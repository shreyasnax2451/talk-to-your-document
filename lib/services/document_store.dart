import 'dart:convert';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqlite3/sqlite3.dart';

import '../models/chat_message.dart';
import '../models/chat_session.dart';
import '../models/document.dart';
import 'text_chunker.dart';

/// A stored chunk returned by a search, with its search score.
class ChunkHit {
  final int id;
  final String docId;
  final int page;
  final String text;
  final double score;

  const ChunkHit({
    required this.id,
    required this.docId,
    required this.page,
    required this.text,
    required this.score,
  });
}

/// On-device store for documents, their chunk text, embedding vectors, a
/// keyword (FTS5) index over the same chunks, and chat history.
///
/// Chunk text is stored next to its vector: the answering model reads the
/// text, the vector only decides which chunks to read.
class DocumentStore {
  final Database _db;

  DocumentStore._(this._db);

  static Future<DocumentStore> open() async {
    final dir = await getApplicationSupportDirectory();
    final db = sqlite3.open(p.join(dir.path, 'docchat.db'));
    db.execute('PRAGMA journal_mode = WAL');
    db.execute('PRAGMA foreign_keys = ON');
    db.execute('''
      CREATE TABLE IF NOT EXISTS documents (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        file_path TEXT NOT NULL,
        page_count INTEGER NOT NULL DEFAULT 0,
        uploaded_at INTEGER NOT NULL,
        status TEXT NOT NULL,
        error_message TEXT,
        embedding_model TEXT,
        embedding_dim INTEGER
      )
    ''');
    db.execute('''
      CREATE TABLE IF NOT EXISTS chunks (
        id INTEGER PRIMARY KEY,
        doc_id TEXT NOT NULL REFERENCES documents(id) ON DELETE CASCADE,
        chunk_index INTEGER NOT NULL,
        page INTEGER NOT NULL,
        text TEXT NOT NULL,
        embedding BLOB NOT NULL
      )
    ''');
    db.execute('''
      CREATE TABLE IF NOT EXISTS pages (
        doc_id TEXT NOT NULL REFERENCES documents(id) ON DELETE CASCADE,
        page INTEGER NOT NULL,
        text TEXT NOT NULL,
        PRIMARY KEY (doc_id, page)
      )
    ''');
    db.execute(
        'CREATE INDEX IF NOT EXISTS chunks_doc_idx ON chunks(doc_id, chunk_index)');
    // rowid of chunks_fts == chunks.id
    db.execute('''
      CREATE VIRTUAL TABLE IF NOT EXISTS chunks_fts USING fts5(
        text, content='chunks', content_rowid='id'
      )
    ''');
    db.execute('''
      CREATE TRIGGER IF NOT EXISTS chunks_ai AFTER INSERT ON chunks BEGIN
        INSERT INTO chunks_fts(rowid, text) VALUES (new.id, new.text);
      END
    ''');
    db.execute('''
      CREATE TRIGGER IF NOT EXISTS chunks_ad AFTER DELETE ON chunks BEGIN
        INSERT INTO chunks_fts(chunks_fts, rowid, text)
          VALUES ('delete', old.id, old.text);
      END
    ''');
    db.execute('''
      CREATE TABLE IF NOT EXISTS chats (
        id TEXT PRIMARY KEY,
        title TEXT NOT NULL,
        created_at INTEGER NOT NULL,
        scope_doc_id TEXT
      )
    ''');
    db.execute('''
      CREATE TABLE IF NOT EXISTS messages (
        id TEXT PRIMARY KEY,
        chat_id TEXT NOT NULL REFERENCES chats(id) ON DELETE CASCADE,
        text TEXT NOT NULL,
        is_user INTEGER NOT NULL,
        created_at INTEGER NOT NULL,
        sources TEXT NOT NULL DEFAULT '[]'
      )
    ''');
    db.execute(
        'CREATE INDEX IF NOT EXISTS messages_chat_idx ON messages(chat_id, created_at)');
    db.execute(
        'CREATE TABLE IF NOT EXISTS settings (key TEXT PRIMARY KEY, value TEXT NOT NULL)');
    return DocumentStore._(db);
  }

  List<Document> loadDocuments() {
    final rows = _db.select(
        'SELECT id, name, file_path, page_count, uploaded_at, status, error_message '
        'FROM documents ORDER BY uploaded_at DESC');
    final pagesByDoc = <String, List<String>>{};
    for (final row in _db.select('SELECT doc_id, text FROM pages ORDER BY doc_id, page')) {
      pagesByDoc.putIfAbsent(row['doc_id'] as String, () => []).add(row['text'] as String);
    }
    return [
      for (final row in rows)
        Document(
          id: row['id'] as String,
          name: row['name'] as String,
          filePath: row['file_path'] as String,
          pageCount: row['page_count'] as int,
          uploadDate: DateTime.fromMillisecondsSinceEpoch(row['uploaded_at'] as int),
          status: DocumentStatus.values.byName(row['status'] as String),
          errorMessage: row['error_message'] as String?,
          progress: 1.0,
          pages: pagesByDoc[row['id']] ?? const [],
        ),
    ];
  }

  void upsertDocument(Document doc) {
    _db.execute('''
      INSERT INTO documents (id, name, file_path, page_count, uploaded_at, status, error_message)
      VALUES (?, ?, ?, ?, ?, ?, ?)
      ON CONFLICT(id) DO UPDATE SET
        name = excluded.name,
        file_path = excluded.file_path,
        page_count = excluded.page_count,
        status = excluded.status,
        error_message = excluded.error_message
    ''', [
      doc.id,
      doc.name,
      doc.filePath,
      doc.pageCount,
      doc.uploadDate.millisecondsSinceEpoch,
      doc.status.name,
      doc.errorMessage,
    ]);
  }

  /// Replaces the page texts and chunks of [docId] and marks it ready, in one
  /// transaction.
  void saveIndex({
    required String docId,
    required List<String> pages,
    required List<TextChunk> chunks,
    required List<Float32List> embeddings,
    required String embeddingModel,
    required int embeddingDim,
  }) {
    assert(chunks.length == embeddings.length);
    _db.execute('BEGIN');
    try {
      _db.execute('DELETE FROM pages WHERE doc_id = ?', [docId]);
      _db.execute('DELETE FROM chunks WHERE doc_id = ?', [docId]);
      final insertPage =
          _db.prepare('INSERT INTO pages (doc_id, page, text) VALUES (?, ?, ?)');
      try {
        for (var i = 0; i < pages.length; i++) {
          insertPage.execute([docId, i + 1, pages[i]]);
        }
      } finally {
        insertPage.close();
      }
      final insert = _db.prepare(
          'INSERT INTO chunks (doc_id, chunk_index, page, text, embedding) '
          'VALUES (?, ?, ?, ?, ?)');
      try {
        for (var i = 0; i < chunks.length; i++) {
          final c = chunks[i];
          insert.execute([
            docId,
            c.chunkIndex,
            c.pageNumber,
            c.text,
            embeddings[i].buffer.asUint8List(
                embeddings[i].offsetInBytes, embeddings[i].lengthInBytes),
          ]);
        }
      } finally {
        insert.close();
      }
      _db.execute(
          "UPDATE documents SET status = 'ready', error_message = NULL, "
          'embedding_model = ?, embedding_dim = ? WHERE id = ?',
          [embeddingModel, embeddingDim, docId]);
      _db.execute('COMMIT');
    } catch (_) {
      _db.execute('ROLLBACK');
      rethrow;
    }
  }

  void renameDocument(String docId, String name) {
    _db.execute('UPDATE documents SET name = ? WHERE id = ?', [name, docId]);
  }

  /// Deletes the document with its pages, chunks, vectors and FTS entries (the
  /// delete trigger removes the FTS rows).
  void deleteDocument(String docId) {
    _db.execute('BEGIN');
    try {
      _db.execute('DELETE FROM pages WHERE doc_id = ?', [docId]);
      _db.execute('DELETE FROM chunks WHERE doc_id = ?', [docId]);
      _db.execute('DELETE FROM documents WHERE id = ?', [docId]);
      _db.execute('COMMIT');
    } catch (_) {
      _db.execute('ROLLBACK');
      rethrow;
    }
  }

  /// Nearest chunks to [query] by cosine similarity (vectors are normalized,
  /// so this is the dot product). Only ready documents indexed with
  /// [embeddingModel] are searched; [docId] limits the search to one document.
  ///
  /// This scans every stored vector, which is fast enough for a phone-sized
  /// library (10,000 chunks ≈ 30 MB of vectors).
  List<ChunkHit> vectorSearch(
    Float32List query, {
    required String embeddingModel,
    String? docId,
    int limit = 20,
  }) {
    final rows = _db.select('''
      SELECT c.id, c.doc_id, c.page, c.embedding FROM chunks c
      JOIN documents d ON d.id = c.doc_id
      WHERE d.status = 'ready' AND d.embedding_model = ?
        AND (? IS NULL OR c.doc_id = ?)
    ''', [embeddingModel, docId, docId]);

    final scored = <(int, String, int, double)>[];
    for (final row in rows) {
      final bytes = row['embedding'] as Uint8List;
      final vector = Float32List.view(
          Uint8List.fromList(bytes).buffer, 0, bytes.lengthInBytes ~/ 4);
      if (vector.length != query.length) continue;
      var dot = 0.0;
      for (var i = 0; i < vector.length; i++) {
        dot += vector[i] * query[i];
      }
      scored.add((row['id'] as int, row['doc_id'] as String, row['page'] as int, dot));
    }
    scored.sort((a, b) => b.$4.compareTo(a.$4));
    final top = scored.take(limit).toList();
    final texts = _chunkTexts([for (final s in top) s.$1]);
    return [
      for (final s in top)
        ChunkHit(id: s.$1, docId: s.$2, page: s.$3, text: texts[s.$1] ?? '', score: s.$4),
    ];
  }

  /// Keyword search over chunk text (FTS5, BM25 ranking). Catches exact terms
  /// such as clause IDs, names and numbers that embeddings can miss.
  List<ChunkHit> keywordSearch(
    String query, {
    required String embeddingModel,
    String? docId,
    int limit = 20,
  }) {
    final match = ftsQuery(query);
    if (match == null) return const [];
    final rows = _db.select('''
      SELECT c.id, c.doc_id, c.page, c.text, bm25(chunks_fts) AS rank
      FROM chunks_fts
      JOIN chunks c ON c.id = chunks_fts.rowid
      JOIN documents d ON d.id = c.doc_id
      WHERE chunks_fts MATCH ? AND d.status = 'ready' AND d.embedding_model = ?
        AND (? IS NULL OR c.doc_id = ?)
      ORDER BY rank
      LIMIT ?
    ''', [match, embeddingModel, docId, docId, limit]);
    return [
      for (final row in rows)
        ChunkHit(
          id: row['id'] as int,
          docId: row['doc_id'] as String,
          page: row['page'] as int,
          text: row['text'] as String,
          score: -(row['rank'] as double), // bm25: lower is better
        ),
    ];
  }

  static const _stopWords = {
    'a', 'about', 'an', 'and', 'are', 'as', 'at', 'be', 'by', 'can', 'do', 'does',
    'for', 'from', 'how', 'i', 'in', 'is', 'it', 'many', 'me', 'much', 'my', 'of',
    'on', 'or', 'should', 'that', 'the', 'there', 'this', 'to', 'was', 'we', 'what',
    'when', 'where', 'which', 'who', 'why', 'will', 'with', 'you', 'your',
  };

  /// Turns free text into an FTS5 query: each meaningful term quoted (so
  /// punctuation such as "EXP-12" is safe) and OR-ed, letting BM25 rank.
  static String? ftsQuery(String text) {
    final terms = RegExp(r'[\p{L}\p{N}][\p{L}\p{N}\-_./]*', unicode: true)
        .allMatches(text.toLowerCase())
        .map((m) => m.group(0)!.replaceAll(RegExp(r'[.\-_/]+$'), ''))
        .where((t) => t.length > 1 && !_stopWords.contains(t))
        .toSet();
    if (terms.isEmpty) return null;
    return terms.map((t) => '"$t"').join(' OR ');
  }

  Map<int, String> _chunkTexts(List<int> ids) {
    if (ids.isEmpty) return const {};
    final placeholders = List.filled(ids.length, '?').join(',');
    return {
      for (final row in _db.select('SELECT id, text FROM chunks WHERE id IN ($placeholders)', ids))
        row['id'] as int: row['text'] as String,
    };
  }

  bool hasReadyDocuments({String? docId}) {
    return _db.select(
      "SELECT 1 FROM documents WHERE status = 'ready' AND (? IS NULL OR id = ?) LIMIT 1",
      [docId, docId],
    ).isNotEmpty;
  }

  List<ChatSession> loadChats() {
    final messagesByChat = <String, List<ChatMessage>>{};
    for (final row in _db.select(
        'SELECT id, chat_id, text, is_user, created_at, sources FROM messages ORDER BY created_at')) {
      messagesByChat.putIfAbsent(row['chat_id'] as String, () => []).add(ChatMessage(
            id: row['id'] as String,
            text: row['text'] as String,
            isUser: row['is_user'] == 1,
            timestamp: DateTime.fromMillisecondsSinceEpoch(row['created_at'] as int),
            sources: [
              for (final s in jsonDecode(row['sources'] as String) as List)
                SourceRef.fromJson(s as Map<String, dynamic>),
            ],
          ));
    }
    return [
      for (final row in _db.select(
          'SELECT id, title, created_at, scope_doc_id FROM chats ORDER BY created_at DESC'))
        ChatSession(
          id: row['id'] as String,
          title: row['title'] as String,
          createdAt: DateTime.fromMillisecondsSinceEpoch(row['created_at'] as int),
          scopeDocumentId: row['scope_doc_id'] as String?,
          messages: messagesByChat[row['id']] ?? [],
        ),
    ];
  }

  void upsertChat(ChatSession chat) {
    _db.execute('''
      INSERT INTO chats (id, title, created_at, scope_doc_id) VALUES (?, ?, ?, ?)
      ON CONFLICT(id) DO UPDATE SET title = excluded.title, scope_doc_id = excluded.scope_doc_id
    ''', [chat.id, chat.title, chat.createdAt.millisecondsSinceEpoch, chat.scopeDocumentId]);
  }

  /// Saves a message (and its chat row, if this is the chat's first message).
  void saveMessage(ChatSession chat, ChatMessage message) {
    upsertChat(chat);
    _db.execute('''
      INSERT INTO messages (id, chat_id, text, is_user, created_at, sources) VALUES (?, ?, ?, ?, ?, ?)
      ON CONFLICT(id) DO UPDATE SET text = excluded.text, sources = excluded.sources
    ''', [
      message.id,
      chat.id,
      message.text,
      message.isUser ? 1 : 0,
      message.timestamp.millisecondsSinceEpoch,
      jsonEncode([for (final s in message.sources) s.toJson()]),
    ]);
  }

  void deleteMessage(String messageId) {
    _db.execute('DELETE FROM messages WHERE id = ?', [messageId]);
  }

  void deleteChat(String chatId) {
    _db.execute('DELETE FROM messages WHERE chat_id = ?', [chatId]);
    _db.execute('DELETE FROM chats WHERE id = ?', [chatId]);
  }

  String? getSetting(String key) {
    final rows = _db.select('SELECT value FROM settings WHERE key = ?', [key]);
    return rows.isEmpty ? null : rows.first['value'] as String;
  }

  void setSetting(String key, String value) {
    _db.execute(
        'INSERT INTO settings (key, value) VALUES (?, ?) '
        'ON CONFLICT(key) DO UPDATE SET value = excluded.value',
        [key, value]);
  }

  int chunkCount(String docId) {
    return _db.select('SELECT COUNT(*) AS n FROM chunks WHERE doc_id = ?',
        [docId]).first['n'] as int;
  }

  void close() => _db.close();
}

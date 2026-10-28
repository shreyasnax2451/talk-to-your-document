import 'dart:async';
import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import 'package:file_picker/file_picker.dart';
import '../models/document.dart';
import '../models/chat_message.dart';
import '../models/chat_session.dart';
import '../services/answer_service.dart';
import '../services/document_indexer.dart';
import '../services/document_store.dart';
import '../services/embedding_service.dart';
import '../services/indexing_notifications.dart';
import '../services/model_config.dart';
import '../services/model_manager.dart';
import '../services/retriever.dart';

class AppState extends ChangeNotifier {
  final _uuid = const Uuid();

  List<Document> _documents = [];
  final List<ChatSession> _chatSessions = [];
  String _activeChatId = '';
  String? _scopeDocumentId; // null = 'All documents'
  bool _isGenerating = false;

  DocumentStore? _store;
  DocumentIndexer? _indexer;
  Retriever? _retriever;
  final ModelManager models;
  late final EmbeddingService _embeddings = EmbeddingService(models);
  final AnswerService _answers = AnswerService();
  late final Future<void> _storageReady;
  late final AppLifecycleListener _lifecycle;

  final IndexingNotifications _notifications = IndexingNotifications();
  int _indexingJobs = 0;
  int _batchIndexed = 0;
  int _batchFailed = 0;

  static const _answerModelKey = 'answer_model';
  ModelSpec? _answerModel;
  bool _storageLoaded = false;

  AppState(this.models) {
    createNewChat();
    _storageReady = _initStorage();
    _notifications.init();
    // Free the ~3 GB answering model when the app goes to the background; it
    // reloads on the next question.
    _lifecycle = AppLifecycleListener(onPause: () {
      if (!_isGenerating) _answers.unload();
    });
  }

  Future<void> _initStorage() async {
    final DocumentStore store;
    try {
      store = await DocumentStore.open();
    } catch (e) {
      debugPrint('Opening the document store failed: $e');
      return;
    }
    _store = store;
    _indexer = DocumentIndexer(store: store, embeddings: _embeddings);
    _retriever = Retriever(store: store, embeddings: _embeddings);
    _documents = store.loadDocuments();
    // A job still marked processing was cut off when the app last closed.
    for (final doc in _documents.where((d) => d.status == DocumentStatus.processing)) {
      doc.status = DocumentStatus.failed;
      doc.errorMessage = 'Indexing was interrupted. Tap to retry.';
      store.upsertDocument(doc);
    }
    // Keep the fresh "New chat" on top, followed by saved chats.
    _chatSessions.addAll(store.loadChats().where((c) => c.id != _activeChatId));
    _answerModel = ModelConfig.answeringModelById(store.getSetting(_answerModelKey));
    _storageLoaded = true;
    notifyListeners();
  }

  /// The answering model the user chose; null until they pick one.
  ModelSpec? get answerModel => _answerModel;

  /// True on first launch, before an answering model has been chosen.
  bool get needsModelSetup => _storageLoaded && _answerModel == null;

  /// Saves [model] as the answering model and starts its background
  /// download if it is not on the phone yet.
  Future<void> selectAnswerModel(ModelSpec model, {bool wifiOnly = false}) async {
    await _storageReady;
    _answerModel = model;
    _store?.setSetting(_answerModelKey, model.id);
    notifyListeners();
    await models.download(model, wifiOnly: wifiOnly);
    if (!_isGenerating) await _answers.unload();
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    _answers.dispose();
    _embeddings.dispose();
    _store?.close();
    super.dispose();
  }

  List<Document> get documents => List.unmodifiable(_documents);
  List<ChatSession> get chatSessions => List.unmodifiable(_chatSessions);
  String get activeChatId => _activeChatId;
  String? get scopeDocumentId => _scopeDocumentId;
  bool get isGenerating => _isGenerating;

  ChatSession get activeChat {
    final index = _chatSessions.indexWhere((c) => c.id == _activeChatId);
    if (index != -1) {
      return _chatSessions[index];
    }
    if (_chatSessions.isEmpty) {
      final newChat = ChatSession(
        id: _uuid.v4(),
        title: 'New chat',
        createdAt: DateTime.now(),
        scopeDocumentId: _scopeDocumentId,
      );
      _chatSessions.add(newChat);
      _activeChatId = newChat.id;
      return newChat;
    }
    return _chatSessions.first;
  }

  Document? get currentScopeDocument {
    if (_scopeDocumentId == null) return null;
    return _documents.where((d) => d.id == _scopeDocumentId).firstOrNull;
  }

  String get scopeDisplayName {
    final doc = currentScopeDocument;
    if (doc != null) {
      return doc.name;
    }
    return 'All documents';
  }

  List<Document> searchDocuments(String query) {
    if (query.trim().isEmpty) return _documents;
    final q = query.toLowerCase();
    return _documents.where((doc) => doc.name.toLowerCase().contains(q)).toList();
  }

  void selectChat(String chatId) {
    final chat = _chatSessions.where((c) => c.id == chatId).firstOrNull;
    if (chat == null) return;
    _activeChatId = chatId;
    _scopeDocumentId = chat.scopeDocumentId;
    notifyListeners();
  }

  void createNewChat({String? scopeDocumentId}) {
    // Reuse an untouched "New chat" instead of stacking empty ones.
    final empty = _chatSessions.where((c) => c.messages.isEmpty).firstOrNull;
    if (empty != null) {
      _chatSessions.remove(empty);
      empty.scopeDocumentId = scopeDocumentId;
      _chatSessions.insert(0, empty);
      _activeChatId = empty.id;
      _scopeDocumentId = scopeDocumentId;
      notifyListeners();
      return;
    }
    final newChat = ChatSession(
      id: _uuid.v4(),
      title: 'New chat',
      createdAt: DateTime.now(),
      scopeDocumentId: scopeDocumentId,
    );
    _chatSessions.insert(0, newChat);
    _activeChatId = newChat.id;
    _scopeDocumentId = scopeDocumentId;
    notifyListeners();
  }

  void renameChat(String chatId, String newTitle) {
    final index = _chatSessions.indexWhere((c) => c.id == chatId);
    if (index != -1 && newTitle.trim().isNotEmpty) {
      _chatSessions[index].title = newTitle.trim();
      _persistChat(_chatSessions[index]);
      notifyListeners();
    }
  }

  void deleteChat(String chatId) {
    if (_isGenerating && chatId == _activeChatId) stopGeneration();
    _chatSessions.removeWhere((c) => c.id == chatId);
    _store?.deleteChat(chatId);
    if (_activeChatId == chatId) {
      if (_chatSessions.isNotEmpty) {
        _activeChatId = _chatSessions.first.id;
        _scopeDocumentId = _chatSessions.first.scopeDocumentId;
      } else {
        createNewChat();
      }
    }
    notifyListeners();
  }

  void setScope(String? docId) {
    _scopeDocumentId = docId;
    activeChat.scopeDocumentId = docId;
    _persistChat(activeChat);
    notifyListeners();
  }

  /// Chats are stored once they have messages; empty "New chat"s are not.
  void _persistChat(ChatSession chat) {
    if (chat.messages.isNotEmpty) _store?.upsertChat(chat);
  }

  /// Lets the user pick a PDF, adds it to the library and starts indexing in
  /// the background. Returns whether a document was added.
  Future<bool> pickAndUploadDocument() async {
    final List<PlatformFile> files;
    try {
      files = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf'],
      );
    } catch (e) {
      debugPrint('File picker failed: $e');
      return false;
    }
    if (files.isEmpty || files.first.path == null) return false;
    final file = files.first;

    await _storageReady;
    if (_store == null) return false;
    final doc = Document(
      id: _uuid.v4(),
      name: file.name,
      pageCount: 0,
      uploadDate: DateTime.now(),
      status: DocumentStatus.processing,
      progress: 0.0,
    );
    _documents.insert(0, doc);
    notifyListeners();
    unawaited(_importAndIndex(doc, file.path!));
    return true;
  }

  Future<void> _importAndIndex(Document doc, String sourcePath) async {
    try {
      doc.filePath = await DocumentIndexer.importFile(sourcePath, doc.id);
    } catch (e) {
      _markFailed(doc, 'Could not copy this file.');
      return;
    }
    if (!_documents.contains(doc)) {
      // Deleted while the file was being copied.
      await DocumentIndexer.deleteFile(doc.filePath);
      return;
    }
    _store!.upsertDocument(doc);
    await _indexDocument(doc);
  }

  Future<void> _indexDocument(Document doc) async {
    // Jobs run one at a time in the indexer; these count the current batch
    // for the notification.
    _indexingJobs++;
    var succeeded = false;
    try {
      await _indexer!.index(
        docId: doc.id,
        title: doc.name,
        filePath: doc.filePath!,
        onPages: (pages) {
          if (!_documents.contains(doc)) return;
          doc.pages = pages;
          doc.pageCount = pages.length;
          _store!.upsertDocument(doc);
          notifyListeners();
        },
        onProgress: (progress) {
          if (!_documents.contains(doc)) return;
          doc.progress = progress;
          notifyListeners();
          _notifications.progress(docName: doc.name, progress: progress, queued: _indexingJobs - 1);
        },
      );
      if (!_documents.contains(doc)) return;
      succeeded = true;
      doc.status = DocumentStatus.ready;
      doc.progress = 1.0;
      doc.errorMessage = null;
      notifyListeners();
    } catch (e) {
      debugPrint('Indexing ${doc.name} failed: $e');
      _markFailed(doc, e is IndexingException ? e.message : "Couldn't index this file");
    } finally {
      _indexingJobs--;
      if (succeeded) {
        _batchIndexed++;
      } else if (_documents.contains(doc)) {
        _batchFailed++;
      }
      if (_indexingJobs == 0) {
        _notifications.finished(ready: _batchIndexed, failed: _batchFailed);
        _batchIndexed = 0;
        _batchFailed = 0;
      }
    }
  }

  void _markFailed(Document doc, String message) {
    if (!_documents.contains(doc)) return;
    doc.status = DocumentStatus.failed;
    doc.errorMessage = message;
    _store?.upsertDocument(doc);
    notifyListeners();
  }

  void retryProcessing(String docId) {
    final doc = _documents.where((d) => d.id == docId).firstOrNull;
    if (doc == null || doc.filePath == null || doc.status == DocumentStatus.processing) return;
    doc.status = DocumentStatus.processing;
    doc.progress = 0.0;
    doc.errorMessage = null;
    _store?.upsertDocument(doc);
    notifyListeners();
    _indexDocument(doc);
  }

  void renameDocument(String docId, String newName) {
    final index = _documents.indexWhere((d) => d.id == docId);
    if (index != -1 && newName.trim().isNotEmpty) {
      _documents[index].name = newName.trim();
      _store?.renameDocument(docId, newName.trim());
      notifyListeners();
    }
  }

  void deleteDocument(String docId) {
    final doc = _documents.where((d) => d.id == docId).firstOrNull;
    if (doc == null) return;
    _documents.remove(doc);
    _store?.deleteDocument(docId);
    DocumentIndexer.deleteFile(doc.filePath);
    if (_scopeDocumentId == docId) {
      _scopeDocumentId = null;
    }
    for (final chat in _chatSessions.where((c) => c.scopeDocumentId == docId)) {
      chat.scopeDocumentId = null;
      _persistChat(chat);
    }
    notifyListeners();
  }

  Document? getDocumentById(String id) {
    return _documents.where((d) => d.id == id).firstOrNull;
  }

  Future<void> sendMessage(String text) async {
    if (text.trim().isEmpty || _isGenerating) return;
    final chat = activeChat;

    final userMessage = ChatMessage(
      id: _uuid.v4(),
      text: text.trim(),
      isUser: true,
      timestamp: DateTime.now(),
    );
    chat.messages.add(userMessage);

    // Auto-title chat session if still default
    if (chat.title == 'New chat') {
      final trimmed = text.trim();
      chat.title = trimmed.length > 28 ? '${trimmed.substring(0, 25)}...' : trimmed;
    }
    _store?.saveMessage(chat, userMessage);

    await _answer(chat, userMessage.text);
  }

  Future<void> regenerateLastAnswer() async {
    final chat = activeChat;
    if (_isGenerating || chat.messages.isEmpty) return;
    final lastUser = chat.messages.lastWhere((m) => m.isUser, orElse: () => chat.messages.first);
    if (!lastUser.isUser) return;
    if (!chat.messages.last.isUser) {
      _store?.deleteMessage(chat.messages.removeLast().id);
    }
    await _answer(chat, lastUser.text);
  }

  void stopGeneration() => _answers.stop();

  /// Retrieves passages for [question] and streams Qwen3-4B's answer into a
  /// new assistant message on [chat].
  Future<void> _answer(ChatSession chat, String question) async {
    _isGenerating = true;
    final reply = ChatMessage(
      id: _uuid.v4(),
      text: '',
      isUser: false,
      timestamp: DateTime.now(),
      isStreaming: true,
    );
    chat.messages.add(reply);
    notifyListeners();

    void status(String s) {
      reply.statusText = s;
      notifyListeners();
    }

    final pending = StringBuffer();
    Timer? flushTimer;
    void flush() {
      flushTimer = null;
      if (pending.isEmpty) return;
      reply.text += pending.toString();
      reply.statusText = null;
      pending.clear();
      notifyListeners();
    }

    try {
      await _storageReady;
      final store = _store;
      final docId = chat.scopeDocumentId;
      if (store == null) {
        reply.text = "Couldn't open the on-device database.";
      } else if (!store.hasReadyDocuments(docId: docId)) {
        reply.text = docId == null
            ? 'There are no indexed documents yet. Upload a PDF from the Library, '
                'wait for it to finish indexing, then ask again.'
            : 'This document is not ready yet. Wait for indexing to finish, '
                'or choose "All documents".';
      } else if (_answerModel == null) {
        reply.text = 'Choose an answering model first: open the menu, tap your '
            'profile, then "Answering model".';
      } else if (_modelNotReadyMessage(ModelConfig.embedding) case final message?) {
        reply.text = message;
      } else if (_modelNotReadyMessage(_answerModel!) case final message?) {
        reply.text = message;
      } else {
        final model = _answerModel!;
        status('Searching your documents…');
        final hits = await _retriever!.retrieve(question, docId: docId);
        if (hits.isEmpty) {
          reply.text = AnswerService.notFoundReply;
        } else {
          if (!_answers.isLoaded(model)) {
            status('Loading ${model.displayName}…');
            await _answers.load(model);
          }
          status('Reading ${hits.length} passages…');
          final docNames = {for (final d in _documents) d.id: d.name};
          final passages = AnswerService.toPassages(hits, docNames);
          await for (final delta in _answers.answer(model, question, passages)) {
            pending.write(delta);
            flushTimer ??= Timer(const Duration(milliseconds: 50), flush);
          }
          flushTimer?.cancel();
          flush();
          _applyCitations(reply, hits, docNames);
        }
      }
    } catch (e) {
      debugPrint('Answering failed: $e');
      flushTimer?.cancel();
      flush();
      if (reply.text.isEmpty) reply.text = "Couldn't answer: $e";
    } finally {
      reply.text = reply.text.trim();
      if (reply.text.isEmpty) reply.text = 'Stopped.';
      reply.statusText = null;
      reply.isStreaming = false;
      _isGenerating = false;
      if (chat.messages.contains(reply)) _store?.saveMessage(chat, reply);
      notifyListeners();
    }
  }

  /// Why [model] cannot be used yet, or null when it is downloaded. Starts the
  /// download again if it is missing or failed.
  String? _modelNotReadyMessage(ModelSpec model) {
    final state = models.stateOf(model);
    switch (state.status) {
      case ModelStatus.ready:
        return null;
      case ModelStatus.downloading || ModelStatus.paused:
        return '${model.displayName} is still downloading '
            '(${(state.progress * 100).toStringAsFixed(0)}%). '
            'Ask again once the download finishes.';
      case ModelStatus.verifying:
        return '${model.displayName} has downloaded and is being checked. '
            'Ask again in a moment.';
      case ModelStatus.notDownloaded || ModelStatus.failed:
        unawaited(models.download(model));
        return '${model.displayName} is not on this phone yet. The download '
            'has started (${model.sizeLabel}); ask again once it finishes.';
    }
  }

  /// Turns the model's passage citations ([1], [2]...) into page citations
  /// ([p. 3]) and records the cited pages as the answer's sources.
  void _applyCitations(ChatMessage reply, List<ChunkHit> hits, Map<String, String> docNames) {
    if (reply.text.trim() == AnswerService.notFoundReply) return;
    final cited = <int>[];
    reply.text = reply.text.replaceAllMapped(RegExp(r'\[(\d+)\]'), (m) {
      final i = int.parse(m.group(1)!) - 1;
      if (i < 0 || i >= hits.length) return '';
      if (!cited.contains(i)) cited.add(i);
      return '[p. ${hits[i].page}]';
    });
    // If the model cited nothing, show everything it was given.
    final used = cited.isEmpty ? List.generate(hits.length, (i) => i) : cited;
    final seen = <String>{};
    reply.sources = [
      for (final i in used)
        if (seen.add('${hits[i].docId}:${hits[i].page}'))
          SourceRef(docId: hits[i].docId, docName: docNames[hits[i].docId] ?? 'Document', page: hits[i].page),
    ];
  }
}

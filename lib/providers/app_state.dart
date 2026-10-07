import 'dart:async';
import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import 'package:file_picker/file_picker.dart';
import '../models/document.dart';
import '../models/chat_message.dart';
import '../models/chat_session.dart';
import '../data/sample_documents.dart';

class AppState extends ChangeNotifier {
  final _uuid = const Uuid();

  List<Document> _documents = [];
  List<ChatSession> _chatSessions = [];
  String _activeChatId = '';
  String? _scopeDocumentId; // null = 'All documents'
  bool _isGenerating = false;

  AppState() {
    _initData();
  }

  void _initData() {
    _documents = SampleData.getInitialDocuments();
    _chatSessions = SampleData.getInitialChatSessions();
    if (_chatSessions.isNotEmpty) {
      _activeChatId = _chatSessions.first.id;
      _scopeDocumentId = _chatSessions.first.scopeDocumentId;
    } else {
      createNewChat();
    }
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
    _activeChatId = chatId;
    final chat = _chatSessions.firstWhere((c) => c.id == chatId);
    _scopeDocumentId = chat.scopeDocumentId;
    notifyListeners();
  }

  void createNewChat({String? scopeDocumentId}) {
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
      notifyListeners();
    }
  }

  void deleteChat(String chatId) {
    _chatSessions.removeWhere((c) => c.id == chatId);
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
    notifyListeners();
  }

  Future<void> pickAndUploadDocument() async {
    try {
      final files = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf'],
      );

      if (files.isNotEmpty) {
        final file = files.first;
        final newDoc = Document(
          id: _uuid.v4(),
          name: file.name,
          pageCount: 12,
          uploadDate: DateTime.now(),
          status: DocumentStatus.processing,
          progress: 0.1,
          filePath: file.path,
          pages: [
            'Preview of ${file.name}\n\nUploaded file content indexed successfully for conversational query.'
          ],
        );
        _documents.insert(0, newDoc);
        notifyListeners();
        _simulateProcessing(newDoc.id);
      } else {
        // Add a demo upload if user dismissed picker
        _addDemoUpload();
      }
    } catch (e) {
      _addDemoUpload();
    }
  }

  void _addDemoUpload() {
    final demoDoc = Document(
      id: _uuid.v4(),
      name: 'Product Roadmap 2027.pdf',
      pageCount: 24,
      uploadDate: DateTime.now(),
      status: DocumentStatus.processing,
      progress: 0.15,
      pages: [
        'PRODUCT ROADMAP 2027\nStrategic Vision & Release Milestones\n\n• Q1: Multi-modal document intelligence.\n• Q2: Cross-document semantic correlation engine.\n• Q3: Enterprise fine-tuned on-device models.'
      ],
    );
    _documents.insert(0, demoDoc);
    notifyListeners();
    _simulateProcessing(demoDoc.id);
  }

  void _simulateProcessing(String docId) {
    Timer.periodic(const Duration(milliseconds: 600), (timer) {
      final index = _documents.indexWhere((d) => d.id == docId);
      if (index == -1) {
        timer.cancel();
        return;
      }
      final doc = _documents[index];
      if (doc.progress < 0.85) {
        doc.progress += 0.25;
        notifyListeners();
      } else {
        doc.progress = 1.0;
        doc.status = DocumentStatus.ready;
        timer.cancel();
        notifyListeners();
      }
    });
  }

  void retryProcessing(String docId) {
    final index = _documents.indexWhere((d) => d.id == docId);
    if (index != -1) {
      _documents[index].status = DocumentStatus.processing;
      _documents[index].progress = 0.2;
      _documents[index].errorMessage = null;
      notifyListeners();
      _simulateProcessing(docId);
    }
  }

  void renameDocument(String docId, String newName) {
    final index = _documents.indexWhere((d) => d.id == docId);
    if (index != -1 && newName.trim().isNotEmpty) {
      _documents[index].name = newName.trim();
      notifyListeners();
    }
  }

  void deleteDocument(String docId) {
    _documents.removeWhere((d) => d.id == docId);
    if (_scopeDocumentId == docId) {
      _scopeDocumentId = null;
    }
    notifyListeners();
  }

  Document? getDocumentByName(String name) {
    return _documents.where((d) => d.name == name).firstOrNull;
  }

  Future<void> sendMessage(String text) async {
    if (text.trim().isEmpty || _isGenerating) return;

    final userMessage = ChatMessage(
      id: _uuid.v4(),
      text: text.trim(),
      isUser: true,
      timestamp: DateTime.now(),
    );

    activeChat.messages.add(userMessage);

    // Auto-title chat session if still default
    if (activeChat.messages.length == 1 || activeChat.title == 'New chat') {
      final trimmed = text.trim();
      activeChat.title = trimmed.length > 28 ? '${trimmed.substring(0, 25)}...' : trimmed;
    }

    _isGenerating = true;
    notifyListeners();

    // Determine context and answer
    final prompt = text.trim().toLowerCase();
    String answer = '';
    List<String> sources = [];

    final scopeDoc = currentScopeDocument;

    if (scopeDoc != null) {
      sources.add(scopeDoc.name);
      if (scopeDoc.name.contains('Lease')) {
        if (prompt.contains('end') || prompt.contains('rent') || prompt.contains('increase') || prompt.contains('date')) {
          answer = 'Your lease ends on March 31, 2027.\n\nThe rent increases by 4% at renewal, taking it from \$1,850 to \$1,924 per month.';
        } else if (prompt.contains('deposit') || prompt.contains('security')) {
          answer = 'The security deposit is \$1,850.00, held in an interest-bearing escrow account at First Horizon Bank and returnable within 30 days of lease conclusion.';
        } else if (prompt.contains('summarize') || prompt.contains('summary')) {
          answer = 'This is a Residential Lease Agreement for Suite 402 at Oakwood Residences running through March 31, 2027. Monthly base rent is \$1,850 with a scheduled 4% renewal adjustment to \$1,924/month.';
        } else {
          answer = 'According to ${scopeDoc.name}, the term runs until March 31, 2027 with a base rent of \$1,850/month and standard 60-day non-renewal notification clauses.';
        }
      } else if (scopeDoc.name.contains('financial') || scopeDoc.name.contains('Q3')) {
        if (prompt.contains('revenue') || prompt.contains('driver')) {
          answer = 'Consolidated Q3 revenue reached \$48.2M (+14.2% YoY), predominantly driven by Enterprise Cloud which expanded 22% YoY to \$27.1M.';
        } else if (prompt.contains('cash') || prompt.contains('balance') || prompt.contains('debt')) {
          answer = 'The company ended Q3 with \$94.5M in cash & equivalents, zero long-term debt, and generated \$11.4M in quarterly operating cash flow.';
        } else {
          answer = 'In Q3, consolidated revenue grew 14.2% YoY to \$48.2M with gross margin expanding to 68.4% and adjusted EBITDA margin reaching 23.0%.';
        }
      } else {
        answer = 'Based on the contents of ${scopeDoc.name}, the key points indicate strong operational milestones, with deliverables scheduled across the upcoming quarters.';
      }
    } else {
      // All documents search
      if (prompt.contains('lease') || prompt.contains('rent') || prompt.contains('landlord')) {
        sources.add('Lease agreement.pdf');
        answer = 'Your lease ends on March 31, 2027. The rent increases by 4% at renewal, taking it from \$1,850 to \$1,924 per month.';
      } else if (prompt.contains('revenue') || prompt.contains('q3') || prompt.contains('margin') || prompt.contains('financial')) {
        sources.add('Q3 financial report.pdf');
        answer = 'Q3 consolidated revenue totaled \$48.2M (+14.2% YoY). Enterprise Cloud drove growth (+22% YoY to \$27.1M) and subscription ARR reached \$38.6M.';
      } else if (prompt.contains('date') || prompt.contains('key dates')) {
        sources.add('Lease agreement.pdf');
        sources.add('Q3 financial report.pdf');
        answer = 'Key dates identified across your library:\n• March 31, 2027: Lease expiration date for Suite 402.\n• Sep 24, 2026: Q3 Financial reporting close date.\n• 60 days before expiration: Notice of non-renewal window.';
      } else if (prompt.contains('action item') || prompt.contains('actions')) {
        sources.add('Lease agreement.pdf');
        sources.add('Q3 financial report.pdf');
        answer = 'Key action items found in your documents:\n1. Provide written notice 60 days prior to March 31, 2027 regarding lease continuation.\n2. Review Q4 guidance targets (\$51M - \$53.5M).\n3. Maintain required tenant utility accounts.';
      } else {
        sources.add('Lease agreement.pdf');
        sources.add('Q3 financial report.pdf');
        answer = 'Searching across all documents in your library, your documents include lease terms for Suite 402 through March 2027 and Q3 consolidated financial performance with \$48.2M revenue.';
      }
    }

    // Stream the assistant response word by word
    final assistantMessage = ChatMessage(
      id: _uuid.v4(),
      text: '',
      isUser: false,
      timestamp: DateTime.now(),
      sourceFileNames: sources,
      isStreaming: true,
    );

    activeChat.messages.add(assistantMessage);
    notifyListeners();

    final words = answer.split(' ');
    int wordIndex = 0;

    Timer.periodic(const Duration(milliseconds: 38), (timer) {
      if (wordIndex < words.length) {
        if (wordIndex == 0) {
          assistantMessage.text = words[0];
        } else {
          assistantMessage.text += ' ${words[wordIndex]}';
        }
        wordIndex++;
        notifyListeners();
      } else {
        assistantMessage.isStreaming = false;
        _isGenerating = false;
        timer.cancel();
        notifyListeners();
      }
    });
  }

  Future<void> regenerateLastAnswer() async {
    if (_isGenerating || activeChat.messages.isEmpty) return;
    
    // Find last user prompt
    String? lastUserPrompt;
    for (int i = activeChat.messages.length - 1; i >= 0; i--) {
      if (activeChat.messages[i].isUser) {
        lastUserPrompt = activeChat.messages[i].text;
        break;
      }
    }

    if (lastUserPrompt != null) {
      // Remove last assistant message if exists
      if (!activeChat.messages.last.isUser) {
        activeChat.messages.removeLast();
        notifyListeners();
      }
      await sendMessage(lastUserPrompt);
    }
  }
}

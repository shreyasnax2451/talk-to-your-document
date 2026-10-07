import 'chat_message.dart';

class ChatSession {
  final String id;
  String title;
  final DateTime createdAt;
  String? scopeDocumentId; // null = 'All documents'
  List<ChatMessage> messages;

  ChatSession({
    required this.id,
    required this.title,
    required this.createdAt,
    this.scopeDocumentId,
    List<ChatMessage>? messages,
  }) : messages = messages ?? [];

  ChatSession copyWith({
    String? id,
    String? title,
    DateTime? createdAt,
    String? scopeDocumentId,
    List<ChatMessage>? messages,
  }) {
    return ChatSession(
      id: id ?? this.id,
      title: title ?? this.title,
      createdAt: createdAt ?? this.createdAt,
      scopeDocumentId: scopeDocumentId ?? this.scopeDocumentId,
      messages: messages ?? List.from(this.messages),
    );
  }
}

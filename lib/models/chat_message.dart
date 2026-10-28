/// A cited passage location: which document and page an answer drew on.
class SourceRef {
  final String docId;
  final String docName;
  final int page;

  const SourceRef({
    required this.docId,
    required this.docName,
    required this.page,
  });

  Map<String, Object> toJson() => {'docId': docId, 'docName': docName, 'page': page};

  factory SourceRef.fromJson(Map<String, dynamic> json) => SourceRef(
        docId: json['docId'] as String,
        docName: json['docName'] as String,
        page: json['page'] as int,
      );
}

class ChatMessage {
  final String id;
  String text;
  final bool isUser;
  final DateTime timestamp;
  List<SourceRef> sources;
  bool isStreaming;

  /// Progress shown while an answer has no text yet (not persisted).
  String? statusText;

  ChatMessage({
    required this.id,
    required this.text,
    required this.isUser,
    required this.timestamp,
    this.sources = const [],
    this.isStreaming = false,
  });

  ChatMessage copyWith({
    String? id,
    String? text,
    bool? isUser,
    DateTime? timestamp,
    List<SourceRef>? sources,
    bool? isStreaming,
  }) {
    return ChatMessage(
      id: id ?? this.id,
      text: text ?? this.text,
      isUser: isUser ?? this.isUser,
      timestamp: timestamp ?? this.timestamp,
      sources: sources ?? this.sources,
      isStreaming: isStreaming ?? this.isStreaming,
    );
  }
}

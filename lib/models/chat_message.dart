class ChatMessage {
  final String id;
  String text;
  final bool isUser;
  final DateTime timestamp;
  final List<String> sourceFileNames;
  bool isStreaming;

  ChatMessage({
    required this.id,
    required this.text,
    required this.isUser,
    required this.timestamp,
    this.sourceFileNames = const [],
    this.isStreaming = false,
  });

  ChatMessage copyWith({
    String? id,
    String? text,
    bool? isUser,
    DateTime? timestamp,
    List<String>? sourceFileNames,
    bool? isStreaming,
  }) {
    return ChatMessage(
      id: id ?? this.id,
      text: text ?? this.text,
      isUser: isUser ?? this.isUser,
      timestamp: timestamp ?? this.timestamp,
      sourceFileNames: sourceFileNames ?? this.sourceFileNames,
      isStreaming: isStreaming ?? this.isStreaming,
    );
  }
}

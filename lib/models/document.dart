enum DocumentStatus {
  ready,
  processing,
  failed,
}

class Document {
  final String id;
  String name;
  int pageCount;
  final DateTime uploadDate;
  DocumentStatus status;
  double progress; // 0.0 to 1.0
  String? errorMessage;
  String? filePath;
  List<String> pages;

  Document({
    required this.id,
    required this.name,
    required this.pageCount,
    required this.uploadDate,
    required this.status,
    this.progress = 1.0,
    this.errorMessage,
    this.filePath,
    this.pages = const [],
  });

  Document copyWith({
    String? id,
    String? name,
    int? pageCount,
    DateTime? uploadDate,
    DocumentStatus? status,
    double? progress,
    String? errorMessage,
    String? filePath,
    List<String>? pages,
  }) {
    return Document(
      id: id ?? this.id,
      name: name ?? this.name,
      pageCount: pageCount ?? this.pageCount,
      uploadDate: uploadDate ?? this.uploadDate,
      status: status ?? this.status,
      progress: progress ?? this.progress,
      errorMessage: errorMessage ?? this.errorMessage,
      filePath: filePath ?? this.filePath,
      pages: pages ?? this.pages,
    );
  }
}

class Document {
  int? id;

  String title;
  String type; // pdf/image/word/excel/note
  String rawContent; // 原始格式内容，用于用户预览
  String aiContent; // 提取的纯文本内容，用于AI解析
  List<double> embedding; // 文本嵌入向量
  DateTime createdAt;
  String? filePath; // 原始文件路径

  Document({
    this.id,
    required this.title,
    required this.type,
    required this.rawContent,
    required this.aiContent,
    required this.embedding,
    required this.createdAt,
    this.filePath,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'title': title,
      'type': type,
      'content': rawContent, // 兼容旧版本，使用rawContent作为content存储
      'ai_content': aiContent, // 新增字段，用于存储AI解析的内容
      'embedding': embedding.join(','),
      'createdAt': createdAt.millisecondsSinceEpoch,
      'filePath': filePath,
    };
  }

  factory Document.fromMap(Map<String, dynamic> map) {
    return Document(
      id: map['id'],
      title: map['title'],
      type: map['type'],
      rawContent: map['content'], // 兼容旧版本，从content字段读取rawContent
      aiContent: map['ai_content'] ?? map['content'], // 如果有ai_content字段则使用，否则使用content
      embedding: (map['embedding'] as String).split(',').map(double.parse).toList(),
      createdAt: DateTime.fromMillisecondsSinceEpoch(map['createdAt']),
      filePath: map['filePath'],
    );
  }
}

class ChatMediaAttachment {
  const ChatMediaAttachment({
    required this.kind,
    required this.url,
    required this.fileName,
    required this.mimeType,
    required this.sizeBytes,
  });

  final String kind;
  final String url;
  final String fileName;
  final String mimeType;
  final int sizeBytes;
}

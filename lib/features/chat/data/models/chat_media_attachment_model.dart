import '../../domain/entities/chat_media_attachment.dart';

class ChatMediaAttachmentModel extends ChatMediaAttachment {
  const ChatMediaAttachmentModel({
    required super.kind,
    required super.url,
    required super.fileName,
    required super.mimeType,
    required super.sizeBytes,
  });

  factory ChatMediaAttachmentModel.fromJson(Map<String, dynamic> json) {
    return ChatMediaAttachmentModel(
      kind: (json['kind'] ?? '').toString(),
      url: (json['url'] ?? '').toString(),
      fileName: (json['fileName'] ?? '').toString(),
      mimeType: (json['mimeType'] ?? '').toString(),
      sizeBytes: (json['sizeBytes'] as num?)?.toInt() ?? 0,
    );
  }
}

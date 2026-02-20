class ChatMessage {
  const ChatMessage({
    required this.id,
    required this.chatId,
    required this.senderId,
    required this.text,
    required this.type,
    required this.createdAt,
    this.readAt,
  });

  final String id;
  final String chatId;
  final String senderId;
  final String text;
  final String type;
  final DateTime createdAt;
  final DateTime? readAt;

  bool get isSticker => type == 'sticker';
  bool get isImage => type == 'image';
  bool get isVideo => type == 'video';
  bool get isVoice => type == 'voice';
  bool get isMedia => isImage || isVideo || isVoice;
  bool get isRead => readAt != null;
}

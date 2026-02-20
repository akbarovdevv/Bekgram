import '../../domain/entities/chat_message.dart';

class ChatMessageModel extends ChatMessage {
  const ChatMessageModel({
    required super.id,
    required super.chatId,
    required super.senderId,
    required super.text,
    required super.type,
    required super.createdAt,
    super.readAt,
  });

  factory ChatMessageModel.fromJson(Map<String, dynamic> json) {
    return ChatMessageModel(
      id: (json['id'] ?? '').toString(),
      chatId: (json['chatId'] ?? '').toString(),
      senderId: (json['senderId'] ?? '').toString(),
      text: (json['text'] ?? '').toString(),
      type: (json['type'] ?? 'text').toString(),
      createdAt: _readDateTime(json['createdAt']),
      readAt: _readNullableDateTime(json['readAt']),
    );
  }

  ChatMessageModel copyWith({
    DateTime? readAt,
  }) {
    return ChatMessageModel(
      id: id,
      chatId: chatId,
      senderId: senderId,
      text: text,
      type: type,
      createdAt: createdAt,
      readAt: readAt ?? this.readAt,
    );
  }

  static DateTime _readDateTime(dynamic value) {
    if (value is DateTime) return value;
    if (value is String && value.isNotEmpty) {
      return DateTime.tryParse(value)?.toLocal() ?? DateTime.now();
    }
    return DateTime.now();
  }

  static DateTime? _readNullableDateTime(dynamic value) {
    if (value == null) return null;
    if (value is DateTime) return value;
    if (value is String && value.isNotEmpty) {
      return DateTime.tryParse(value)?.toLocal();
    }
    return null;
  }
}

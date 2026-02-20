import '../../domain/entities/chat_thread.dart';

class ChatThreadModel extends ChatThread {
  const ChatThreadModel({
    required super.id,
    required super.type,
    required super.participantIds,
    required super.isSaved,
    super.title,
    super.groupUsername,
    super.groupBio,
    super.ownerId,
    super.isPublic,
    super.lastMessage,
    super.lastMessageAt,
    super.lastSenderId,
    super.updatedAt,
    super.unreadCount,
    super.canWrite,
    super.memberCount,
    super.myRole,
  });

  factory ChatThreadModel.fromJson(Map<String, dynamic> json) {
    final rawParticipants = json['participantIds'];

    return ChatThreadModel(
      id: (json['id'] ?? '').toString(),
      type: (json['type'] ?? 'direct').toString(),
      participantIds: rawParticipants is List
          ? rawParticipants.map((item) => item.toString()).toList()
          : const [],
      isSaved: json['isSaved'] == true,
      title: json['title']?.toString(),
      groupUsername: json['groupUsername']?.toString(),
      groupBio: json['groupBio']?.toString(),
      ownerId: json['ownerId']?.toString(),
      isPublic: json['isPublic'] == true,
      lastMessage: json['lastMessage']?.toString(),
      lastMessageAt: _readNullableDateTime(json['lastMessageAt']),
      lastSenderId: json['lastSenderId']?.toString(),
      updatedAt: _readNullableDateTime(json['updatedAt']),
      unreadCount: (json['unreadCount'] as num?)?.toInt() ?? 0,
      canWrite: json['canWrite'] == null ? true : json['canWrite'] == true,
      memberCount: (json['memberCount'] as num?)?.toInt() ?? 0,
      myRole: (json['myRole'] ?? 'member').toString(),
    );
  }

  static DateTime? _readNullableDateTime(dynamic value) {
    if (value is String && value.isNotEmpty) {
      return DateTime.tryParse(value)?.toLocal();
    }
    if (value is DateTime) return value;
    return null;
  }
}

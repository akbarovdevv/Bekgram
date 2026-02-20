class ChatThread {
  const ChatThread({
    required this.id,
    required this.type,
    required this.participantIds,
    required this.isSaved,
    this.title,
    this.groupUsername,
    this.groupBio,
    this.ownerId,
    this.isPublic = false,
    this.lastMessage,
    this.lastMessageAt,
    this.lastSenderId,
    this.updatedAt,
    this.unreadCount = 0,
    this.canWrite = true,
    this.memberCount = 0,
    this.myRole = 'member',
  });

  final String id;
  final String type;
  final List<String> participantIds;
  final bool isSaved;
  final String? title;
  final String? groupUsername;
  final String? groupBio;
  final String? ownerId;
  final bool isPublic;
  final String? lastMessage;
  final DateTime? lastMessageAt;
  final String? lastSenderId;
  final DateTime? updatedAt;
  final int unreadCount;
  final bool canWrite;
  final int memberCount;
  final String myRole;

  bool get isGroup => type == 'group';
  bool get isOwner => myRole == 'owner';
}

class GroupMember {
  const GroupMember({
    required this.id,
    required this.username,
    required this.displayName,
    required this.avatarUrl,
    required this.isOnline,
    required this.lastSeen,
    required this.isVerified,
    required this.role,
  });

  final String id;
  final String username;
  final String displayName;
  final String avatarUrl;
  final bool isOnline;
  final DateTime? lastSeen;
  final bool isVerified;
  final String role;

  bool get isOwner => role == 'owner';
}

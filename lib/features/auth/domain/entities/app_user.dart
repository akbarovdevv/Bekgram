class AppUser {
  const AppUser({
    required this.id,
    required this.username,
    required this.usernameLower,
    required this.displayName,
    required this.email,
    required this.avatarUrl,
    required this.bio,
    required this.createdAt,
    required this.lastSeen,
    this.phoneNumber,
    this.isVerified = false,
    this.canReceiveMessages = true,
    this.verifyRequestBlockedUntil,
    this.isOnline = false,
  });

  final String id;
  final String username;
  final String usernameLower;
  final String displayName;
  final String email;
  final String avatarUrl;
  final String bio;
  final String? phoneNumber;
  final bool isVerified;
  final bool canReceiveMessages;
  final DateTime? verifyRequestBlockedUntil;
  final bool isOnline;
  final DateTime createdAt;
  final DateTime lastSeen;

  AppUser copyWith({
    String? displayName,
    String? avatarUrl,
    String? bio,
    String? phoneNumber,
    bool? isVerified,
    bool? canReceiveMessages,
    DateTime? verifyRequestBlockedUntil,
    bool? isOnline,
    DateTime? lastSeen,
  }) {
    return AppUser(
      id: id,
      username: username,
      usernameLower: usernameLower,
      displayName: displayName ?? this.displayName,
      email: email,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      bio: bio ?? this.bio,
      phoneNumber: phoneNumber ?? this.phoneNumber,
      isVerified: isVerified ?? this.isVerified,
      canReceiveMessages: canReceiveMessages ?? this.canReceiveMessages,
      verifyRequestBlockedUntil:
          verifyRequestBlockedUntil ?? this.verifyRequestBlockedUntil,
      isOnline: isOnline ?? this.isOnline,
      createdAt: createdAt,
      lastSeen: lastSeen ?? this.lastSeen,
    );
  }
}

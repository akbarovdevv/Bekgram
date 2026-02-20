import '../../domain/entities/group_member.dart';

class GroupMemberModel extends GroupMember {
  const GroupMemberModel({
    required super.id,
    required super.username,
    required super.displayName,
    required super.avatarUrl,
    required super.isOnline,
    required super.lastSeen,
    required super.isVerified,
    required super.role,
  });

  factory GroupMemberModel.fromJson(Map<String, dynamic> json) {
    return GroupMemberModel(
      id: (json['id'] ?? '').toString(),
      username: (json['username'] ?? '').toString(),
      displayName: (json['displayName'] ?? '').toString(),
      avatarUrl: (json['avatarUrl'] ?? '').toString(),
      isOnline: json['isOnline'] == true,
      lastSeen: _readNullableDateTime(json['lastSeen']),
      isVerified: json['isVerified'] == true,
      role: (json['role'] ?? 'member').toString(),
    );
  }

  static DateTime? _readNullableDateTime(dynamic value) {
    if (value is DateTime) return value;
    if (value is String && value.isNotEmpty) {
      return DateTime.tryParse(value)?.toLocal();
    }
    return null;
  }
}

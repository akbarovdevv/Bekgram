import '../../domain/entities/app_user.dart';

class AppUserModel extends AppUser {
  const AppUserModel({
    required super.id,
    required super.username,
    required super.usernameLower,
    required super.displayName,
    required super.email,
    required super.avatarUrl,
    required super.bio,
    required super.createdAt,
    required super.lastSeen,
    super.phoneNumber,
    super.isVerified,
    super.canReceiveMessages,
    super.verifyRequestBlockedUntil,
    super.isOnline,
  });

  factory AppUserModel.fromJson(Map<String, dynamic> json) {
    return AppUserModel(
      id: _readString(json, 'id'),
      username: _readString(json, 'username'),
      usernameLower: _readString(json, 'usernameLower',
          fallback: _readString(json, 'username')),
      displayName: _readString(json, 'displayName'),
      email: _readString(json, 'email',
          fallback: '${_readString(json, 'username')}@bekgram.local'),
      avatarUrl: _readString(json, 'avatarUrl'),
      bio: _readString(json, 'bio'),
      phoneNumber: _readNullableString(json, 'phoneNumber'),
      isVerified: json['isVerified'] == true,
      canReceiveMessages: json['canReceiveMessages'] == null
          ? true
          : json['canReceiveMessages'] == true,
      verifyRequestBlockedUntil:
          _readNullableDateTime(json['verifyRequestBlockedUntil']),
      isOnline: json['isOnline'] == true,
      createdAt: _readDateTime(json['createdAt']),
      lastSeen: _readDateTime(json['lastSeen']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'username': username,
      'usernameLower': usernameLower,
      'displayName': displayName,
      'email': email,
      'avatarUrl': avatarUrl,
      'bio': bio,
      'phoneNumber': phoneNumber,
      'isVerified': isVerified,
      'canReceiveMessages': canReceiveMessages,
      'verifyRequestBlockedUntil': verifyRequestBlockedUntil?.toIso8601String(),
      'isOnline': isOnline,
      'createdAt': createdAt.toIso8601String(),
      'lastSeen': lastSeen.toIso8601String(),
    };
  }

  static String _readString(Map<String, dynamic> json, String key,
      {String fallback = ''}) {
    final value = json[key];
    if (value is String && value.isNotEmpty) return value;
    return fallback;
  }

  static String? _readNullableString(Map<String, dynamic> json, String key) {
    final value = json[key];
    if (value is String && value.isNotEmpty) return value;
    return null;
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

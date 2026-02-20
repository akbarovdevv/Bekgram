import 'dart:convert';

class VerificationRequestPayload {
  const VerificationRequestPayload({
    required this.requesterId,
    required this.username,
    required this.displayName,
    required this.bio,
    this.phoneNumber,
    this.requestedAt,
  });

  final String requesterId;
  final String username;
  final String displayName;
  final String bio;
  final String? phoneNumber;
  final DateTime? requestedAt;

  static VerificationRequestPayload? tryParse(String raw) {
    final map = _decodeMap(raw);
    if (map == null || map['kind'] != 'verify_request') return null;

    final requesterId = (map['requesterId'] ?? '').toString();
    final username = (map['username'] ?? '').toString();
    final displayName = (map['displayName'] ?? '').toString();
    final bio = (map['bio'] ?? '').toString();
    final phone = map['phoneNumber']?.toString();
    final requestedAt =
        DateTime.tryParse((map['requestedAt'] ?? '').toString())?.toLocal();

    if (requesterId.isEmpty || username.isEmpty || displayName.isEmpty) {
      return null;
    }

    return VerificationRequestPayload(
      requesterId: requesterId,
      username: username,
      displayName: displayName,
      bio: bio,
      phoneNumber: (phone == null || phone.isEmpty) ? null : phone,
      requestedAt: requestedAt,
    );
  }
}

class VerificationDecisionPayload {
  const VerificationDecisionPayload({
    required this.approved,
    required this.username,
    required this.reviewerUsername,
    this.blockedUntil,
  });

  final bool approved;
  final String username;
  final String reviewerUsername;
  final DateTime? blockedUntil;

  static VerificationDecisionPayload? tryParse(String raw) {
    final map = _decodeMap(raw);
    if (map == null || map['kind'] != 'verify_decision') return null;

    final username = (map['username'] ?? '').toString();
    final reviewerUsername = (map['reviewerUsername'] ?? '').toString();
    if (username.isEmpty || reviewerUsername.isEmpty) return null;

    final blockedUntil =
        DateTime.tryParse((map['blockedUntil'] ?? '').toString())?.toLocal();

    return VerificationDecisionPayload(
      approved: map['approved'] == true,
      username: username,
      reviewerUsername: reviewerUsername,
      blockedUntil: blockedUntil,
    );
  }

  String toReadableText() {
    if (approved) {
      return '@$username verified by @$reviewerUsername';
    }
    final until = blockedUntil;
    if (until == null) {
      return '@$username request rejected by @$reviewerUsername';
    }
    final day = until.day.toString().padLeft(2, '0');
    final month = until.month.toString().padLeft(2, '0');
    final year = until.year.toString();
    final hour = until.hour.toString().padLeft(2, '0');
    final minute = until.minute.toString().padLeft(2, '0');
    return '@$username rejected by @$reviewerUsername. Retry: $year-$month-$day $hour:$minute';
  }
}

Map<String, dynamic>? _decodeMap(String raw) {
  final trimmed = raw.trim();
  if (trimmed.isEmpty || !trimmed.startsWith('{')) return null;

  try {
    final decoded = jsonDecode(trimmed);
    if (decoded is! Map) return null;
    return decoded.map((k, v) => MapEntry(k.toString(), v));
  } catch (_) {
    return null;
  }
}

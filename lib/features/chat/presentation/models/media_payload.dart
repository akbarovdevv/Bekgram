import 'dart:convert';

import '../../domain/entities/chat_media_attachment.dart';

class MediaPayload {
  const MediaPayload({
    required this.kind,
    required this.url,
    required this.fileName,
    required this.mimeType,
    required this.sizeBytes,
  });

  final String kind;
  final String url;
  final String fileName;
  final String mimeType;
  final int sizeBytes;

  factory MediaPayload.fromAttachment(ChatMediaAttachment attachment) {
    return MediaPayload(
      kind: attachment.kind,
      url: attachment.url,
      fileName: attachment.fileName,
      mimeType: attachment.mimeType,
      sizeBytes: attachment.sizeBytes,
    );
  }

  String encode() {
    return jsonEncode({
      'kind': kind,
      'url': url,
      'fileName': fileName,
      'mimeType': mimeType,
      'sizeBytes': sizeBytes,
    });
  }

  static MediaPayload? tryParse(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty || !trimmed.startsWith('{')) return null;

    try {
      final decoded = jsonDecode(trimmed);
      if (decoded is! Map) return null;
      final map = decoded.map((k, v) => MapEntry(k.toString(), v));

      final kind = map['kind']?.toString() ?? '';
      final url = map['url']?.toString() ?? '';
      final fileName = map['fileName']?.toString() ?? '';
      final mimeType = map['mimeType']?.toString() ?? '';
      final sizeBytes = (map['sizeBytes'] as num?)?.toInt() ?? 0;
      if (kind.isEmpty || url.isEmpty) return null;

      return MediaPayload(
        kind: kind,
        url: url,
        fileName: fileName,
        mimeType: mimeType,
        sizeBytes: sizeBytes,
      );
    } catch (_) {
      return null;
    }
  }
}

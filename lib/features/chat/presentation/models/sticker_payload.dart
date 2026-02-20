import 'dart:convert';

class StickerPayload {
  StickerPayload({
    required this.stickerAssetPath,
    this.caption,
  });

  final String stickerAssetPath;
  final String? caption;

  String encode() {
    return jsonEncode({
      'sticker': stickerAssetPath,
      'caption': caption,
    });
  }

  static StickerPayload? tryParse(String raw) {
    if (raw.trim().isEmpty) return null;

    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;

      final map = decoded.map((key, value) => MapEntry(key.toString(), value));
      final sticker = map['sticker'];
      if (sticker is! String || sticker.trim().isEmpty) return null;

      final captionValue = map['caption'];
      final caption = captionValue is String && captionValue.trim().isNotEmpty
          ? captionValue.trim()
          : null;

      return StickerPayload(
        stickerAssetPath: sticker,
        caption: caption,
      );
    } catch (_) {
      return null;
    }
  }
}

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final availableStickersProvider = FutureProvider<List<String>>((ref) async {
  return StickerCatalog.loadStickerAssets();
});

class StickerCatalog {
  static const _folderPrefixes = ['assets/lottie/', 'lottie/'];

  static Future<List<String>> loadStickerAssets() async {
    final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
    final stickers = manifest
        .listAssets()
        .where((key) =>
            _folderPrefixes.any((prefix) => key.startsWith(prefix)) &&
            key.toLowerCase().endsWith('.json'))
        .toList()
      ..sort();

    return stickers;
  }
}

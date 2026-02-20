import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/glass_surface.dart';

class StickerPickerSheet extends StatelessWidget {
  const StickerPickerSheet({
    super.key,
    required this.stickers,
  });

  final List<String> stickers;

  @override
  Widget build(BuildContext context) {
    final textColor = AppTheme.textPrimary(context);
    final secondaryText = AppTheme.textSecondary(context);

    if (stickers.isEmpty) {
      return SafeArea(
        child: SizedBox(
          height: 180,
          child: Center(
            child: Text(
              'Sticker topilmadi. lottie/ yoki assets/lottie/ ga json qo\'shing.',
              style: TextStyle(
                color: secondaryText,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      );
    }

    return SafeArea(
      child: SizedBox(
        height: 320,
        child: Column(
          children: [
            const SizedBox(height: 8),
            Container(
              width: 42,
              height: 4,
              decoration: BoxDecoration(
                color: textColor.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(99),
              ),
            ),
            const SizedBox(height: 10),
            const Text(
              'Send Sticker',
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: GridView.builder(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 5,
                  mainAxisSpacing: 10,
                  crossAxisSpacing: 10,
                ),
                itemCount: stickers.length,
                itemBuilder: (context, index) {
                  final asset = stickers[index];
                  final name = asset.split('/').last;

                  return GlassSurface(
                    radius: 16,
                    opacity: 0.5,
                    blur: 12,
                    padding: const EdgeInsets.all(6),
                    onTap: () => Navigator.of(context).pop(asset),
                    child: Tooltip(
                      message: name,
                      child: Center(
                        child: SizedBox(
                          width: 44,
                          height: 44,
                          child: Lottie.asset(
                            asset,
                            fit: BoxFit.contain,
                            repeat: true,
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

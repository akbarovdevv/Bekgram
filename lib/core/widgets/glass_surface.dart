import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

class GlassSurface extends StatelessWidget {
  const GlassSurface({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(14),
    this.margin = EdgeInsets.zero,
    this.radius = 22,
    this.blur = 16,
    this.opacity = 0.52,
    this.borderColor,
    this.onTap,
    this.onLongPress,
    this.onSecondaryTapDown,
    this.enableBackdrop = true,
    this.borderWidth = 1,
    this.showSpecular = true,
  });

  final Widget child;
  final EdgeInsets padding;
  final EdgeInsets margin;
  final double radius;
  final double blur;
  final double opacity;
  final Color? borderColor;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final GestureTapDownCallback? onSecondaryTapDown;
  final bool enableBackdrop;
  final double borderWidth;
  final bool showSpecular;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isMobilePlatform = defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS;
    final blurScale = isMobilePlatform ? (kReleaseMode ? 0.74 : 0.56) : 1.0;
    final effectiveBlur = (blur * blurScale).clamp(4.0, blur).toDouble();
    final shadowBlur = (20 * blurScale).clamp(10.0, 20.0).toDouble();

    final backgroundColor = isDark
        ? const Color(0xFF0B0F15).withValues(
            alpha: ((opacity + 0.08).clamp(0.0, 1.0)).toDouble(),
          )
        : Colors.white.withValues(alpha: opacity);
    final tintColor = isDark
        ? AppTheme.telegramBlue.withValues(alpha: 0.18)
        : AppTheme.cyan.withValues(alpha: 0.24);
    final effectiveBorderColor =
        borderColor ?? Colors.white.withValues(alpha: isDark ? 0.2 : 0.62);
    final effectiveShadowColor = isDark
        ? Colors.black.withValues(alpha: 0.4)
        : Colors.white.withValues(alpha: 0.22);
    final radiusGeometry = BorderRadius.circular(radius);

    final content = Container(
      decoration: BoxDecoration(
        borderRadius: radiusGeometry,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            backgroundColor,
            Color.alphaBlend(tintColor, backgroundColor),
          ],
        ),
        border: Border.all(
          color: effectiveBorderColor,
          width: borderWidth,
        ),
        boxShadow: [
          BoxShadow(
            color: effectiveShadowColor,
            blurRadius: shadowBlur,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Stack(
        children: [
          if (showSpecular)
            Positioned.fill(
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: radiusGeometry,
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        Colors.white.withValues(alpha: isDark ? 0.2 : 0.46),
                        Colors.white.withValues(alpha: isDark ? 0.06 : 0.16),
                        Colors.transparent,
                      ],
                      stops: const [0.0, 0.32, 1.0],
                    ),
                  ),
                ),
              ),
            ),
          if (showSpecular)
            Positioned(
              top: -radius * 0.58,
              left: radius * 0.2,
              right: radius * 0.2,
              height: radius * 1.32,
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(radius * 0.92),
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.white.withValues(alpha: isDark ? 0.22 : 0.42),
                        Colors.transparent,
                      ],
                    ),
                  ),
                ),
              ),
            ),
          Padding(
            padding: padding,
            child: child,
          ),
        ],
      ),
    );

    final card = ClipRRect(
      borderRadius: radiusGeometry,
      child: enableBackdrop
          ? BackdropFilter(
              filter: ImageFilter.blur(
                  sigmaX: effectiveBlur, sigmaY: effectiveBlur),
              child: content,
            )
          : content,
    );

    final wrapped = Padding(padding: margin, child: card);
    if (onTap == null && onLongPress == null && onSecondaryTapDown == null) {
      return wrapped;
    }

    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      onSecondaryTapDown: onSecondaryTapDown,
      behavior: HitTestBehavior.opaque,
      child: wrapped,
    );
  }
}

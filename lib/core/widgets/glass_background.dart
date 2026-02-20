import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

class GlassBackground extends StatelessWidget {
  const GlassBackground({
    super.key,
    required this.child,
  });

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isMobilePlatform = defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS;
    final effectScale = isMobilePlatform ? (kReleaseMode ? 0.78 : 0.6) : 1.0;
    final overlayBlur = (3 * effectScale).clamp(1.0, 3.0).toDouble();
    final glowShadowBlur = (90 * effectScale).clamp(42.0, 90.0).toDouble();
    final glowSpread = (18 * effectScale).clamp(8.0, 18.0).toDouble();

    return Stack(
      fit: StackFit.expand,
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: isDark
                  ? const [
                      Color(0xFF030408),
                      Color(0xFF070D16),
                      Color(0xFF0B1320),
                    ]
                  : [
                      const Color(0xFFD7EEFF),
                      AppTheme.cyan.withValues(alpha: 0.48),
                      AppTheme.violet.withValues(alpha: 0.42),
                    ],
            ),
          ),
        ),
        Positioned(
          top: -140,
          left: -70,
          child: _GlowBlob(
            size: 300,
            color:
                AppTheme.telegramBlue.withValues(alpha: isDark ? 0.13 : 0.25),
            shadowBlur: glowShadowBlur,
            spreadRadius: glowSpread,
          ),
        ),
        Positioned(
          bottom: -110,
          right: -80,
          child: _GlowBlob(
            size: 280,
            color: AppTheme.violet.withValues(alpha: isDark ? 0.1 : 0.24),
            shadowBlur: glowShadowBlur,
            spreadRadius: glowSpread,
          ),
        ),
        Positioned.fill(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: overlayBlur, sigmaY: overlayBlur),
            child: const SizedBox.shrink(),
          ),
        ),
        SafeArea(child: child),
      ],
    );
  }
}

class _GlowBlob extends StatelessWidget {
  const _GlowBlob({
    required this.size,
    required this.color,
    required this.shadowBlur,
    required this.spreadRadius,
  });

  final double size;
  final Color color;
  final double shadowBlur;
  final double spreadRadius;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color,
        boxShadow: [
          BoxShadow(
            color: color,
            blurRadius: shadowBlur,
            spreadRadius: spreadRadius,
          ),
        ],
      ),
    );
  }
}

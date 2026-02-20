import 'package:flutter/material.dart';

/// Paints a blurred glossy border around a rounded rectangle to simulate
/// liquid-glass (iOS-like) stroke.
class LiquidGlassBorderPainter extends CustomPainter {
  LiquidGlassBorderPainter({
    required this.radius,
    required this.isDark,
    this.strokeWidth = 1.2,
    this.glowSigma = 6.0,
  });

  final double radius;
  final bool isDark;
  final double strokeWidth;
  final double glowSigma;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;

    final rect = Offset.zero & size;
    // Keep the stroke fully visible within bounds
    final rrect = RRect.fromRectAndRadius(
      rect.deflate(strokeWidth / 2),
      Radius.circular(radius),
    );

    // 1) Soft outer glow on the stroke (blurred border look)
    final glowPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..color = Colors.white.withOpacity(isDark ? 0.25 : 0.40)
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, glowSigma)
      ..isAntiAlias = true;
    canvas.drawRRect(rrect, glowPaint);

    // 2) 135° glossy gradient stroke (crisper layer)
    final shader = const LinearGradient(
      begin: Alignment(-0.8, -0.8),
      end: Alignment(0.8, 0.8),
      colors: [
        Color(0xCCFFFFFF), // bright corner
        Color(0x33FFFFFF), // fade out
      ],
    ).createShader(rect);

    final strokePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..shader = shader
      ..isAntiAlias = true;

    canvas.drawRRect(rrect, strokePaint);
  }

  @override
  bool shouldRepaint(covariant LiquidGlassBorderPainter oldDelegate) {
    return oldDelegate.radius != radius ||
        oldDelegate.isDark != isDark ||
        oldDelegate.strokeWidth != strokeWidth ||
        oldDelegate.glowSigma != glowSigma;
  }
}

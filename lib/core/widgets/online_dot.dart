import 'package:flutter/material.dart';

class OnlineDot extends StatelessWidget {
  const OnlineDot({
    super.key,
    required this.isOnline,
    this.size = 12,
  });

  final bool isOnline;
  final double size;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: isOnline ? const Color(0xFF00C47A) : const Color(0xFF94A3B8),
        shape: BoxShape.circle,
        border: Border.all(
          color: isDark ? const Color(0xFF05080D) : Colors.white,
          width: 1.6,
        ),
      ),
    );
  }
}

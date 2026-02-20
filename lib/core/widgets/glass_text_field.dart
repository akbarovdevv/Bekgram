import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'glass_surface.dart';

class GlassTextField extends StatelessWidget {
  const GlassTextField({
    super.key,
    required this.controller,
    required this.hint,
    this.icon,
    this.obscureText = false,
    this.onChanged,
    this.textInputAction,
    this.keyboardType,
  });

  final TextEditingController controller;
  final String hint;
  final IconData? icon;
  final bool obscureText;
  final ValueChanged<String>? onChanged;
  final TextInputAction? textInputAction;
  final TextInputType? keyboardType;

  @override
  Widget build(BuildContext context) {
    final textColor = AppTheme.textPrimary(context);
    final iconColor = AppTheme.textSecondary(context).withValues(alpha: 0.9);

    return GlassSurface(
      radius: 18,
      blur: 18,
      opacity: AppTheme.isDark(context) ? 0.5 : 0.55,
      enableBackdrop: false,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
      child: TextField(
        controller: controller,
        obscureText: obscureText,
        textInputAction: textInputAction,
        keyboardType: keyboardType,
        onChanged: onChanged,
        style: TextStyle(
          color: textColor,
          fontWeight: FontWeight.w600,
        ),
        decoration: InputDecoration(
          prefixIcon: icon != null
              ? Icon(
                  icon,
                  size: 20,
                  color: iconColor,
                )
              : null,
          hintText: hint,
          border: InputBorder.none,
        ),
      ),
    );
  }
}

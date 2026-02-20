import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';

import '../theme/app_theme.dart';

class VerificationBadge extends StatelessWidget {
  const VerificationBadge({
    super.key,
    required this.usernameLower,
    required this.isVerified,
    this.size = 16,
  });

  final String usernameLower;
  final bool isVerified;
  final double size;

  bool get _isCeoBadge => usernameLower == 'asilbek';

  @override
  Widget build(BuildContext context) {
    if (!_isCeoBadge && !isVerified) {
      return const SizedBox.shrink();
    }

    if (_isCeoBadge) {
      return Transform.translate(
        offset: const Offset(0, 0.7),
        child: SizedBox.square(
          dimension: size * 1.15,
          child: Lottie.asset(
            'lottie/ceo.json',
            fit: BoxFit.cover,
            alignment: Alignment.center,
            repeat: true,
            frameRate: FrameRate.composition,
            errorBuilder: (context, error, stackTrace) {
              return Icon(
                Icons.verified_rounded,
                size: size,
                color: AppTheme.telegramBlue,
              );
            },
          ),
        ),
      );
    }

    return Transform.translate(
      offset: const Offset(0, 0.7),
      child: Icon(
        Icons.verified_rounded,
        size: size,
        color: AppTheme.telegramBlue,
      ),
    );
  }
}

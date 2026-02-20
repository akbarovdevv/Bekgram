import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/auth/presentation/controllers/auth_controller.dart';
import '../../features/auth/presentation/screens/login_screen.dart';
import 'main_shell.dart';
import 'splash_screen.dart';

class RootGate extends ConsumerStatefulWidget {
  const RootGate({super.key});

  @override
  ConsumerState<RootGate> createState() => _RootGateState();
}

class _RootGateState extends ConsumerState<RootGate> {
  bool _splashDone = false;

  @override
  void initState() {
    super.initState();
    Future<void>.delayed(const Duration(milliseconds: 1500), () {
      if (mounted) {
        setState(() => _splashDone = true);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!_splashDone) return const SplashScreen();

    final authState = ref.watch(authUserProvider);

    return authState.when(
      data: (user) {
        if (user == null) return const LoginScreen();
        return const MainShell();
      },
      loading: SplashScreen.new,
      error: (_, __) => const LoginScreen(),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/glass_background.dart';
import '../../../../core/widgets/glass_surface.dart';
import '../../../../core/widgets/glass_text_field.dart';
import '../controllers/auth_controller.dart';

class SignUpScreen extends ConsumerStatefulWidget {
  const SignUpScreen({super.key});

  @override
  ConsumerState<SignUpScreen> createState() => _SignUpScreenState();
}

class _SignUpScreenState extends ConsumerState<SignUpScreen> {
  final _displayNameController = TextEditingController();
  final _usernameController = TextEditingController();
  final _bioController = TextEditingController();
  final _phoneController = TextEditingController();
  final _passwordController = TextEditingController();

  @override
  void dispose() {
    _displayNameController.dispose();
    _usernameController.dispose();
    _bioController.dispose();
    _phoneController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _signUp() async {
    final message = await ref.read(authControllerProvider.notifier).signUp(
          username: _usernameController.text,
          password: _passwordController.text,
          displayName: _displayNameController.text,
          bio: _bioController.text,
          phoneNumber: _phoneController.text,
        );

    if (!mounted) return;

    if (message != null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));
      return;
    }

    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authControllerProvider);
    final isLoading = authState.isLoading;

    return Scaffold(
      body: GlassBackground(
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(22),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 480),
                child: GlassSurface(
                  radius: 32,
                  blur: 22,
                  opacity: 0.6,
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          IconButton(
                            onPressed: () => Navigator.of(context).pop(),
                            icon: const Icon(Icons.arrow_back_ios_new_rounded),
                          ),
                          const SizedBox(width: 4),
                          const Text(
                            'Create account',
                            style: TextStyle(
                                fontSize: 22, fontWeight: FontWeight.w800),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      GlassTextField(
                        controller: _displayNameController,
                        hint: 'Full name',
                        icon: Icons.person_rounded,
                        textInputAction: TextInputAction.next,
                      ),
                      const SizedBox(height: 10),
                      GlassTextField(
                        controller: _usernameController,
                        hint: 'Unique username (e.g. bek_user)',
                        icon: Icons.alternate_email_rounded,
                        textInputAction: TextInputAction.next,
                      ),
                      const SizedBox(height: 10),
                      GlassTextField(
                        controller: _bioController,
                        hint: 'Bio',
                        icon: Icons.auto_awesome_rounded,
                        textInputAction: TextInputAction.next,
                      ),
                      const SizedBox(height: 10),
                      GlassTextField(
                        controller: _phoneController,
                        hint: 'Phone (optional)',
                        icon: Icons.phone_rounded,
                        keyboardType: TextInputType.phone,
                        textInputAction: TextInputAction.next,
                      ),
                      const SizedBox(height: 10),
                      GlassTextField(
                        controller: _passwordController,
                        hint: 'Password (min 6)',
                        icon: Icons.lock_rounded,
                        obscureText: true,
                        textInputAction: TextInputAction.done,
                      ),
                      const SizedBox(height: 18),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton(
                          onPressed: isLoading ? null : _signUp,
                          style: FilledButton.styleFrom(
                            backgroundColor: AppTheme.telegramBlue,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16)),
                          ),
                          child: isLoading
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2.2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Text(
                                  'Sign Up',
                                  style: TextStyle(
                                      fontWeight: FontWeight.w700,
                                      color: Colors.white),
                                ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

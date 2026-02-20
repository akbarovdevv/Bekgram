import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/theme/theme_mode_controller.dart';
import '../../../../core/widgets/glass_background.dart';
import '../../../../core/widgets/glass_surface.dart';
import '../../../auth/presentation/controllers/auth_controller.dart';
import '../../../profile/presentation/screens/profile_screen.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(themeModeProvider);
    final me = ref.watch(currentUserProvider);
    final authState = ref.watch(authControllerProvider);
    final isDark = mode == ThemeMode.dark;
    final canReceiveMessages = me?.canReceiveMessages ?? true;
    final isBusy = authState.isLoading;
    final secondaryText = AppTheme.textSecondary(context);

    return Scaffold(
      body: GlassBackground(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 22),
          children: [
            GlassSurface(
              radius: 26,
              blur: 18,
              opacity: 0.56,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
              child: Row(
                children: [
                  const Icon(Icons.settings_rounded, size: 28),
                  const SizedBox(width: 10),
                  const Text(
                    'Settings',
                    style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            GlassSurface(
              radius: 24,
              blur: 16,
              opacity: 0.56,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              child: Column(
                children: [
                  ListTile(
                    leading: Icon(
                      isDark
                          ? Icons.dark_mode_rounded
                          : Icons.light_mode_rounded,
                    ),
                    title: const Text(
                      'Dark mode',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                    subtitle: Text(
                      isDark ? 'Night black theme' : 'Light glass theme',
                      style: TextStyle(
                        color: secondaryText,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    trailing: Switch.adaptive(
                      value: isDark,
                      onChanged: (_) =>
                          ref.read(themeModeProvider.notifier).toggle(),
                    ),
                  ),
                  const Divider(height: 1),
                  ListTile(
                    leading: const Icon(Icons.person_rounded),
                    title: const Text(
                      'Edit profile',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                    subtitle: Text(
                      'Photo, bio, phone, username view',
                      style: TextStyle(
                        color: secondaryText,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                            builder: (_) => const ProfileScreen()),
                      );
                    },
                  ),
                  const Divider(height: 1),
                  ListTile(
                    leading: Icon(
                      canReceiveMessages
                          ? Icons.lock_open_rounded
                          : Icons.lock_rounded,
                    ),
                    title: const Text(
                      'Allow incoming messages',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                    subtitle: Text(
                      canReceiveMessages
                          ? 'People can send you direct messages'
                          : 'New incoming messages are blocked',
                      style: TextStyle(
                        color: secondaryText,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    trailing: Switch.adaptive(
                      value: canReceiveMessages,
                      onChanged: isBusy
                          ? null
                          : (value) async {
                              final error = await ref
                                  .read(authControllerProvider.notifier)
                                  .updateProfile(canReceiveMessages: value);
                              if (!context.mounted || error == null) return;
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text(error)),
                              );
                            },
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: () =>
                  ref.read(authControllerProvider.notifier).signOut(),
              style: FilledButton.styleFrom(
                backgroundColor: Colors.redAccent,
                foregroundColor: Colors.white,
                minimumSize: const Size.fromHeight(50),
              ),
              icon: const Icon(Icons.logout_rounded),
              label: const Text('Log out'),
            ),
          ],
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/navigation/fade_page_route.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/glass_background.dart';
import '../../../../core/widgets/glass_surface.dart';
import '../../../../core/widgets/glass_text_field.dart';
import '../../../../core/widgets/verification_badge.dart';
import '../../../auth/domain/entities/app_user.dart';
import '../../../auth/presentation/controllers/auth_controller.dart';
import '../controllers/chat_controller.dart';
import 'chat_screen.dart';

class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key, this.fromBottomTab = false});

  final bool fromBottomTab;

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  final _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _openChat(String userId) async {
    final me = ref.read(currentUserProvider);
    final users = ref.read(searchUsersProvider).valueOrNull;
    if (me == null || users == null) return;
    try {
      AppUser? peer;
      for (final user in users) {
        if (user.id == userId) {
          peer = user;
          break;
        }
      }
      if (peer == null) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text("User topilmadi. Qayta urinib ko'ring.")),
        );
        return;
      }
      final chatId =
          await ref.read(chatActionControllerProvider.notifier).openDirectChat(
                currentUserId: me.id,
                peer: peer,
              );

      if (!mounted) return;

      Navigator.of(context).push(
        FadePageRoute(
          page: ChatScreen(chatId: chatId, peerId: userId, isSaved: false),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.toString())),
      );
    }
  }

  Future<void> _joinGroup(String groupId, String title) async {
    try {
      final chatId = await ref
          .read(chatActionControllerProvider.notifier)
          .joinGroup(groupId);
      ref.invalidate(chatListProvider);
      ref.invalidate(searchPublicGroupsProvider);
      if (!mounted) return;
      Navigator.of(context).push(
        FadePageRoute(
          page: ChatScreen(chatId: chatId, peerId: null, isSaved: false),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.toString())),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final results = ref.watch(searchUsersProvider);
    final groupResults = ref.watch(searchPublicGroupsProvider);
    final secondaryText = AppTheme.textSecondary(context);

    return Scaffold(
      body: GlassBackground(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
              child: GlassSurface(
                radius: 22,
                opacity: 0.58,
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                child: Row(
                  children: [
                    if (!widget.fromBottomTab)
                      IconButton(
                        onPressed: () => Navigator.of(context).pop(),
                        icon: const Icon(Icons.arrow_back_ios_new_rounded),
                      ),
                    Expanded(
                      child: GlassTextField(
                        controller: _searchController,
                        hint: 'Search users & groups',
                        icon: Icons.search_rounded,
                        onChanged: (value) {
                          ref.read(searchQueryProvider.notifier).state = value;
                          ref.read(searchGroupsQueryProvider.notifier).state =
                              value;
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Expanded(
              child: _searchController.text.trim().isEmpty
                  ? Center(
                      child: Text(
                        'Type username to find users & groups',
                        style: TextStyle(
                          color: secondaryText,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    )
                  : ListView(
                      padding: const EdgeInsets.only(bottom: 24),
                      children: [
                        // ── Public Groups ──
                        groupResults.when(
                          data: (groups) {
                            if (groups.isEmpty) {
                              return const SizedBox.shrink();
                            }
                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 20, vertical: 6),
                                  child: Text(
                                    'PUBLIC GROUPS',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w800,
                                      color: AppTheme.telegramBlue
                                          .withValues(alpha: 0.8),
                                      letterSpacing: 1,
                                    ),
                                  ),
                                ),
                                ...groups.map((group) {
                                  final groupId = group['id']?.toString() ?? '';
                                  final title =
                                      group['title']?.toString() ?? '';
                                  final username =
                                      group['groupUsername']?.toString() ?? '';
                                  final memberCount =
                                      (group['memberCount'] as num?)?.toInt() ??
                                          0;
                                  final isMember = group['isMember'] == true;

                                  return GlassSurface(
                                    margin: const EdgeInsets.symmetric(
                                        horizontal: 16, vertical: 6),
                                    radius: 22,
                                    opacity: 0.56,
                                    onTap: isMember
                                        ? () {
                                            Navigator.of(context).push(
                                              FadePageRoute(
                                                page: ChatScreen(
                                                  chatId: groupId,
                                                  peerId: null,
                                                  isSaved: false,
                                                ),
                                              ),
                                            );
                                          }
                                        : null,
                                    child: ListTile(
                                      contentPadding: EdgeInsets.zero,
                                      leading: Container(
                                        width: 48,
                                        height: 48,
                                        decoration: BoxDecoration(
                                          borderRadius:
                                              BorderRadius.circular(14),
                                          gradient: const LinearGradient(
                                            colors: [
                                              AppTheme.telegramBlue,
                                              AppTheme.cyan,
                                            ],
                                          ),
                                        ),
                                        child: const Icon(Icons.groups_rounded,
                                            color: Colors.white),
                                      ),
                                      title: Text(
                                        title,
                                        style: const TextStyle(
                                            fontWeight: FontWeight.w800),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      subtitle: Text(
                                        '@$username · $memberCount members',
                                        style: const TextStyle(
                                            fontWeight: FontWeight.w600),
                                      ),
                                      trailing: isMember
                                          ? const Chip(
                                              label: Text('Joined',
                                                  style:
                                                      TextStyle(fontSize: 12)),
                                              padding: EdgeInsets.zero,
                                              visualDensity:
                                                  VisualDensity.compact,
                                            )
                                          : FilledButton(
                                              onPressed: () =>
                                                  _joinGroup(groupId, title),
                                              style: FilledButton.styleFrom(
                                                backgroundColor:
                                                    AppTheme.telegramBlue,
                                                foregroundColor: Colors.white,
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                        horizontal: 16),
                                                minimumSize: const Size(60, 34),
                                              ),
                                              child: const Text('Join'),
                                            ),
                                    ),
                                  );
                                }),
                                const SizedBox(height: 8),
                              ],
                            );
                          },
                          loading: () => const Padding(
                            padding: EdgeInsets.all(16),
                            child: Center(child: CircularProgressIndicator()),
                          ),
                          error: (_, __) => const SizedBox.shrink(),
                        ),

                        // ── Users ──
                        results.when(
                          data: (users) {
                            if (users.isEmpty) {
                              return const SizedBox.shrink();
                            }
                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 20, vertical: 6),
                                  child: Text(
                                    'USERS',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w800,
                                      color: AppTheme.telegramBlue
                                          .withValues(alpha: 0.8),
                                      letterSpacing: 1,
                                    ),
                                  ),
                                ),
                                ...users.map((user) {
                                  final isVerifiedUser = user.isVerified ||
                                      user.usernameLower == 'asilbek';

                                  return GlassSurface(
                                    margin: const EdgeInsets.symmetric(
                                        horizontal: 16, vertical: 6),
                                    radius: 22,
                                    opacity: 0.56,
                                    onTap: () => _openChat(user.id),
                                    child: ListTile(
                                      contentPadding: EdgeInsets.zero,
                                      leading: CircleAvatar(
                                        radius: 24,
                                        backgroundImage:
                                            user.avatarUrl.isNotEmpty
                                                ? NetworkImage(user.avatarUrl)
                                                : null,
                                      ),
                                      title: Text.rich(
                                        TextSpan(
                                          style: const TextStyle(
                                              fontWeight: FontWeight.w800),
                                          children: [
                                            TextSpan(text: user.displayName),
                                            if (isVerifiedUser)
                                              WidgetSpan(
                                                alignment:
                                                    PlaceholderAlignment.middle,
                                                child: Padding(
                                                  padding:
                                                      const EdgeInsets.only(
                                                          left: 4),
                                                  child: VerificationBadge(
                                                    usernameLower:
                                                        user.usernameLower,
                                                    isVerified: user.isVerified,
                                                    size: 16,
                                                  ),
                                                ),
                                              ),
                                          ],
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      subtitle: Text(
                                        '@${user.username}',
                                        style: const TextStyle(
                                            fontWeight: FontWeight.w600),
                                      ),
                                      trailing: const Icon(
                                          Icons.chevron_right_rounded),
                                    ),
                                  );
                                }),
                              ],
                            );
                          },
                          loading: () => const Padding(
                            padding: EdgeInsets.all(16),
                            child: Center(child: CircularProgressIndicator()),
                          ),
                          error: (error, _) =>
                              Center(child: Text(error.toString())),
                        ),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

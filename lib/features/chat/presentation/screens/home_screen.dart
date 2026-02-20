import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/navigation/fade_page_route.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/glass_background.dart';
import '../../../../core/widgets/glass_surface.dart';
import '../../../auth/presentation/controllers/auth_controller.dart';
import '../../domain/entities/chat_thread.dart';
import '../controllers/chat_controller.dart';
import '../widgets/chat_tile.dart';
import 'chat_screen.dart';
import 'search_screen.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  Future<void> _openCreateGroupSheet(
    BuildContext context,
    WidgetRef ref,
  ) async {
    final titleController = TextEditingController();
    final usernameController = TextEditingController();
    final bioController = TextEditingController();
    var saving = false;
    var isPublic = false;

    await showModalBottomSheet<void>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        final bottomInset = MediaQuery.of(sheetContext).viewInsets.bottom;
        return StatefulBuilder(
          builder: (sheetContext, setModalState) {
            Future<void> onCreate() async {
              if (saving) return;
              final title = titleController.text.trim();
              final username = usernameController.text.trim();
              final bio = bioController.text.trim();

              setModalState(() => saving = true);
              try {
                final chatId = await ref
                    .read(chatActionControllerProvider.notifier)
                    .createGroup(
                  title: title,
                  groupUsername: username,
                  bio: bio,
                  isPublic: isPublic,
                  memberUsernames: const [],
                );
                ref.invalidate(chatListProvider);

                if (!sheetContext.mounted) return;
                Navigator.of(sheetContext).pop();

                if (!context.mounted) return;
                final normalized = username.startsWith('@')
                    ? username.substring(1).toLowerCase()
                    : username.toLowerCase();
                Navigator.of(context).push(
                  FadePageRoute(
                    page: ChatScreen(
                      chatId: chatId,
                      peerId: null,
                      isSaved: false,
                      initialChat: ChatThread(
                        id: chatId,
                        type: 'group',
                        participantIds: const [],
                        isSaved: false,
                        title: title,
                        groupUsername: isPublic ? normalized : null,
                        groupBio: bio,
                        isPublic: isPublic,
                        memberCount: 1,
                        myRole: 'owner',
                      ),
                    ),
                  ),
                );
              } catch (error) {
                if (!sheetContext.mounted) return;
                ScaffoldMessenger.of(sheetContext).showSnackBar(
                  SnackBar(content: Text(error.toString())),
                );
                setModalState(() => saving = false);
              }
            }

            return SafeArea(
              child: Padding(
                padding: EdgeInsets.fromLTRB(12, 12, 12, bottomInset + 12),
                child: GlassSurface(
                  radius: 26,
                  blur: 20,
                  opacity: 0.6,
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Text(
                              'Create Group',
                              style: TextStyle(
                                fontWeight: FontWeight.w900,
                                fontSize: 20,
                              ),
                            ),
                            const Spacer(),
                            IconButton(
                              onPressed: () => Navigator.of(sheetContext).pop(),
                              icon: const Icon(Icons.close_rounded),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            Expanded(
                              child: GestureDetector(
                                onTap: () =>
                                    setModalState(() => isPublic = false),
                                child: AnimatedContainer(
                                  duration: const Duration(milliseconds: 200),
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 10),
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(12),
                                    color: !isPublic
                                        ? AppTheme.telegramBlue
                                        : Colors.white10,
                                  ),
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(
                                        Icons.lock_rounded,
                                        size: 18,
                                        color: !isPublic
                                            ? Colors.white
                                            : Colors.white54,
                                      ),
                                      const SizedBox(width: 6),
                                      Text(
                                        'Private',
                                        style: TextStyle(
                                          fontWeight: FontWeight.w700,
                                          color: !isPublic
                                              ? Colors.white
                                              : Colors.white54,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: GestureDetector(
                                onTap: () =>
                                    setModalState(() => isPublic = true),
                                child: AnimatedContainer(
                                  duration: const Duration(milliseconds: 200),
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 10),
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(12),
                                    color: isPublic
                                        ? AppTheme.telegramBlue
                                        : Colors.white10,
                                  ),
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(
                                        Icons.public_rounded,
                                        size: 18,
                                        color: isPublic
                                            ? Colors.white
                                            : Colors.white54,
                                      ),
                                      const SizedBox(width: 6),
                                      Text(
                                        'Public',
                                        style: TextStyle(
                                          fontWeight: FontWeight.w700,
                                          color: isPublic
                                              ? Colors.white
                                              : Colors.white54,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        TextField(
                          controller: titleController,
                          decoration: const InputDecoration(
                            labelText: 'Group name',
                            hintText: 'Design Team',
                          ),
                        ),
                        if (isPublic) ...[
                          const SizedBox(height: 8),
                          TextField(
                            controller: usernameController,
                            decoration: const InputDecoration(
                              labelText: 'Group username',
                              hintText: '@design_team',
                            ),
                          ),
                        ],
                        const SizedBox(height: 8),
                        TextField(
                          controller: bioController,
                          maxLines: 2,
                          decoration: const InputDecoration(
                            labelText: 'Group bio',
                            hintText: 'Team updates and discussion',
                          ),
                        ),
                        const SizedBox(height: 14),
                        FilledButton.icon(
                          onPressed: saving ? null : onCreate,
                          icon: saving
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child:
                                      CircularProgressIndicator(strokeWidth: 2),
                                )
                              : const Icon(Icons.groups_rounded),
                          label: Text(saving ? 'Creating...' : 'Create group'),
                          style: FilledButton.styleFrom(
                            minimumSize: const Size.fromHeight(48),
                            backgroundColor: AppTheme.telegramBlue,
                            foregroundColor: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );

    titleController.dispose();
    usernameController.dispose();
    bioController.dispose();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final me = ref.watch(currentUserProvider);
    final chatsAsync = ref.watch(chatListProvider);
    final secondaryText = AppTheme.textSecondary(context);

    return Scaffold(
      body: GlassBackground(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
              child: GlassSurface(
                radius: 26,
                blur: 18,
                opacity: 0.56,
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                child: Row(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.asset(
                        'assets/images/bekgram_logo.png',
                        width: 30,
                        height: 30,
                        fit: BoxFit.cover,
                      ),
                    ),
                    const SizedBox(width: 10),
                    const Expanded(
                      child: Text(
                        'Bekgram',
                        textAlign: TextAlign.left,
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w900,
                          color: AppTheme.telegramBlue,
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: () => _openCreateGroupSheet(context, ref),
                      tooltip: 'Create group',
                      icon: const Icon(
                        Icons.group_add_rounded,
                        color: AppTheme.telegramBlue,
                      ),
                    ),
                    IconButton(
                      onPressed: () {
                        Navigator.of(context).push(
                          FadePageRoute(page: const SearchScreen()),
                        );
                      },
                      icon: const Icon(
                        Icons.search_rounded,
                        color: AppTheme.telegramBlue,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (me != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: GlassSurface(
                  radius: 20,
                  opacity: 0.54,
                  onTap: () async {
                    try {
                      final chatId = await ref
                          .read(chatActionControllerProvider.notifier)
                          .openSavedChat(me.id);
                      if (!context.mounted) return;
                      Navigator.of(context).push(
                        FadePageRoute(
                          page: ChatScreen(
                            chatId: chatId,
                            peerId: me.id,
                            isSaved: true,
                          ),
                        ),
                      );
                    } catch (error) {
                      if (!context.mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(error.toString())),
                      );
                    }
                  },
                  child: Row(
                    children: [
                      Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(14),
                          gradient: const LinearGradient(
                            colors: [AppTheme.telegramBlue, AppTheme.cyan],
                          ),
                        ),
                        child: const Icon(Icons.bookmark_rounded,
                            color: Colors.white),
                      ),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Saved Messages',
                              style: TextStyle(
                                  fontWeight: FontWeight.w800, fontSize: 16),
                            ),
                            SizedBox(height: 3),
                            Text('Your private notes and links'),
                          ],
                        ),
                      ),
                      Icon(
                        Icons.chevron_right_rounded,
                        color: secondaryText.withValues(alpha: 0.75),
                      ),
                    ],
                  ),
                ),
              ),
            Expanded(
              child: chatsAsync.when(
                data: (chats) {
                  final visibleChats =
                      chats.where((chat) => !chat.isSaved).toList();

                  if (visibleChats.isEmpty) {
                    return Center(
                      child: Text(
                        'No chats yet. Search a username to start chatting.',
                        style: TextStyle(color: secondaryText),
                      ),
                    );
                  }

                  return ListView.builder(
                    padding: const EdgeInsets.only(bottom: 22),
                    itemCount: visibleChats.length,
                    itemBuilder: (context, index) {
                      return ChatTile(chat: visibleChats[index]);
                    },
                  );
                },
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (error, _) => Center(child: Text(error.toString())),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

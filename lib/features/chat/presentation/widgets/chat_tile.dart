import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/navigation/fade_page_route.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/glass_surface.dart';
import '../../../../core/widgets/online_dot.dart';
import '../../../../core/widgets/verification_badge.dart';
import '../../../auth/domain/entities/app_user.dart';
import '../../../auth/presentation/controllers/auth_controller.dart';
import '../../domain/entities/chat_thread.dart';
import '../controllers/chat_controller.dart';
import '../models/sticker_payload.dart';
import '../screens/chat_screen.dart';

class ChatTile extends ConsumerStatefulWidget {
  const ChatTile({
    super.key,
    required this.chat,
  });

  final ChatThread chat;

  @override
  ConsumerState<ChatTile> createState() => _ChatTileState();
}

class _ChatTileState extends ConsumerState<ChatTile> {
  bool _pressed = false;

  Future<void> _showChatActions(BuildContext context, WidgetRef ref) async {
    if (widget.chat.isSaved) return;

    final action = await showModalBottomSheet<String>(
      context: context,
      useRootNavigator: true,
      backgroundColor: Colors.transparent,
      builder: (_) => SafeArea(
        child: Container(
          margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          decoration: BoxDecoration(
            color: Theme.of(context).brightness == Brightness.dark
                ? const Color(0xFF111922).withValues(alpha: 0.96)
                : Colors.white.withValues(alpha: 0.96),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: Colors.white.withValues(alpha: 0.25)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.25),
                blurRadius: 18,
                offset: const Offset(0, 8),
              )
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading:
                    const Icon(Icons.delete_rounded, color: Colors.redAccent),
                title: const Text(
                  'Delete chat',
                  style: TextStyle(
                    color: Colors.redAccent,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                onTap: () => Navigator.of(context).pop('delete'),
              ),
              ListTile(
                leading: const Icon(Icons.close_rounded),
                title: const Text('Cancel'),
                onTap: () => Navigator.of(context).pop(),
              ),
            ],
          ),
        ),
      ),
    );

    if (action != 'delete' || !context.mounted) return;
    final confirmed = await showDialog<bool>(
      context: context,
      useRootNavigator: true,
      builder: (_) => AlertDialog(
        title: const Text('Delete chat?'),
        content: const Text('This will delete all messages in this chat.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true || !context.mounted) return;
    try {
      await ref
          .read(chatActionControllerProvider.notifier)
          .deleteChat(widget.chat.id);
      ref.invalidate(chatListProvider);
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.toString())),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final chat = widget.chat;
    final me = ref.watch(currentUserProvider);
    if (me == null) return const SizedBox.shrink();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final secondaryText = AppTheme.textSecondary(context);

    final peerId = chat.isSaved
        ? me.id
        : chat.isGroup
            ? null
            : chat.participantIds.firstWhere(
                (id) => id != me.id,
                orElse: () => me.id,
              );

    final AsyncValue<AppUser?> peer = peerId != null
        ? ref.watch(userByIdProvider(peerId))
        : const AsyncValue.data(null);
    final isVerifiedUser = !chat.isSaved &&
        !chat.isGroup &&
        ((peer.valueOrNull?.isVerified ?? false) ||
            peer.valueOrNull?.usernameLower == 'asilbek');

    final displayName = chat.isSaved
        ? 'Saved Messages'
        : chat.isGroup
            ? ((chat.title?.trim().isNotEmpty ?? false)
                ? chat.title!.trim()
                : 'Group')
            : (peer.valueOrNull?.displayName.isNotEmpty ?? false)
                ? peer.valueOrNull!.displayName
                : '@$peerId';

    final avatarUrl = chat.isGroup ? null : peer.valueOrNull?.avatarUrl;
    final isOnline = chat.isSaved
        ? true
        : (chat.isGroup ? false : (peer.valueOrNull?.isOnline ?? false));
    final effectiveCanWrite = chat.isSaved
        ? true
        : chat.isGroup
            ? true
            : (peer.valueOrNull?.canReceiveMessages ?? chat.canWrite);

    final rawSubtitle = chat.lastMessage?.trim();
    final parsedSticker =
        rawSubtitle != null ? StickerPayload.tryParse(rawSubtitle) : null;

    final subtitle = rawSubtitle?.isNotEmpty == true
        ? parsedSticker != null
            ? parsedSticker.caption == null
                ? 'Sticker'
                : 'Sticker · ${parsedSticker.caption}'
            : rawSubtitle!
        : chat.isGroup && (chat.groupBio?.trim().isNotEmpty ?? false)
            ? chat.groupBio!.trim()
            : 'Start the conversation';
    final canDeleteChat = !chat.isSaved && (!chat.isGroup || chat.isOwner);

    final tile = AnimatedScale(
      duration: const Duration(milliseconds: 120),
      curve: Curves.easeOutCubic,
      scale: _pressed ? 0.985 : 1.0,
      child: Stack(
        children: [
          GlassSurface(
            margin: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            radius: 30,
            blur: 22,
            opacity: isDark ? 0.36 : 0.56,
            borderColor: Colors.white.withValues(alpha: isDark ? 0.24 : 0.68),
            enableBackdrop: true,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            onTap: () {
              HapticFeedback.selectionClick();
              Navigator.of(context).push(
                FadePageRoute(
                  page: ChatScreen(
                    chatId: chat.id,
                    peerId: peerId,
                    isSaved: chat.isSaved,
                    initialChat: chat,
                  ),
                ),
              );
            },
            onLongPress: canDeleteChat
                ? () {
                    HapticFeedback.mediumImpact();
                    _showChatActions(context, ref);
                  }
                : null,
            onSecondaryTapDown:
                canDeleteChat ? (_) => _showChatActions(context, ref) : null,
            child: Row(
              children: [
                Stack(
                  clipBehavior: Clip.none,
                  children: [
                    CircleAvatar(
                      radius: 26,
                      backgroundColor:
                          AppTheme.telegramBlue.withValues(alpha: 0.3),
                      backgroundImage: avatarUrl != null && avatarUrl.isNotEmpty
                          ? NetworkImage(avatarUrl)
                          : null,
                      onBackgroundImageError:
                          avatarUrl != null && avatarUrl.isNotEmpty
                              ? (_, __) {}
                              : null,
                      child: avatarUrl == null || avatarUrl.isEmpty
                          ? chat.isGroup
                              ? const Icon(Icons.groups_rounded)
                              : Text(
                                  displayName.isNotEmpty
                                      ? displayName[0].toUpperCase()
                                      : '?',
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w700),
                                )
                          : null,
                    ),
                    Positioned(
                      right: -2,
                      bottom: -2,
                      child: OnlineDot(isOnline: isOnline),
                    ),
                  ],
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text.rich(
                              TextSpan(
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w800,
                                ),
                                children: [
                                  TextSpan(text: displayName),
                                  if (isVerifiedUser)
                                    WidgetSpan(
                                      alignment: PlaceholderAlignment.middle,
                                      child: Padding(
                                        padding:
                                            const EdgeInsets.only(left: 4),
                                        child: VerificationBadge(
                                          usernameLower:
                                              peer.valueOrNull?.usernameLower ??
                                                  '',
                                          isVerified:
                                              peer.valueOrNull?.isVerified ??
                                                  false,
                                          size: 16,
                                        ),
                                      ),
                                    ),
                                  if (!effectiveCanWrite)
                                    const WidgetSpan(
                                      alignment: PlaceholderAlignment.middle,
                                      child: Padding(
                                        padding: EdgeInsets.only(left: 4),
                                        child: Icon(
                                          Icons.lock_rounded,
                                          size: 14,
                                          color: Colors.orangeAccent,
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 3),
                      Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: secondaryText,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      if (!effectiveCanWrite)
                        const Padding(
                          padding: EdgeInsets.only(top: 2),
                          child: Text(
                            'You cannot write in this chat',
                            style: TextStyle(
                              color: Colors.orangeAccent,
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                if (canDeleteChat)
                  PopupMenuButton<String>(
                    onSelected: (value) {
                      if (value == 'delete') {
                        _showChatActions(context, ref);
                      }
                    },
                    icon: const Icon(Icons.more_vert_rounded),
                    itemBuilder: (_) => const [
                      PopupMenuItem<String>(
                        value: 'delete',
                        child: Text('Delete chat'),
                      ),
                    ],
                  ),
                if (chat.unreadCount > 0)
                  Container(
                    margin: const EdgeInsets.only(left: 8),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                    decoration: BoxDecoration(
                      color: AppTheme.telegramBlue,
                      borderRadius: BorderRadius.circular(99),
                      border: Border.all(
                        color: Colors.redAccent,
                        width: 1.4,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.18),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Text(
                      chat.unreadCount.toString(),
                      style: const TextStyle(
                          color: Colors.white, fontWeight: FontWeight.w700),
                    ),
                  ),
              ],
            ),
          ),
          // Press highlight overlay for glass realism
          Positioned.fill(
            child: IgnorePointer(
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 120),
                curve: Curves.easeOutCubic,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(30),
                  color: _pressed
                      ? (isDark
                          ? Colors.white.withValues(alpha: 0.06)
                          : Colors.white.withValues(alpha: 0.08))
                      : Colors.transparent,
                ),
              ),
            ),
          ),
        ],
      ),
    );

    return Listener(
      onPointerDown: (_) => setState(() => _pressed = true),
      onPointerUp: (_) => setState(() => _pressed = false),
      onPointerCancel: (_) => setState(() => _pressed = false),
      child: Dismissible(
        key: ValueKey('chat-${chat.id}'),
        direction: canDeleteChat ? DismissDirection.endToStart : DismissDirection.none,
        confirmDismiss: (direction) async {
          if (direction == DismissDirection.endToStart && canDeleteChat) {
            HapticFeedback.lightImpact();
            await _showChatActions(context, ref);
          }
          return false; // we manage deletion manually
        },
        background: _SwipeBackground.delete(),
        child: tile,
      ),
    );
  }
}

class _SwipeBackground extends StatelessWidget {
  const _SwipeBackground.delete();

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(30),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: isDark
              ? [
                  const Color(0xFF330000).withValues(alpha: 0.7),
                  const Color(0xFF220000).withValues(alpha: 0.6),
                ]
              : [
                  const Color(0xFFFFCDD2).withValues(alpha: 0.9),
                  const Color(0xFFFF8A80).withValues(alpha: 0.8),
                ],
        ),
        border: Border.all(
          color: Colors.white.withValues(alpha: isDark ? 0.2 : 0.65),
          width: 1.0,
        ),
        boxShadow: [
          BoxShadow(
            color: isDark
                ? Colors.black.withValues(alpha: 0.35)
                : const Color(0x66FFFFFF),
            blurRadius: 24,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      alignment: Alignment.centerRight,
      padding: const EdgeInsets.only(right: 28),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: const [
          Icon(Icons.delete_rounded, color: Colors.white, size: 22),
          SizedBox(width: 8),
          Text(
            'Delete',
            style: TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

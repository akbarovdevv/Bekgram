import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

import '../../../../core/navigation/fade_page_route.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/glass_background.dart';
import '../../../../core/widgets/glass_surface.dart';
import '../../../../core/widgets/verification_badge.dart';
import '../../../auth/domain/entities/app_user.dart';
import '../../../auth/presentation/controllers/auth_controller.dart';
import '../../../chat/presentation/controllers/chat_controller.dart';
import '../../../chat/presentation/screens/chat_screen.dart';

class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key, this.userId});

  final String? userId;

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  final TextEditingController _verifyUsernameController =
      TextEditingController();
  bool _targetVerified = true;
  bool _updatingVerification = false;
  bool _submittingVerificationRequest = false;

  @override
  void dispose() {
    _verifyUsernameController.dispose();
    super.dispose();
  }

  Future<void> _openEditSheet(AppUser user) async {
    await showModalBottomSheet<void>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _EditProfileSheet(
        user: user,
        onSaved: () {
          ref.invalidate(userByIdProvider(user.id));
        },
      ),
    );
  }

  Future<void> _applyVerificationByUsername() async {
    if (_updatingVerification) return;

    final raw = _verifyUsernameController.text.trim();
    final username = raw.startsWith('@') ? raw.substring(1) : raw;
    if (username.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Username kiriting. Masalan: @mavjud')),
      );
      return;
    }

    setState(() => _updatingVerification = true);
    try {
      final updated =
          await ref.read(authRepositoryProvider).setUserVerification(
                username: username,
                isVerified: _targetVerified,
              );

      ref.invalidate(userByIdProvider(updated.id));
      ref.invalidate(chatListProvider);
      ref.invalidate(searchUsersProvider);

      if (!mounted) return;
      setState(() => _updatingVerification = false);
      final actionText = _targetVerified
          ? 'verification berildi'
          : 'verification olib tashlandi';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('@${updated.username} uchun $actionText')),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => _updatingVerification = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.toString())),
      );
    }
  }

  Future<void> _sendVerificationRequest(AppUser user) async {
    if (_submittingVerificationRequest) return;

    final blockedUntil = user.verifyRequestBlockedUntil;
    if (blockedUntil != null && blockedUntil.isAfter(DateTime.now())) {
      final atText = DateFormat('MMM d, HH:mm').format(blockedUntil);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('So\'rov rad etilgan. Qayta yuborish: $atText'),
        ),
      );
      return;
    }

    setState(() => _submittingVerificationRequest = true);
    try {
      final request = await ref
          .read(chatActionControllerProvider.notifier)
          .requestVerification();
      ref.invalidate(chatListProvider);

      if (!mounted) return;
      setState(() => _submittingVerificationRequest = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(request.message)),
      );

      Navigator.of(context).push(
        FadePageRoute(
          page: ChatScreen(
            chatId: request.chatId,
            peerId: request.reviewerId,
            isSaved: false,
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => _submittingVerificationRequest = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.toString())),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final current = ref.watch(currentUserProvider);
    final secondaryText = AppTheme.textSecondary(context);
    final effectiveUserId = widget.userId ?? current?.id;

    if (effectiveUserId == null) {
      return const SizedBox.shrink();
    }

    final userAsync = ref.watch(userByIdProvider(effectiveUserId));
    final isMe = current?.id == effectiveUserId;

    return Scaffold(
      body: GlassBackground(
        child: userAsync.when(
          data: (user) {
            if (user == null) {
              return const Center(child: Text('User not found'));
            }
            final isVerificationAdmin = isMe &&
                (user.usernameLower == 'asilbek' ||
                    user.usernameLower == 'verify');
            final hasVerificationBadge =
                user.isVerified || user.usernameLower == 'asilbek';

            return CustomScrollView(
              slivers: [
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
                    child: GlassSurface(
                      radius: 28,
                      opacity: 0.58,
                      blur: 18,
                      padding: const EdgeInsets.fromLTRB(14, 14, 14, 16),
                      child: Column(
                        children: [
                          Row(
                            children: [
                              IconButton(
                                onPressed: () =>
                                    Navigator.of(context).maybePop(),
                                icon: const Icon(
                                    Icons.arrow_back_ios_new_rounded),
                              ),
                              const Spacer(),
                              if (isMe)
                                IconButton(
                                  onPressed: () => _openEditSheet(user),
                                  icon: const Icon(Icons.edit_rounded),
                                ),
                            ],
                          ),
                          Hero(
                            tag: 'avatar_${user.id}',
                            child: _LiquidGlassAvatar(
                              size: 112,
                              imageUrl: user.avatarUrl,
                            ),
                          ),
                          const SizedBox(height: 12),
                          Text.rich(
                            TextSpan(
                              style: const TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.w900,
                              ),
                              children: [
                                TextSpan(text: user.displayName),
                                if (hasVerificationBadge)
                                  WidgetSpan(
                                    alignment: PlaceholderAlignment.middle,
                                    child: Padding(
                                      padding: const EdgeInsets.only(left: 6),
                                      child: VerificationBadge(
                                        usernameLower: user.usernameLower,
                                        isVerified: user.isVerified,
                                        size: 20,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 4),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                '@${user.username}',
                                style: const TextStyle(
                                  color: AppTheme.telegramBlue,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 15,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          Text(
                            user.isOnline
                                ? 'online now'
                                : 'last seen ${DateFormat('MMM d, HH:mm').format(user.lastSeen)}',
                            style: TextStyle(
                              color: secondaryText,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                user.canReceiveMessages
                                    ? Icons.lock_open_rounded
                                    : Icons.lock_rounded,
                                size: 14,
                                color: user.canReceiveMessages
                                    ? AppTheme.telegramBlue
                                    : Colors.orangeAccent,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                user.canReceiveMessages
                                    ? 'messages: open'
                                    : 'messages: locked',
                                style: TextStyle(
                                  color: secondaryText,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: GlassSurface(
                      radius: 24,
                      opacity: 0.56,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _InfoRow(label: 'Bio', value: user.bio),
                          const Divider(height: 20),
                          _InfoRow(
                              label: 'Phone',
                              value: user.phoneNumber ?? 'Not added'),
                          const Divider(height: 20),
                          _InfoRow(
                              label: 'Username', value: '@${user.username}'),
                          if (hasVerificationBadge) ...[
                            const Divider(height: 20),
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 10,
                              ),
                              decoration: BoxDecoration(
                                color: AppTheme.telegramBlue.withValues(
                                  alpha: 0.11,
                                ),
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(
                                  color: AppTheme.telegramBlue.withValues(
                                    alpha: 0.4,
                                  ),
                                ),
                              ),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Padding(
                                    padding: EdgeInsets.only(top: 1),
                                    child: Icon(
                                      Icons.verified_rounded,
                                      size: 16,
                                      color: AppTheme.telegramBlue,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      'This profile was verified by the organization "Bekgram".',
                                      style: TextStyle(
                                        color: secondaryText.withValues(
                                          alpha: 0.96,
                                        ),
                                        fontWeight: FontWeight.w700,
                                        fontSize: 12.5,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const Divider(height: 20),
                          ] else ...[
                            const Divider(height: 20),
                          ],
                          _InfoRow(
                            label: 'Incoming messages',
                            value:
                                user.canReceiveMessages ? 'Allowed' : 'Blocked',
                          ),
                          if (user.verifyRequestBlockedUntil != null &&
                              user.verifyRequestBlockedUntil!
                                  .isAfter(DateTime.now())) ...[
                            const Divider(height: 20),
                            _InfoRow(
                              label: 'Verify retry',
                              value: DateFormat('MMM d, HH:mm')
                                  .format(user.verifyRequestBlockedUntil!),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
                    child: isVerificationAdmin
                        ? GlassSurface(
                            radius: 24,
                            opacity: 0.56,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Verification manager',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w900,
                                    fontSize: 17,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'Username yozing va verificationni bering yoki olib tashlang.',
                                  style: TextStyle(
                                    color: secondaryText,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(height: 10),
                                TextField(
                                  controller: _verifyUsernameController,
                                  textInputAction: TextInputAction.done,
                                  decoration: const InputDecoration(
                                    labelText: 'Username',
                                    hintText: '@username',
                                  ),
                                ),
                                const SizedBox(height: 8),
                                SwitchListTile(
                                  contentPadding: EdgeInsets.zero,
                                  dense: true,
                                  value: _targetVerified,
                                  title: Text(
                                    _targetVerified
                                        ? 'Set as verified'
                                        : 'Remove verification',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  onChanged: (value) {
                                    setState(() => _targetVerified = value);
                                  },
                                ),
                                const SizedBox(height: 8),
                                FilledButton.icon(
                                  onPressed: _updatingVerification
                                      ? null
                                      : _applyVerificationByUsername,
                                  icon: _updatingVerification
                                      ? const SizedBox(
                                          width: 16,
                                          height: 16,
                                          child: CircularProgressIndicator(
                                              strokeWidth: 2),
                                        )
                                      : Icon(
                                          _targetVerified
                                              ? Icons.verified_rounded
                                              : Icons.remove_circle_rounded,
                                        ),
                                  label: Text(
                                    _updatingVerification
                                        ? 'Saving...'
                                        : (_targetVerified
                                            ? 'Apply verification'
                                            : 'Remove verification'),
                                  ),
                                  style: FilledButton.styleFrom(
                                    minimumSize: const Size.fromHeight(46),
                                    backgroundColor: AppTheme.telegramBlue,
                                    foregroundColor: Colors.white,
                                  ),
                                ),
                              ],
                            ),
                          )
                        : const SizedBox.shrink(),
                  ),
                ),
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 14, 16, 22),
                    child: Column(
                      children: [
                        if (isMe && !isVerificationAdmin)
                          FilledButton.icon(
                            onPressed: _submittingVerificationRequest
                                ? null
                                : () => _sendVerificationRequest(user),
                            icon: _submittingVerificationRequest
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2),
                                  )
                                : const Icon(Icons.mark_chat_unread_rounded),
                            label: Text(
                              _submittingVerificationRequest
                                  ? 'Sending...'
                                  : '/get',
                            ),
                            style: FilledButton.styleFrom(
                              minimumSize: const Size.fromHeight(50),
                              backgroundColor: AppTheme.telegramBlue,
                              foregroundColor: Colors.white,
                            ),
                          ),
                        if (isMe && !isVerificationAdmin)
                          const SizedBox(height: 10),
                        if (isMe)
                          OutlinedButton.icon(
                            onPressed: () => _openEditSheet(user),
                            icon: const Icon(Icons.photo_camera_back_rounded),
                            label: const Text('Edit Profile & Photo'),
                            style: OutlinedButton.styleFrom(
                              minimumSize: const Size.fromHeight(50),
                              side: BorderSide(
                                color: AppTheme.telegramBlue
                                    .withValues(alpha: 0.5),
                              ),
                            ),
                          ),
                        if (isMe) const SizedBox(height: 10),
                        if (isMe)
                          FilledButton.icon(
                            onPressed: () => ref
                                .read(authControllerProvider.notifier)
                                .signOut(),
                            icon: const Icon(Icons.logout_rounded),
                            label: const Text('Log out'),
                            style: FilledButton.styleFrom(
                              backgroundColor: Colors.redAccent,
                              foregroundColor: Colors.white,
                              minimumSize: const Size.fromHeight(50),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            );
          },
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) => Center(child: Text(error.toString())),
        ),
      ),
    );
  }
}

class _EditProfileSheet extends ConsumerStatefulWidget {
  const _EditProfileSheet({
    required this.user,
    required this.onSaved,
  });

  final AppUser user;
  final VoidCallback onSaved;

  @override
  ConsumerState<_EditProfileSheet> createState() => _EditProfileSheetState();
}

class _EditProfileSheetState extends ConsumerState<_EditProfileSheet> {
  late final TextEditingController _displayNameController;
  late final TextEditingController _bioController;
  late final TextEditingController _phoneController;
  late final TextEditingController _avatarUrlController;

  Uint8List? _pickedAvatarBytes;
  String? _avatarBase64;
  String? _avatarMimeType;
  String? _avatarFileName;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _displayNameController =
        TextEditingController(text: widget.user.displayName);
    _bioController = TextEditingController(text: widget.user.bio);
    _phoneController =
        TextEditingController(text: widget.user.phoneNumber ?? '');
    _avatarUrlController = TextEditingController(text: widget.user.avatarUrl);
  }

  @override
  void dispose() {
    _displayNameController.dispose();
    _bioController.dispose();
    _phoneController.dispose();
    _avatarUrlController.dispose();
    super.dispose();
  }

  Future<void> _pickAvatarFromGallery() async {
    try {
      final picker = ImagePicker();
      final file = await picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1024,
        imageQuality: 80,
      );
      if (file == null) return;

      final bytes = await file.readAsBytes();
      if (!mounted) return;

      setState(() {
        _pickedAvatarBytes = bytes;
        _avatarBase64 = base64Encode(bytes);
        _avatarMimeType = file.mimeType;
        _avatarFileName = file.name;
      });
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Rasm tanlashda xatolik bo'ldi.")),
      );
    }
  }

  Future<void> _saveProfile() async {
    if (_saving) return;
    setState(() => _saving = true);

    final avatarUrlValue =
        _avatarBase64 == null ? _avatarUrlController.text.trim() : null;

    final error = await ref.read(authControllerProvider.notifier).updateProfile(
          displayName: _displayNameController.text.trim(),
          bio: _bioController.text.trim(),
          phoneNumber: _phoneController.text.trim(),
          avatarUrl: avatarUrlValue,
          avatarBase64: _avatarBase64,
          avatarMimeType: _avatarMimeType,
          avatarFileName: _avatarFileName,
        );

    if (!mounted) return;
    setState(() => _saving = false);

    if (error != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error)),
      );
      return;
    }

    widget.onSaved();
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    ImageProvider<Object>? imageProvider;
    if (_pickedAvatarBytes != null) {
      imageProvider = MemoryImage(_pickedAvatarBytes!);
    } else if (_avatarUrlController.text.trim().isNotEmpty) {
      imageProvider = NetworkImage(_avatarUrlController.text.trim());
    }

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(12, 12, 12, bottom + 12),
        child: GlassSurface(
          radius: 28,
          blur: 20,
          opacity: AppTheme.isDark(context) ? 0.58 : 0.92,
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    const Text(
                      'Edit profile',
                      style:
                          TextStyle(fontWeight: FontWeight.w900, fontSize: 20),
                    ),
                    const Spacer(),
                    IconButton(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Center(
                  child: CircleAvatar(
                    radius: 44,
                    backgroundImage: imageProvider,
                    onBackgroundImageError:
                        imageProvider is NetworkImage ? (_, __) {} : null,
                    child: imageProvider == null
                        ? const Icon(Icons.person_rounded, size: 34)
                        : null,
                  ),
                ),
                const SizedBox(height: 10),
                Center(
                  child: OutlinedButton.icon(
                    onPressed: _pickAvatarFromGallery,
                    icon: const Icon(Icons.photo_library_rounded),
                    label: const Text('Choose photo'),
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _displayNameController,
                  decoration: const InputDecoration(labelText: 'Display name'),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _bioController,
                  maxLines: 2,
                  decoration: const InputDecoration(labelText: 'Bio'),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _phoneController,
                  decoration:
                      const InputDecoration(labelText: 'Phone (optional)'),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _avatarUrlController,
                  onChanged: (_) => setState(() {}),
                  decoration:
                      const InputDecoration(labelText: 'Avatar URL (optional)'),
                ),
                const SizedBox(height: 14),
                FilledButton.icon(
                  onPressed: _saving ? null : _saveProfile,
                  icon: _saving
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.save_rounded),
                  label: Text(_saving ? 'Saving...' : 'Save profile'),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(50),
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
  }
}

class _LiquidGlassAvatar extends StatefulWidget {
  const _LiquidGlassAvatar({
    required this.size,
    required this.imageUrl,
  });

  final double size;
  final String imageUrl;

  @override
  State<_LiquidGlassAvatar> createState() => _LiquidGlassAvatarState();
}

class _LiquidGlassAvatarState extends State<_LiquidGlassAvatar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final size = widget.size;

    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        children: [
          // Outer liquid glass ring
          Container(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Colors.white.withValues(alpha: isDark ? 0.16 : 0.36),
                  Colors.white.withValues(alpha: isDark ? 0.06 : 0.18),
                ],
              ),
              border: Border.all(
                color: Colors.white.withValues(alpha: isDark ? 0.18 : 0.58),
                width: 1.1,
              ),
              boxShadow: [
                BoxShadow(
                  color: isDark
                      ? Colors.black.withValues(alpha: 0.35)
                      : const Color(0x55FFFFFF),
                  blurRadius: 28,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
          ),
          // Avatar content
          ClipOval(
            child: Container(
              color: Colors.black.withValues(alpha: 0.02),
              child: widget.imageUrl.isNotEmpty
                  ? Image.network(
                      widget.imageUrl,
                      fit: BoxFit.cover,
                      width: size,
                      height: size,
                      errorBuilder: (_, __, ___) => const Icon(
                        Icons.person_rounded,
                        size: 36,
                      ),
                    )
                  : const Center(
                      child: Icon(Icons.person_rounded, size: 36),
                    ),
            ),
          ),
          // Subtle animated light reflection sweep
          Positioned.fill(
            child: IgnorePointer(
              child: AnimatedBuilder(
                animation: _ctrl,
                builder: (context, child) {
                  final t = _ctrl.value; // 0..1
                  final dx = -1.2 + 2.4 * t; // move left -> right
                  return Align(
                    alignment: Alignment(dx, -0.2),
                    child: Transform.rotate(
                      angle: -0.7,
                      child: Container(
                        width: size * 0.35,
                        height: size * 1.4,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(999),
                          gradient: LinearGradient(
                            begin: Alignment.centerLeft,
                            end: Alignment.centerRight,
                            colors: [
                              Colors.white.withValues(alpha: isDark ? 0.12 : 0.28),
                              Colors.white.withValues(alpha: 0.0),
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 90,
          child: Text(
            label,
            style: TextStyle(
              color: AppTheme.textSecondary(context),
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
        ),
      ],
    );
  }
}

import 'dart:async';
import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:record/record.dart';

import '../../../../core/navigation/fade_page_route.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/glass_background.dart';
import '../../../../core/widgets/glass_surface.dart';
import '../../../../core/widgets/verification_badge.dart';
import '../../../auth/domain/entities/app_user.dart';
import '../../../auth/presentation/controllers/auth_controller.dart';
import '../../domain/entities/chat_thread.dart';
import '../../../profile/presentation/screens/profile_screen.dart';
import '../controllers/chat_controller.dart';
import '../models/media_payload.dart';
import '../controllers/sticker_catalog.dart';
import '../models/sticker_payload.dart';
import '../models/verification_request_payload.dart';
import '../services/voice_file_helper.dart';
import '../widgets/message_bubble.dart';
import '../widgets/sticker_picker_sheet.dart';

class ChatScreen extends ConsumerStatefulWidget {
  const ChatScreen({
    super.key,
    required this.chatId,
    this.peerId,
    required this.isSaved,
    this.initialChat,
  });

  final String chatId;
  final String? peerId;
  final bool isSaved;
  final ChatThread? initialChat;

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  final _textController = TextEditingController();
  final _scrollController = ScrollController();
  final _audioRecorder = AudioRecorder();
  final Set<String> _verificationActionLoading = <String>{};
  String? _pendingStickerAssetPath;
  bool _didInitialScroll = false;
  int _lastMessageCount = 0;
  bool _isRecordingVoice = false;
  int _recordingSeconds = 0;
  DateTime? _recordingStartedAt;
  Timer? _recordingTicker;
  _VoiceCodec? _activeVoiceCodec;

  static const _inlineStickerMarker = '🤝';
  static const _maxUploadBytes = 25 * 1024 * 1024;
  static const _minVoiceDuration = Duration(milliseconds: 450);
  static const _voiceCodecPriority = <_VoiceCodec>[
    _VoiceCodec(
      encoder: AudioEncoder.aacLc,
      extension: 'm4a',
      mimeType: 'audio/mp4',
    ),
    _VoiceCodec(
      encoder: AudioEncoder.opus,
      extension: 'opus',
      mimeType: 'audio/opus',
    ),
    _VoiceCodec(
      encoder: AudioEncoder.wav,
      extension: 'wav',
      mimeType: 'audio/wav',
    ),
    _VoiceCodec(
      encoder: AudioEncoder.flac,
      extension: 'flac',
      mimeType: 'audio/flac',
    ),
  ];
  static const _webVoiceCodecPriority = <_VoiceCodec>[
    _VoiceCodec(
      encoder: AudioEncoder.wav,
      extension: 'wav',
      mimeType: 'audio/wav',
    ),
    _VoiceCodec(
      encoder: AudioEncoder.opus,
      extension: 'webm',
      mimeType: 'audio/webm',
    ),
  ];

  @override
  void dispose() {
    _recordingTicker?.cancel();
    if (_isRecordingVoice) {
      _audioRecorder.stop();
    }
    _audioRecorder.dispose();
    _textController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToBottom({bool animated = true}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      final target = _scrollController.position.maxScrollExtent;
      if (!animated) {
        _scrollController.jumpTo(target);
        return;
      }
      _scrollController.animateTo(
        target,
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOut,
      );
    });
  }

  void _syncScrollWithMessages(int messageCount) {
    if (messageCount <= 0) return;

    if (!_didInitialScroll) {
      _didInitialScroll = true;
      _lastMessageCount = messageCount;
      _scrollToBottom(animated: false);
      return;
    }

    final hasNewMessages = messageCount > _lastMessageCount;
    _lastMessageCount = messageCount;
    if (!hasNewMessages) return;

    if (!_scrollController.hasClients) {
      _scrollToBottom();
      return;
    }

    final distanceToBottom =
        _scrollController.position.maxScrollExtent - _scrollController.offset;
    if (distanceToBottom < 120) {
      _scrollToBottom();
    }
  }

  void _insertStickerMarkerIfNeeded() {
    final current = _textController.text;
    if (current.contains(_inlineStickerMarker)) return;

    final trimmedRight = current.replaceFirst(RegExp(r'\s+$'), '');
    final next = trimmedRight.isEmpty
        ? _inlineStickerMarker
        : '$trimmedRight $_inlineStickerMarker';

    _textController.value = TextEditingValue(
      text: next,
      selection: TextSelection.collapsed(offset: next.length),
    );
  }

  Future<void> _send() async {
    final me = ref.read(currentUserProvider);
    if (me == null) return;

    final text = _textController.text.trim();
    final pendingSticker = _pendingStickerAssetPath;

    if (pendingSticker != null) {
      final normalizedCaption = text
          .replaceAll(_inlineStickerMarker, '')
          .replaceAll(RegExp(r'\s{2,}'), ' ')
          .trim();
      final payload = StickerPayload(
        stickerAssetPath: pendingSticker,
        caption: normalizedCaption.isEmpty ? null : normalizedCaption,
      ).encode();

      await ref.read(chatActionControllerProvider.notifier).sendMessage(
            chatId: widget.chatId,
            senderId: me.id,
            text: payload,
            isSticker: true,
            type: 'sticker',
          );

      if (mounted) {
        setState(() => _pendingStickerAssetPath = null);
      }
      _textController.clear();
      _scrollToBottom();
      return;
    }

    if (text.isEmpty) return;

    final normalizedCommand = text.toLowerCase();
    if (normalizedCommand == '/get' || normalizedCommand == '/verify') {
      await _sendVerificationRequestFromChat(me);
      return;
    }

    await ref.read(chatActionControllerProvider.notifier).sendMessage(
          chatId: widget.chatId,
          senderId: me.id,
          text: text,
          isSticker: false,
        );

    _textController.clear();
    _scrollToBottom();
  }

  Future<void> _sendVerificationRequestFromChat(AppUser me) async {
    if (_isVerificationAdmin(me)) {
      _textController.clear();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Admin akkaunt uchun /get komandasi ishlatilmaydi.'),
        ),
      );
      return;
    }

    try {
      final request = await ref
          .read(chatActionControllerProvider.notifier)
          .requestVerification();
      ref.invalidate(chatListProvider);

      _textController.clear();
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(request.message)),
      );

      final alreadyInReviewerChat = request.chatId == widget.chatId;
      if (alreadyInReviewerChat) {
        _scrollToBottom();
        return;
      }

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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.toString())),
      );
    }
  }

  Future<void> _sendStickerDirect(String stickerAssetPath) async {
    final me = ref.read(currentUserProvider);
    if (me == null) return;

    final payload = StickerPayload(
      stickerAssetPath: stickerAssetPath,
      caption: null,
    ).encode();

    await ref.read(chatActionControllerProvider.notifier).sendMessage(
          chatId: widget.chatId,
          senderId: me.id,
          text: payload,
          isSticker: true,
          type: 'sticker',
        );

    if (mounted) {
      setState(() => _pendingStickerAssetPath = null);
    }
    _scrollToBottom();
  }

  Future<void> _openStickerPicker() async {
    final stickers = await ref.read(availableStickersProvider.future);
    if (!mounted) return;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final selected = await showModalBottomSheet<String>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: false,
      backgroundColor: isDark
          ? const Color(0xFF0B0F15).withValues(alpha: 0.96)
          : Colors.white.withValues(alpha: 0.9),
      builder: (_) => StickerPickerSheet(stickers: stickers),
    );

    if (selected == null || selected.isEmpty) return;

    final hasTypedText = _textController.text.trim().isNotEmpty;
    if (!hasTypedText) {
      await _sendStickerDirect(selected);
      return;
    }

    if (!mounted) return;
    setState(() => _pendingStickerAssetPath = selected);
    _insertStickerMarkerIfNeeded();
  }

  Future<void> _pickAndSendMedia(String kind) async {
    final me = ref.read(currentUserProvider);
    if (me == null) return;

    final fileType = switch (kind) {
      'image' => FileType.image,
      'video' => FileType.video,
      _ => throw Exception('Unsupported media type: $kind'),
    };

    final result = await FilePicker.platform.pickFiles(
      type: fileType,
      withData: true,
      allowMultiple: false,
    );
    if (!mounted || result == null || result.files.isEmpty) return;

    final file = result.files.single;
    final bytes = file.bytes;
    if (bytes == null || bytes.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Faylni o\'qib bo\'lmadi')),
      );
      return;
    }

    if (bytes.length > _maxUploadBytes) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Fayl 25MB dan kichik bo\'lishi kerak')),
      );
      return;
    }

    final base64 = base64Encode(bytes);
    final uploaded =
        await ref.read(chatActionControllerProvider.notifier).uploadMedia(
              chatId: widget.chatId,
              kind: kind,
              base64: base64,
              fileName: file.name,
              mimeType: file.extension ?? '',
            );

    final payload = MediaPayload.fromAttachment(uploaded).encode();
    await ref.read(chatActionControllerProvider.notifier).sendMessage(
          chatId: widget.chatId,
          senderId: me.id,
          text: payload,
          type: kind,
        );
    _scrollToBottom();
  }

  Future<void> _showAttachmentSheet(bool canWrite) async {
    if (!canWrite) return;

    final selected = await showModalBottomSheet<String>(
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
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.image_rounded),
                title: const Text('Send image'),
                onTap: () => Navigator.of(context).pop('image'),
              ),
              ListTile(
                leading: const Icon(Icons.videocam_rounded),
                title: const Text('Send video'),
                onTap: () => Navigator.of(context).pop('video'),
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

    if (selected == null) return;
    try {
      await _pickAndSendMedia(selected);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.toString())),
      );
    }
  }

  Future<void> _startVoiceRecording(bool canWrite) async {
    if (!canWrite || _isRecordingVoice) return;

    try {
      final hasPermission = await _audioRecorder.hasPermission();
      if (!hasPermission) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Mikrofon ruxsati berilmagan')),
        );
        return;
      }

      final candidates = kIsWeb ? _webVoiceCodecPriority : _voiceCodecPriority;
      _VoiceCodec? selectedCodec;
      for (final codec in candidates) {
        final ok = await _audioRecorder.isEncoderSupported(codec.encoder);
        if (ok) {
          selectedCodec = codec;
          break;
        }
      }

      if (selectedCodec == null) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Ushbu qurilmada voice encoder topilmadi')),
        );
        return;
      }

      _activeVoiceCodec = selectedCodec;
      final recordPath = await createVoiceRecordingPath();
      await _audioRecorder.start(
        RecordConfig(
          encoder: selectedCodec.encoder,
          bitRate: 128000,
          sampleRate: 44100,
        ),
        path: '$recordPath.${selectedCodec.extension}',
      );

      if (!mounted) return;
      _recordingTicker?.cancel();
      setState(() {
        _isRecordingVoice = true;
        _recordingSeconds = 0;
        _recordingStartedAt = DateTime.now();
      });

      _recordingTicker = Timer.periodic(const Duration(seconds: 1), (_) {
        if (!mounted || !_isRecordingVoice) return;
        setState(() => _recordingSeconds += 1);
      });
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.toString())),
      );
    }
  }

  Future<void> _deleteTempVoiceFile(String? path) async {
    await deleteVoiceRecordingFile(path);
  }

  Future<void> _stopVoiceRecording({
    required bool sendAfterStop,
  }) async {
    if (!_isRecordingVoice) return;

    _recordingTicker?.cancel();
    final startedAt = _recordingStartedAt;

    String? localPath;
    try {
      localPath = await _audioRecorder.stop();
    } catch (_) {
      localPath = null;
    }

    final duration = startedAt == null
        ? Duration.zero
        : DateTime.now().difference(startedAt);

    if (mounted) {
      setState(() {
        _isRecordingVoice = false;
        _recordingSeconds = 0;
        _recordingStartedAt = null;
      });
    }

    final activeCodec = _activeVoiceCodec;
    _activeVoiceCodec = null;

    final shouldSend = sendAfterStop && duration >= _minVoiceDuration;
    if (!shouldSend) {
      await _deleteTempVoiceFile(localPath);
      return;
    }

    if (!supportsRecordedVoiceFileAccess) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Webda voice yuborish hozircha yoq')),
      );
      return;
    }

    if (localPath == null || localPath.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Voice yozib olinmadi')),
      );
      return;
    }
    if (activeCodec == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Voice format aniqlanmadi')),
      );
      await _deleteTempVoiceFile(localPath);
      return;
    }

    final me = ref.read(currentUserProvider);
    if (me == null) {
      await _deleteTempVoiceFile(localPath);
      return;
    }

    try {
      final bytes = await readVoiceRecordingBytes(localPath);
      if (bytes == null) {
        throw Exception('Voice fayl topilmadi');
      }
      if (bytes.isEmpty) {
        throw Exception('Voice yozuvi bo\'sh');
      }
      if (bytes.length > _maxUploadBytes) {
        throw Exception('Voice 25MB dan kichik bo\'lishi kerak');
      }

      final uploaded =
          await ref.read(chatActionControllerProvider.notifier).uploadMedia(
                chatId: widget.chatId,
                kind: 'voice',
                base64: base64Encode(bytes),
                fileName:
                    'voice-${DateTime.now().millisecondsSinceEpoch}.${activeCodec.extension}',
                mimeType: activeCodec.mimeType,
              );

      final payload = MediaPayload.fromAttachment(uploaded).encode();
      await ref.read(chatActionControllerProvider.notifier).sendMessage(
            chatId: widget.chatId,
            senderId: me.id,
            text: payload,
            type: 'voice',
          );

      _scrollToBottom();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.toString())),
      );
    } finally {
      await _deleteTempVoiceFile(localPath);
    }
  }

  Future<void> _showMessageActions({
    required String messageId,
    required bool canDelete,
  }) async {
    if (!canDelete) return;

    final selected = await showModalBottomSheet<String>(
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
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading:
                    const Icon(Icons.delete_rounded, color: Colors.redAccent),
                title: const Text(
                  'Delete message',
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

    if (selected != 'delete' || !mounted) return;
    try {
      await ref.read(chatActionControllerProvider.notifier).deleteMessage(
            chatId: widget.chatId,
            messageId: messageId,
          );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.toString())),
      );
    }
  }

  Future<void> _showChatMenu() async {
    if (widget.isSaved) return;
    final isGroupOwner = widget.initialChat?.isGroup == true &&
        (widget.initialChat?.isOwner == true);
    final canDeleteChat =
        widget.initialChat?.isGroup == true ? isGroupOwner : true;

    final selected = await showModalBottomSheet<String>(
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
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (isGroupOwner) ...[
                ListTile(
                  leading: const Icon(Icons.person_add_alt_rounded),
                  title: const Text(
                    'Add members',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  onTap: () => Navigator.of(context).pop('add-members'),
                ),
              ],
              if (canDeleteChat)
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

    if (selected == 'add-members') {
      await _showAddGroupMembersSheet();
      return;
    }
    if (selected != 'delete' || !mounted) return;

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

    if (confirmed != true || !mounted) return;

    try {
      await ref.read(chatActionControllerProvider.notifier).deleteChat(
            widget.chatId,
          );
      if (!mounted) return;
      Navigator.of(context).pop();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.toString())),
      );
    }
  }

  List<String> _parseUsernames(String raw) {
    final parts = raw
        .split(RegExp(r'[\s,;]+'))
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .map((item) => item.startsWith('@') ? item.substring(1) : item)
        .toList();
    final seen = <String>{};
    final out = <String>[];
    for (final item in parts) {
      final lower = item.toLowerCase();
      if (seen.contains(lower)) continue;
      seen.add(lower);
      out.add(lower);
    }
    return out;
  }

  Future<void> _showGroupMembersSheet() async {
    if (!(widget.initialChat?.isGroup ?? false)) return;

    final membersAsync =
        ref.read(chatRepositoryProvider).getGroupMembers(widget.chatId);

    await showModalBottomSheet<void>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        final isGroupOwner = widget.initialChat?.isOwner ?? false;

        return SafeArea(
          child: Padding(
            padding: EdgeInsets.fromLTRB(
                12, 12, 12, MediaQuery.of(sheetContext).viewInsets.bottom + 12),
            child: GlassSurface(
              radius: 26,
              blur: 20,
              opacity: 0.6,
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Text(
                        'Group Members',
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
                  const SizedBox(height: 10),
                  FutureBuilder<List<dynamic>>(
                    future: membersAsync,
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return const Center(
                          child: Padding(
                            padding: EdgeInsets.all(20),
                            child: CircularProgressIndicator(),
                          ),
                        );
                      }

                      if (snapshot.hasError) {
                        return Center(
                          child: Padding(
                            padding: const EdgeInsets.all(20),
                            child: Text('Error: ${snapshot.error}'),
                          ),
                        );
                      }

                      final members = snapshot.data ?? [];

                      if (members.isEmpty) {
                        return const Center(
                          child: Padding(
                            padding: EdgeInsets.all(20),
                            child: Text('No members found'),
                          ),
                        );
                      }

                      return ConstrainedBox(
                        constraints: BoxConstraints(
                          maxHeight: MediaQuery.of(context).size.height * 0.5,
                        ),
                        child: ListView.builder(
                          shrinkWrap: true,
                          itemCount: members.length,
                          itemBuilder: (context, index) {
                            final member = members[index];
                            final displayName = member.displayName ?? 'Unknown';
                            final username = member.username ?? '';
                            final role = member.role ?? 'member';
                            final avatarUrl = member.avatarUrl ?? '';

                            return ListTile(
                              contentPadding: EdgeInsets.zero,
                              leading: CircleAvatar(
                                radius: 22,
                                backgroundImage: avatarUrl.isNotEmpty
                                    ? NetworkImage(avatarUrl)
                                    : null,
                                child: avatarUrl.isEmpty
                                    ? const Icon(Icons.person_rounded, size: 20)
                                    : null,
                              ),
                              title: Text(
                                displayName,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 15,
                                ),
                              ),
                              subtitle: Text(
                                '@$username • ${role.toUpperCase()}',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: AppTheme.textSecondary(context),
                                ),
                              ),
                              trailing: role == 'owner'
                                  ? const Icon(
                                      Icons.star_rounded,
                                      color: Colors.amber,
                                      size: 20,
                                    )
                                  : null,
                            );
                          },
                        ),
                      );
                    },
                  ),
                  if (isGroupOwner) ...[
                    const SizedBox(height: 12),
                    const Divider(),
                    const SizedBox(height: 8),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(12),
                          color: AppTheme.telegramBlue.withValues(alpha: 0.15),
                        ),
                        child: const Icon(
                          Icons.person_add_alt_rounded,
                          color: AppTheme.telegramBlue,
                        ),
                      ),
                      title: const Text(
                        'Add Member',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: AppTheme.telegramBlue,
                        ),
                      ),
                      onTap: () {
                        Navigator.of(sheetContext).pop();
                        _showAddGroupMembersSheet();
                      },
                    ),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _showAddGroupMembersSheet() async {
    if (!(widget.initialChat?.isGroup ?? false)) return;
    final controller = TextEditingController();
    var saving = false;

    await showModalBottomSheet<void>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        final bottomInset = MediaQuery.of(sheetContext).viewInsets.bottom;
        return StatefulBuilder(
          builder: (sheetContext, setModalState) {
            Future<void> onSubmit() async {
              if (saving) return;
              final usernames = _parseUsernames(controller.text);
              if (usernames.isEmpty) {
                ScaffoldMessenger.of(sheetContext).showSnackBar(
                  const SnackBar(
                    content: Text(
                      'Kamida 1 ta username kiriting. Masalan: @user1, @user2',
                    ),
                  ),
                );
                return;
              }
              setModalState(() => saving = true);
              try {
                await ref
                    .read(chatActionControllerProvider.notifier)
                    .addGroupMembers(
                      chatId: widget.chatId,
                      memberUsernames: usernames,
                    );
                ref.invalidate(chatListProvider);
                if (!sheetContext.mounted) return;
                Navigator.of(sheetContext).pop();
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('A\'zolar qo\'shildi.')),
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
                  radius: 24,
                  blur: 18,
                  opacity: 0.6,
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Text(
                            'Add members',
                            style: TextStyle(
                              fontWeight: FontWeight.w900,
                              fontSize: 19,
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
                      TextField(
                        controller: controller,
                        maxLines: 2,
                        decoration: const InputDecoration(
                          labelText: 'Usernames',
                          hintText: '@user1, @user2, @user3',
                        ),
                      ),
                      const SizedBox(height: 12),
                      FilledButton.icon(
                        onPressed: saving ? null : onSubmit,
                        icon: saving
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.person_add_alt_rounded),
                        label: Text(saving ? 'Adding...' : 'Add members'),
                        style: FilledButton.styleFrom(
                          minimumSize: const Size.fromHeight(46),
                          backgroundColor: AppTheme.telegramBlue,
                          foregroundColor: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );

    controller.dispose();
  }

  bool _isVerificationAdmin(AppUser user) {
    return user.usernameLower == 'verify' || user.usernameLower == 'asilbek';
  }

  Future<void> _applyVerificationDecision({
    required String messageId,
    required VerificationRequestPayload payload,
    required bool approve,
  }) async {
    if (_verificationActionLoading.contains(messageId)) return;
    setState(() => _verificationActionLoading.add(messageId));

    try {
      await ref
          .read(chatActionControllerProvider.notifier)
          .reviewVerificationRequest(
            requesterId: payload.requesterId,
            approve: approve,
          );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            approve
                ? '@${payload.username} verified qilindi.'
                : '@${payload.username} reject qilindi (1 hafta blok).',
          ),
        ),
      );
      ref.invalidate(userByIdProvider(payload.requesterId));
      ref.invalidate(chatListProvider);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.toString())),
      );
    } finally {
      if (mounted) {
        setState(() => _verificationActionLoading.remove(messageId));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final me = ref.watch(currentUserProvider);
    if (me == null) return const SizedBox.shrink();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final secondaryText = AppTheme.textSecondary(context);

    final isGroupChat = widget.initialChat?.isGroup == true;
    final peerAsync = (!widget.isSaved && !isGroupChat && widget.peerId != null)
        ? ref.watch(userByIdProvider(widget.peerId!))
        : const AsyncValue<AppUser?>.data(null);
    final messagesAsync = ref.watch(chatMessagesProvider(widget.chatId));

    final peer = peerAsync.valueOrNull;
    final isVerificationAdminUser = _isVerificationAdmin(me);
    final canWrite =
        widget.isSaved || isGroupChat || (peer?.canReceiveMessages ?? true);
    final isVerifiedPeer = !widget.isSaved &&
        !isGroupChat &&
        (peer?.isVerified == true || peer?.usernameLower == 'asilbek');
    final groupMemberCount = widget.initialChat?.memberCount ??
        widget.initialChat?.participantIds.length ??
        0;
    final name = widget.isSaved
        ? 'Saved Messages'
        : isGroupChat
            ? ((widget.initialChat?.title?.trim().isNotEmpty ?? false)
                ? widget.initialChat!.title!.trim()
                : 'Group')
            : (peer?.displayName ?? 'Loading...');

    final status = widget.isSaved
        ? 'private storage'
        : isGroupChat
            ? '@${widget.initialChat?.groupUsername ?? 'group'} • $groupMemberCount members'
            : peer == null
                ? 'syncing...'
                : peer.isOnline
                    ? 'online'
                    : 'last seen ${DateFormat('MMM d, HH:mm').format(peer.lastSeen)}';
    final shownStatus = canWrite ? status : 'messages locked';

    return Scaffold(
      body: GlassBackground(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
              child: GlassSurface(
                radius: 22,
                opacity: 0.5,
                blur: 28,
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
                child: Row(
                  children: [
                    IconButton(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.arrow_back_ios_new_rounded),
                    ),
                    Expanded(
                      child: GestureDetector(
                        onTap: () {
                          if (!widget.isSaved &&
                              !isGroupChat &&
                              widget.peerId != null) {
                            Navigator.of(context).push(
                              FadePageRoute(
                                page: ProfileScreen(userId: widget.peerId!),
                              ),
                            );
                          } else if (isGroupChat) {
                            _showGroupMembersSheet();
                          }
                        },
                        child: Row(
                          children: [
                            CircleAvatar(
                              radius: 20,
                              backgroundImage: !isGroupChat &&
                                      peer?.avatarUrl.isNotEmpty == true
                                  ? NetworkImage(peer!.avatarUrl)
                                  : null,
                              onBackgroundImageError: !isGroupChat &&
                                      peer?.avatarUrl.isNotEmpty == true
                                  ? (_, __) {}
                                  : null,
                              child: !isGroupChat &&
                                      peer?.avatarUrl.isNotEmpty == true
                                  ? null
                                  : Icon(
                                      isGroupChat
                                          ? Icons.groups_rounded
                                          : Icons.person_rounded,
                                      size: 18,
                                    ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Row(
                                    mainAxisSize: MainAxisSize.max,
                                    children: [
                                      Expanded(
                                        child: Text.rich(
                                          TextSpan(
                                            style: const TextStyle(
                                              fontWeight: FontWeight.w800,
                                              fontSize: 16,
                                            ),
                                            children: [
                                              TextSpan(text: name),
                                              if (isVerifiedPeer)
                                                WidgetSpan(
                                                  alignment:
                                                      PlaceholderAlignment
                                                          .middle,
                                                  child: Padding(
                                                    padding:
                                                        const EdgeInsets.only(
                                                            left: 4),
                                                    child: VerificationBadge(
                                                      usernameLower:
                                                          peer?.usernameLower ??
                                                              '',
                                                      isVerified:
                                                          peer?.isVerified ??
                                                              false,
                                                      size: 16,
                                                    ),
                                                  ),
                                                ),
                                            ],
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                      if (!canWrite) ...[
                                        const SizedBox(width: 4),
                                        const Icon(
                                          Icons.lock_rounded,
                                          size: 15,
                                          color: Colors.orangeAccent,
                                        ),
                                      ],
                                    ],
                                  ),
                                  Text(
                                    shownStatus,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: secondaryText,
                                      fontWeight: FontWeight.w600,
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: () {},
                      icon: const Icon(Icons.call_rounded),
                    ),
                    IconButton(
                      onPressed: _showChatMenu,
                      icon: const Icon(Icons.more_vert_rounded),
                    ),
                  ],
                ),
              ),
            ),
            Expanded(
              child: messagesAsync.when(
                data: (messages) {
                  _syncScrollWithMessages(messages.length);

                  if (messages.isEmpty) {
                    return Center(
                      child: Text(
                        widget.isSaved
                            ? 'Save your first note'
                            : 'Send first message to start chat',
                        style: TextStyle(
                          color: secondaryText,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    );
                  }

                  return ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
                    itemCount: messages.length,
                    itemBuilder: (context, index) {
                      final message = messages[index];
                      final isMe = message.senderId == me.id;
                      final verificationRequest = message.type == 'text'
                          ? VerificationRequestPayload.tryParse(message.text)
                          : null;
                      final verificationDecision = message.type == 'text'
                          ? VerificationDecisionPayload.tryParse(message.text)
                          : null;
                      final stickerPayload = message.isSticker
                          ? StickerPayload.tryParse(message.text)
                          : null;
                      final mediaPayload = message.isMedia
                          ? MediaPayload.tryParse(message.text)
                          : null;
                      final canDelete = isMe || widget.isSaved;

                      return GestureDetector(
                        onLongPress: canDelete
                            ? () => _showMessageActions(
                                  messageId: message.id,
                                  canDelete: canDelete,
                                )
                            : null,
                        onSecondaryTapDown: canDelete
                            ? (_) => _showMessageActions(
                                  messageId: message.id,
                                  canDelete: canDelete,
                                )
                            : null,
                        child: verificationRequest != null
                            ? _VerificationRequestBubble(
                                payload: verificationRequest,
                                isMe: isMe,
                                time: DateFormat.Hm().format(message.createdAt),
                                isRead: message.isRead,
                                canReview: isVerificationAdminUser && !isMe,
                                isActionLoading: _verificationActionLoading
                                    .contains(message.id),
                                onApprove: () => _applyVerificationDecision(
                                  messageId: message.id,
                                  payload: verificationRequest,
                                  approve: true,
                                ),
                                onReject: () => _applyVerificationDecision(
                                  messageId: message.id,
                                  payload: verificationRequest,
                                  approve: false,
                                ),
                              )
                            : MessageBubble(
                                text: verificationDecision?.toReadableText() ??
                                    message.text,
                                isMe: isMe,
                                type: message.type,
                                stickerAssetPath:
                                    stickerPayload?.stickerAssetPath,
                                stickerCaption: stickerPayload?.caption,
                                mediaPayload: mediaPayload,
                                time: DateFormat.Hm().format(message.createdAt),
                                isRead: message.isRead,
                                showSenderInfo: isGroupChat && !isMe,
                              ),
                      );
                    },
                  );
                },
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (error, _) => Center(child: Text(error.toString())),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 2, 12, 14),
              child: GlassSurface(
                radius: 34,
                blur: 36,
                opacity: isDark ? 0.44 : 0.66,
                borderColor:
                    Colors.white.withValues(alpha: isDark ? 0.32 : 0.7),
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                child: Row(
                  children: [
                    SizedBox(
                      width: 40,
                      height: 40,
                      child: IconButton(
                        onPressed: canWrite ? _openStickerPicker : null,
                        padding: EdgeInsets.zero,
                        icon: Icon(
                          Icons.emoji_emotions_outlined,
                          color: canWrite
                              ? secondaryText.withValues(alpha: 0.92)
                              : secondaryText.withValues(alpha: 0.45),
                        ),
                      ),
                    ),
                    Expanded(
                      child: TextField(
                        controller: _textController,
                        enabled: canWrite,
                        textInputAction: TextInputAction.send,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w500,
                          color: AppTheme.textPrimary(context),
                        ),
                        onChanged: (value) {
                          if (_pendingStickerAssetPath != null &&
                              !value.contains(_inlineStickerMarker)) {
                            setState(() => _pendingStickerAssetPath = null);
                          }
                        },
                        onSubmitted: (_) => canWrite ? _send() : null,
                        decoration: InputDecoration(
                          hintText: canWrite
                              ? 'Message'
                              : 'User locked incoming messages',
                          border: InputBorder.none,
                          isCollapsed: true,
                          hintStyle: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w500,
                            color: secondaryText.withValues(alpha: 0.9),
                          ),
                        ),
                      ),
                    ),
                    SizedBox(
                      width: 40,
                      height: 40,
                      child: IconButton(
                        onPressed: () => _showAttachmentSheet(canWrite),
                        padding: EdgeInsets.zero,
                        icon: Icon(
                          Icons.attach_file_rounded,
                          color: canWrite
                              ? secondaryText.withValues(alpha: 0.92)
                              : secondaryText.withValues(alpha: 0.45),
                        ),
                      ),
                    ),
                    if (_isRecordingVoice)
                      Container(
                        margin: const EdgeInsets.only(right: 4),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.redAccent.withValues(alpha: 0.18),
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(
                            color: Colors.redAccent.withValues(alpha: 0.5),
                          ),
                        ),
                        child: Text(
                          'REC ${_recordingSeconds.toString().padLeft(2, '0')}',
                          style: const TextStyle(
                            color: Colors.redAccent,
                            fontWeight: FontWeight.w800,
                            fontSize: 11.5,
                          ),
                        ),
                      ),
                    GestureDetector(
                      onLongPressStart: (_) => _startVoiceRecording(canWrite),
                      onLongPressEnd: (_) => _stopVoiceRecording(
                        sendAfterStop: canWrite,
                      ),
                      onLongPressCancel: () => _stopVoiceRecording(
                        sendAfterStop: false,
                      ),
                      child: SizedBox(
                        width: 40,
                        height: 40,
                        child: IconButton(
                          onPressed: canWrite
                              ? () {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text(
                                        'Voice uchun mic tugmasini bosib ushlab turing',
                                      ),
                                      duration: Duration(milliseconds: 900),
                                    ),
                                  );
                                }
                              : null,
                          padding: EdgeInsets.zero,
                          icon: Icon(
                            _isRecordingVoice
                                ? Icons.mic_rounded
                                : Icons.mic_none_rounded,
                            color: _isRecordingVoice
                                ? Colors.redAccent
                                : canWrite
                                    ? secondaryText.withValues(alpha: 0.92)
                                    : secondaryText.withValues(alpha: 0.45),
                          ),
                        ),
                      ),
                    ),
                    Container(
                      width: 42,
                      height: 42,
                      margin: const EdgeInsets.only(left: 3, right: 2),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.42),
                        ),
                        gradient: const LinearGradient(
                          colors: [AppTheme.telegramBlue, AppTheme.cyan],
                        ),
                      ),
                      child: IconButton(
                        onPressed: canWrite ? _send : null,
                        padding: EdgeInsets.zero,
                        icon:
                            const Icon(Icons.send_rounded, color: Colors.white),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _VerificationRequestBubble extends StatelessWidget {
  const _VerificationRequestBubble({
    required this.payload,
    required this.isMe,
    required this.time,
    required this.isRead,
    required this.canReview,
    required this.isActionLoading,
    required this.onApprove,
    required this.onReject,
  });

  final VerificationRequestPayload payload;
  final bool isMe;
  final String time;
  final bool isRead;
  final bool canReview;
  final bool isActionLoading;
  final VoidCallback onApprove;
  final VoidCallback onReject;

  Widget _buildMeta({
    required Color color,
    required bool showChecks,
  }) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          time,
          style: TextStyle(
            color: color,
            fontSize: 11,
            fontWeight: FontWeight.w600,
          ),
        ),
        if (showChecks) ...[
          const SizedBox(width: 2),
          Icon(
            isRead ? Icons.done_all_rounded : Icons.done_rounded,
            size: 14,
            color: color,
          ),
        ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final peerTextColor = isDark ? Colors.white : AppTheme.darkText;
    final peerMetaColor =
        (isDark ? Colors.white : AppTheme.darkText).withValues(alpha: 0.62);

    final bubbleDecoration = BoxDecoration(
      gradient: isMe
          ? const LinearGradient(
              colors: [AppTheme.telegramBlue, AppTheme.cyan],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            )
          : null,
      color: isMe
          ? null
          : (isDark
              ? const Color(0xFF111923).withValues(alpha: 0.9)
              : Colors.white.withValues(alpha: 0.55)),
      borderRadius: BorderRadius.only(
        topLeft: const Radius.circular(20),
        topRight: const Radius.circular(20),
        bottomLeft: isMe ? const Radius.circular(20) : const Radius.circular(6),
        bottomRight:
            isMe ? const Radius.circular(6) : const Radius.circular(20),
      ),
      border: Border.all(
        color: isMe
            ? Colors.white.withValues(alpha: 0.28)
            : Colors.white.withValues(alpha: isDark ? 0.16 : 0.62),
      ),
    );

    final textColor = isMe ? Colors.white : peerTextColor;
    final metaColor =
        isMe ? Colors.white.withValues(alpha: 0.78) : peerMetaColor;
    final requestedAtText = payload.requestedAt == null
        ? null
        : DateFormat('MMM d, HH:mm').format(payload.requestedAt!);

    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints:
            BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.82),
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: bubbleDecoration,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Verification request',
                    style: TextStyle(
                      color: textColor,
                      fontWeight: FontWeight.w800,
                      fontSize: 15.5,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${payload.displayName} (@${payload.username})',
                    style: TextStyle(
                      color: textColor,
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                    ),
                  ),
                  if ((payload.phoneNumber ?? '').trim().isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        'Phone: ${payload.phoneNumber}',
                        style: TextStyle(
                          color: textColor.withValues(alpha: 0.95),
                          fontWeight: FontWeight.w600,
                          fontSize: 12.5,
                        ),
                      ),
                    ),
                  if (payload.bio.trim().isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        payload.bio.trim(),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: textColor.withValues(alpha: 0.95),
                          fontWeight: FontWeight.w500,
                          fontSize: 12.5,
                        ),
                      ),
                    ),
                  if (requestedAtText != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        requestedAtText,
                        style: TextStyle(
                          color: textColor.withValues(alpha: 0.8),
                          fontWeight: FontWeight.w600,
                          fontSize: 11.5,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            if (canReview) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: isActionLoading ? null : onReject,
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size.fromHeight(36),
                        side: BorderSide(
                          color: isMe
                              ? Colors.white.withValues(alpha: 0.5)
                              : Colors.redAccent.withValues(alpha: 0.7),
                        ),
                        foregroundColor: isMe ? Colors.white : Colors.redAccent,
                      ),
                      child: const Text(
                        'Rejection',
                        style: TextStyle(fontWeight: FontWeight.w800),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: FilledButton(
                      onPressed: isActionLoading ? null : onApprove,
                      style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(36),
                        backgroundColor: AppTheme.telegramBlue,
                        foregroundColor: Colors.white,
                      ),
                      child: isActionLoading
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Text(
                              'Verify',
                              style: TextStyle(fontWeight: FontWeight.w800),
                            ),
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 4),
            _buildMeta(
              color: metaColor,
              showChecks: isMe,
            ),
          ],
        ),
      ),
    );
  }
}

class _VoiceCodec {
  const _VoiceCodec({
    required this.encoder,
    required this.extension,
    required this.mimeType,
  });

  final AudioEncoder encoder;
  final String extension;
  final String mimeType;
}

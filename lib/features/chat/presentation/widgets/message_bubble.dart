import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';
import 'package:video_player/video_player.dart';

import '../../../../core/theme/app_theme.dart';
import '../models/media_payload.dart';

class MessageBubble extends StatelessWidget {
  const MessageBubble({
    super.key,
    required this.text,
    required this.time,
    required this.isMe,
    required this.type,
    this.stickerAssetPath,
    this.stickerCaption,
    this.mediaPayload,
    this.showMeta = true,
    this.isRead = false,
    this.senderName,
    this.senderAvatarUrl,
    this.showSenderInfo = false,
  });

  final String text;
  final String time;
  final bool isMe;
  final String type;
  final String? stickerAssetPath;
  final String? stickerCaption;
  final MediaPayload? mediaPayload;
  final bool showMeta;
  final bool isRead;
  final String? senderName;
  final String? senderAvatarUrl;
  final bool showSenderInfo;

  static const _inlineStickerMarker = '🤝';

  bool get _isSticker => type == 'sticker';
  bool get _isImage => type == 'image';
  bool get _isVideo => type == 'video';
  bool get _isVoice => type == 'voice';
  bool get _isGroupEvent => type == 'group_event';

  _InlineStickerCaption _parseInlineCaption(String caption) {
    final trimmed = caption.trim();
    final markerIndex = trimmed.indexOf(_inlineStickerMarker);

    if (markerIndex == -1) {
      final words = trimmed
          .split(RegExp(r'\s+'))
          .where((word) => word.isNotEmpty)
          .toList();
      if (words.length <= 1) {
        return _InlineStickerCaption(before: trimmed, after: '');
      }
      return _InlineStickerCaption(
        before: words.first,
        after: words.sublist(1).join(' '),
      );
    }

    return _InlineStickerCaption(
      before: trimmed.substring(0, markerIndex).trimRight(),
      after: trimmed
          .substring(markerIndex + _inlineStickerMarker.length)
          .trimLeft(),
    );
  }

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

  void _openImageViewer(BuildContext context, String imageUrl) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => _ImageViewerPage(imageUrl: imageUrl),
      ),
    );
  }

  void _openVideoViewer(BuildContext context, MediaPayload payload) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => _VideoViewerPage(
          videoUrl: payload.url,
          title: payload.fileName,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final peerTextColor = isDark ? Colors.white : AppTheme.darkText;
    final peerMetaColor =
        (isDark ? Colors.white : AppTheme.darkText).withValues(alpha: 0.62);

    if (_isGroupEvent) {
      try {
        final data = jsonDecode(text) as Map<String, dynamic>;
        final kind = data['kind'];
        if (kind == 'group_event') {
          final action = data['action'];
          final actorName = data['actorDisplayName'] ?? data['actorUsername'];
          final targetName =
              data['targetDisplayName'] ?? data['targetUsername'];

          String? messageText;
          if (action == 'joined') {
            messageText = '$targetName joined the group';
          } else if (action == 'added') {
            messageText = '$actorName added $targetName';
          } else if (action == 'removed') {
            messageText = '$actorName removed $targetName';
          }

          if (messageText != null) {
            return Center(
              child: Container(
                margin: const EdgeInsets.symmetric(vertical: 8),
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Text(
                  messageText,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            );
          }
        }
      } catch (_) {}
      return const SizedBox.shrink();
    }

    final hasMedia = mediaPayload != null && (_isImage || _isVideo || _isVoice);

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

    // Show sender info for group chats (when not own message)
    if (showSenderInfo && !isMe && senderName != null) {
      return Column(
        crossAxisAlignment:
            isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 2),
            child: Row(
              children: [
                if (senderAvatarUrl != null && senderAvatarUrl!.isNotEmpty)
                  CircleAvatar(
                    radius: 12,
                    backgroundImage: NetworkImage(senderAvatarUrl!),
                  )
                else
                  const CircleAvatar(
                    radius: 12,
                    child: Icon(Icons.person_rounded, size: 14),
                  ),
                const SizedBox(width: 6),
                Text(
                  senderName!,
                  style: TextStyle(
                    color: AppTheme.telegramBlue,
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
          _buildBubble(context, isDark, peerTextColor, peerMetaColor, hasMedia,
              bubbleDecoration),
        ],
      );
    }

    return _buildBubble(context, isDark, peerTextColor, peerMetaColor, hasMedia,
        bubbleDecoration);
  }

  Widget _buildBubble(BuildContext context, bool isDark, Color peerTextColor,
      Color peerMetaColor, bool hasMedia, BoxDecoration bubbleDecoration) {
    if (_isSticker && stickerAssetPath != null) {
      return _buildStickerBubble(
          context, isDark, peerTextColor, peerMetaColor, bubbleDecoration);
    }

    if (hasMedia) {
      return _buildMediaBubble(
          context, isDark, peerTextColor, peerMetaColor, bubbleDecoration);
    }

    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints:
            BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.76),
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: bubbleDecoration,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              text,
              style: TextStyle(
                color: isMe ? Colors.white : peerTextColor,
                fontWeight: FontWeight.w500,
                fontSize: 15,
              ),
            ),
            if (showMeta) const SizedBox(height: 4),
            if (showMeta)
              _buildMeta(
                color:
                    isMe ? Colors.white.withValues(alpha: 0.78) : peerMetaColor,
                showChecks: isMe,
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildStickerBubble(
      BuildContext context,
      bool isDark,
      Color peerTextColor,
      Color peerMetaColor,
      BoxDecoration bubbleDecoration) {
    final hasCaption =
        stickerCaption != null && stickerCaption!.trim().isNotEmpty;
    final stickerOnlySize = 116.0;
    final selfMetaColor = Colors.white.withValues(alpha: 0.78);

    if (hasCaption) {
      final inlineCaption = _parseInlineCaption(stickerCaption!);
      final textColor = isMe ? Colors.white : peerTextColor;

      return Align(
        alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
        child: Container(
          constraints: BoxConstraints(
              maxWidth: MediaQuery.of(context).size.width * 0.82),
          margin: const EdgeInsets.symmetric(vertical: 4),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: bubbleDecoration,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              ConstrainedBox(
                constraints: BoxConstraints(
                    maxWidth: MediaQuery.of(context).size.width * 0.5),
                child: Text(
                  stickerCaption!,
                  style: TextStyle(
                    color: textColor,
                    fontWeight: FontWeight.w500,
                    fontSize: 15,
                  ),
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (showMeta) const SizedBox(width: 10),
              if (showMeta)
                _buildMeta(
                  color: isMe ? selfMetaColor : peerMetaColor,
                  showChecks: isMe,
                ),
            ],
          ),
        ),
      );
    }

    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints:
            BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.82),
        margin: const EdgeInsets.symmetric(vertical: 4),
        child: Column(
          crossAxisAlignment:
              isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: stickerOnlySize,
              height: stickerOnlySize,
              child: Lottie.asset(
                stickerAssetPath!,
                repeat: true,
                fit: BoxFit.contain,
              ),
            ),
            if (showMeta) const SizedBox(height: 4),
            if (showMeta)
              _buildMeta(
                color: isMe ? selfMetaColor : peerMetaColor,
                showChecks: isMe,
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildMediaBubble(
      BuildContext context,
      bool isDark,
      Color peerTextColor,
      Color peerMetaColor,
      BoxDecoration bubbleDecoration) {
    final payload = mediaPayload!;

    if (_isImage) {
      return Align(
        alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
        child: Container(
          constraints: BoxConstraints(
              maxWidth: MediaQuery.of(context).size.width * 0.76),
          margin: const EdgeInsets.symmetric(vertical: 4),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
          decoration: bubbleDecoration,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              GestureDetector(
                onTap: () => _openImageViewer(context, payload.url),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: Image.network(
                    payload.url,
                    fit: BoxFit.cover,
                    width: 220,
                    height: 180,
                    loadingBuilder: (context, child, loadingProgress) {
                      if (loadingProgress == null) return child;
                      return SizedBox(
                        width: 220,
                        height: 180,
                        child: Center(
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: isMe ? Colors.white : AppTheme.telegramBlue,
                          ),
                        ),
                      );
                    },
                    errorBuilder: (_, __, ___) => SizedBox(
                      width: 220,
                      height: 180,
                      child: Center(
                        child: Icon(
                          Icons.broken_image_rounded,
                          size: 40,
                          color: isMe ? Colors.white : peerTextColor,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              if (showMeta) const SizedBox(height: 4),
              if (showMeta)
                _buildMeta(
                  color: isMe
                      ? Colors.white.withValues(alpha: 0.78)
                      : peerMetaColor,
                  showChecks: isMe,
                ),
            ],
          ),
        ),
      );
    }

    if (_isVideo) {
      return Align(
        alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
        child: Container(
          constraints: BoxConstraints(
              maxWidth: MediaQuery.of(context).size.width * 0.76),
          margin: const EdgeInsets.symmetric(vertical: 4),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
          decoration: bubbleDecoration,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              GestureDetector(
                onTap: () => _openVideoViewer(context, payload),
                child: Container(
                  width: 220,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(14),
                    color: Colors.black.withValues(alpha: 0.2),
                    border:
                        Border.all(color: Colors.white.withValues(alpha: 0.2)),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.white.withValues(alpha: 0.2),
                        ),
                        child: const Icon(Icons.play_arrow_rounded,
                            color: Colors.white),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Video message',
                              style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w700),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              payload.fileName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  color: Color(0xDDFFFFFF),
                                  fontWeight: FontWeight.w500,
                                  fontSize: 12),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              if (showMeta) const SizedBox(height: 4),
              if (showMeta)
                _buildMeta(
                  color: isMe
                      ? Colors.white.withValues(alpha: 0.78)
                      : peerMetaColor,
                  showChecks: isMe,
                ),
            ],
          ),
        ),
      );
    }

    if (_isVoice) {
      return Align(
        alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
        child: Container(
          constraints: BoxConstraints(
              maxWidth: MediaQuery.of(context).size.width * 0.82),
          margin: const EdgeInsets.symmetric(vertical: 4),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
          decoration: bubbleDecoration,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              _VoiceMessageTile(
                key: ValueKey(payload.url),
                payload: payload,
                isMe: isMe,
                textColor: isMe ? Colors.white : peerTextColor,
              ),
              if (showMeta) const SizedBox(height: 4),
              if (showMeta)
                _buildMeta(
                  color: isMe
                      ? Colors.white.withValues(alpha: 0.78)
                      : peerMetaColor,
                  showChecks: isMe,
                ),
            ],
          ),
        ),
      );
    }

    return const SizedBox.shrink();
  }
}

class _VoiceMessageTile extends StatefulWidget {
  const _VoiceMessageTile({
    super.key,
    required this.payload,
    required this.isMe,
    required this.textColor,
  });

  final MediaPayload payload;
  final bool isMe;
  final Color textColor;

  @override
  State<_VoiceMessageTile> createState() => _VoiceMessageTileState();
}

class _VoiceMessageTileState extends State<_VoiceMessageTile> {
  final AudioPlayer _player = AudioPlayer();
  StreamSubscription<Duration>? _positionSub;
  StreamSubscription<Duration>? _durationSub;
  StreamSubscription<PlayerState>? _playerStateSub;
  StreamSubscription<void>? _completeSub;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  bool _isPlaying = false;
  bool _isLoading = true;
  bool _hasError = false;
  late final List<double> _waveHeights;

  @override
  void initState() {
    super.initState();
    _waveHeights = _generateWaveHeights(widget.payload.url);
    _bindPlayer();
  }

  void _bindPlayer() {
    _positionSub = _player.onPositionChanged.listen((value) {
      if (!mounted) return;
      setState(() => _position = value);
    });
    _durationSub = _player.onDurationChanged.listen((value) {
      if (!mounted) return;
      setState(() => _duration = value);
    });
    _playerStateSub = _player.onPlayerStateChanged.listen((state) {
      if (!mounted) return;
      setState(() => _isPlaying = state == PlayerState.playing);
    });
    _completeSub = _player.onPlayerComplete.listen((_) {
      if (!mounted) return;
      setState(() {
        _isPlaying = false;
        _position = _duration;
      });
    });
    _preparePlayer();
  }

  Future<void> _preparePlayer() async {
    try {
      await _player.setSourceUrl(widget.payload.url);
      final initialDuration = await _player.getDuration();
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        if (initialDuration != null && initialDuration > Duration.zero) {
          _duration = initialDuration;
        }
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _hasError = true;
      });
    }
  }

  Future<void> _togglePlayback() async {
    if (_hasError) return;
    try {
      if (_isPlaying) {
        await _player.pause();
        return;
      }
      if (_duration > Duration.zero &&
          _position >= _duration - const Duration(milliseconds: 250)) {
        await _player.seek(Duration.zero);
      }
      await _player.resume();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _hasError = true;
        _isPlaying = false;
      });
    }
  }

  @override
  void dispose() {
    _positionSub?.cancel();
    _durationSub?.cancel();
    _playerStateSub?.cancel();
    _completeSub?.cancel();
    _player.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_hasError) {
      return Row(
        children: [
          Icon(Icons.error_outline_rounded,
              color: widget.isMe ? Colors.white : Colors.redAccent, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text('Voice ochilmadi',
                style: TextStyle(
                    color: widget.textColor, fontWeight: FontWeight.w600)),
          ),
        ],
      );
    }

    final totalDuration = _duration > Duration.zero ? _duration : _position;
    final durationMs = totalDuration.inMilliseconds;
    final positionMs = _position.inMilliseconds;
    final progress = durationMs <= 0
        ? 0.0
        : (positionMs / durationMs).clamp(0.0, 1.0).toDouble();

    final buttonBg = widget.isMe
        ? Colors.white.withValues(alpha: 0.24)
        : AppTheme.telegramBlue.withValues(alpha: 0.14);
    final buttonIconColor = widget.isMe ? Colors.white : AppTheme.telegramBlue;

    final infoText = _isLoading
        ? 'Loading voice...'
        : '${_formatDuration(totalDuration)}, ${_formatBytes(widget.payload.sizeBytes)}';

    return Row(
      children: [
        GestureDetector(
          onTap: _togglePlayback,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            width: 42,
            height: 42,
            decoration: BoxDecoration(shape: BoxShape.circle, color: buttonBg),
            child: Icon(
                _isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                color: buttonIconColor,
                size: 24),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                height: 22,
                child: CustomPaint(
                  painter: _WaveformPainter(
                      heights: _waveHeights,
                      progress: progress,
                      baseColor: widget.textColor.withValues(alpha: 0.32),
                      activeColor: AppTheme.telegramBlue),
                  size: const Size(double.infinity, 22),
                ),
              ),
              const SizedBox(height: 3),
              Text(infoText,
                  style: TextStyle(
                      color: widget.textColor.withValues(alpha: 0.9),
                      fontWeight: FontWeight.w600,
                      fontSize: 12)),
            ],
          ),
        ),
      ],
    );
  }
}

class _WaveformPainter extends CustomPainter {
  _WaveformPainter(
      {required this.heights,
      required this.progress,
      required this.baseColor,
      required this.activeColor});
  final List<double> heights;
  final double progress;
  final Color baseColor;
  final Color activeColor;

  @override
  void paint(Canvas canvas, Size size) {
    if (heights.isEmpty || size.width <= 0 || size.height <= 0) return;
    final barWidth = 2.4;
    var gap = (size.width - heights.length * barWidth) / (heights.length - 1);
    if (gap.isNaN || gap.isInfinite || gap < 1) gap = 1;
    final basePaint = Paint()..color = baseColor;
    final activePaint = Paint()..color = activeColor;
    final playedX = size.width * progress.clamp(0.0, 1.0);
    var x = 0.0;
    for (final h in heights) {
      if (x > size.width) break;
      final barHeight = h.clamp(6.0, size.height).toDouble();
      final top = (size.height - barHeight) / 2;
      final rect = RRect.fromRectAndRadius(
          Rect.fromLTWH(x, top, barWidth, barHeight), const Radius.circular(2));
      canvas.drawRRect(rect, basePaint);
      if (x + (barWidth / 2) <= playedX) canvas.drawRRect(rect, activePaint);
      x += barWidth + gap;
    }
  }

  @override
  bool shouldRepaint(covariant _WaveformPainter oldDelegate) =>
      oldDelegate.progress != progress ||
      oldDelegate.baseColor != baseColor ||
      oldDelegate.activeColor != activeColor ||
      oldDelegate.heights != heights;
}

class _VideoViewerPage extends StatefulWidget {
  const _VideoViewerPage({required this.videoUrl, required this.title});
  final String videoUrl;
  final String title;
  @override
  State<_VideoViewerPage> createState() => _VideoViewerPageState();
}

class _VideoViewerPageState extends State<_VideoViewerPage> {
  late final VideoPlayerController _controller;
  bool _isReady = false;
  String? _errorText;

  @override
  void initState() {
    super.initState();
    _controller = VideoPlayerController.networkUrl(Uri.parse(widget.videoUrl))
      ..setLooping(false);
    _initializeVideo();
  }

  Future<void> _initializeVideo() async {
    try {
      await _controller.initialize();
      if (!mounted) return;
      setState(() => _isReady = true);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isReady = false;
        _errorText = 'Video format browser tomonidan qo\'llab-quvvatlanmadi.';
      });
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _togglePlay() {
    if (!_isReady) return;
    if (_controller.value.isPlaying) {
      _controller.pause();
    } else {
      _controller.play();
    }
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
          backgroundColor: Colors.black,
          foregroundColor: Colors.white,
          title:
              Text(widget.title, maxLines: 1, overflow: TextOverflow.ellipsis)),
      body: _isReady
          ? AnimatedBuilder(
              animation: _controller,
              builder: (context, _) {
                final value = _controller.value;
                return Column(
                  children: [
                    Expanded(
                      child: Center(
                        child: AspectRatio(
                          aspectRatio: value.aspectRatio == 0
                              ? 9 / 16
                              : value.aspectRatio,
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              VideoPlayer(_controller),
                              GestureDetector(
                                onTap: _togglePlay,
                                child: AnimatedOpacity(
                                  opacity: value.isPlaying ? 0.0 : 1.0,
                                  duration: const Duration(milliseconds: 160),
                                  child: Center(
                                    child: Container(
                                      width: 66,
                                      height: 66,
                                      decoration: BoxDecoration(
                                          shape: BoxShape.circle,
                                          color: Colors.black
                                              .withValues(alpha: 0.45)),
                                      child: const Icon(
                                          Icons.play_arrow_rounded,
                                          color: Colors.white,
                                          size: 42),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    Container(
                      color: Colors.black.withValues(alpha: 0.72),
                      padding: const EdgeInsets.fromLTRB(8, 6, 8, 10),
                      child: Row(
                        children: [
                          IconButton(
                              onPressed: _togglePlay,
                              icon: Icon(
                                  value.isPlaying
                                      ? Icons.pause_rounded
                                      : Icons.play_arrow_rounded,
                                  color: Colors.white)),
                          Expanded(
                              child: VideoProgressIndicator(_controller,
                                  allowScrubbing: true,
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 10),
                                  colors: VideoProgressColors(
                                      playedColor: AppTheme.telegramBlue,
                                      bufferedColor:
                                          Colors.white.withValues(alpha: 0.45),
                                      backgroundColor: Colors.white
                                          .withValues(alpha: 0.2)))),
                          const SizedBox(width: 8),
                          Text(
                              '${_formatDuration(value.position)} / ${_formatDuration(value.duration)}',
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 12)),
                        ],
                      ),
                    ),
                  ],
                );
              },
            )
          : _errorText != null
              ? Center(
                  child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Text(_errorText!,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w600))))
              : const Center(
                  child: CircularProgressIndicator(color: Colors.white)),
    );
  }
}

class _ImageViewerPage extends StatelessWidget {
  const _ImageViewerPage({required this.imageUrl});
  final String imageUrl;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar:
          AppBar(backgroundColor: Colors.black, foregroundColor: Colors.white),
      body: InteractiveViewer(
        minScale: 1,
        maxScale: 4,
        child: Center(
          child: Image.network(
            imageUrl,
            fit: BoxFit.contain,
            loadingBuilder: (context, child, loadingProgress) {
              if (loadingProgress == null) return child;
              return const Center(
                  child: CircularProgressIndicator(color: Colors.white));
            },
            errorBuilder: (_, __, ___) => const Center(
                child: Icon(Icons.broken_image_rounded,
                    color: Colors.white, size: 56)),
          ),
        ),
      ),
    );
  }
}

class _InlineStickerCaption {
  const _InlineStickerCaption({required this.before, required this.after});
  final String before;
  final String after;
}

List<double> _generateWaveHeights(String seed) {
  final random = math.Random(seed.hashCode ^ 0x9E3779B9);
  return List<double>.generate(44, (_) => 7 + random.nextDouble() * 12);
}

String _formatDuration(Duration duration) {
  if (duration.inMilliseconds <= 0) return '00:00';
  final totalSeconds = duration.inSeconds;
  final hours = totalSeconds ~/ 3600;
  final minutes = (totalSeconds % 3600) ~/ 60;
  final seconds = totalSeconds % 60;
  if (hours > 0)
    return '${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
}

String _formatBytes(int bytes) {
  if (bytes <= 0) return '0 KB';
  final mb = bytes / (1024 * 1024);
  if (mb >= 1) return '${mb.toStringAsFixed(1)} MB';
  final kb = bytes / 1024;
  return '${kb.toStringAsFixed(1)} KB';
}

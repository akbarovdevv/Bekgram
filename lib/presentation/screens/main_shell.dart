import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import '../../features/auth/presentation/controllers/auth_controller.dart';
import '../../features/chat/presentation/controllers/chat_controller.dart';
import '../../features/chat/presentation/screens/home_screen.dart';
import '../../features/chat/presentation/screens/search_screen.dart';
import '../../features/profile/presentation/screens/profile_screen.dart';
import '../../features/settings/presentation/screens/settings_screen.dart';
import '../../shared/providers/network_providers.dart';

class MainShell extends ConsumerStatefulWidget {
  const MainShell({super.key});

  @override
  ConsumerState<MainShell> createState() => _MainShellState();
}

class _MainShellState extends ConsumerState<MainShell>
    with WidgetsBindingObserver {
  int _index = 0;
  StreamSubscription<Map<String, dynamic>>? _incomingMessageSub;
  Timer? _incomingSnackDebounce;
  int _incomingBurstCount = 0;
  int? _pressedTabIndex;
  final Map<int, int> _tabPulseTicks = <int, int>{};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      final user = ref.read(currentUserProvider);
      if (user != null) {
        ref
            .read(authControllerProvider.notifier)
            .setPresence(userId: user.id, isOnline: true);
      }
    });

    _incomingMessageSub =
        ref.read(socketServiceProvider).messageStream.listen((payload) {
      if (!mounted) return;

      final me = ref.read(currentUserProvider);
      if (me == null) return;

      final senderId = payload['senderId']?.toString();
      if (senderId == null || senderId == me.id) return;

      final isCurrentRoute = ModalRoute.of(context)?.isCurrent ?? true;
      if (!isCurrentRoute) return;

      _incomingBurstCount += 1;
      _incomingSnackDebounce?.cancel();
      _incomingSnackDebounce = Timer(const Duration(milliseconds: 240), () {
        if (!mounted) return;

        final totalUnread = ref.read(totalUnreadCountProvider);
        final total = totalUnread > 0 ? totalUnread : _incomingBurstCount;
        _showUnreadSnack(delta: _incomingBurstCount, total: total);
        _incomingBurstCount = 0;
      });
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _incomingMessageSub?.cancel();
    _incomingSnackDebounce?.cancel();
    final user = ref.read(currentUserProvider);
    if (user != null) {
      ref
          .read(authControllerProvider.notifier)
          .setPresence(userId: user.id, isOnline: false);
    }
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final user = ref.read(currentUserProvider);
    if (user == null) return;

    final authController = ref.read(authControllerProvider.notifier);
    if (state == AppLifecycleState.resumed) {
      authController.setPresence(userId: user.id, isOnline: true);
      return;
    }

    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      authController.setPresence(userId: user.id, isOnline: false);
    }
  }

  void _showUnreadSnack({
    required int delta,
    required int total,
  }) {
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger == null) return;

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final label = delta == 1 ? '1 ta yangi xabar' : '$delta ta yangi xabar';
    final totalLabel = total == 1 ? '1 ta unread' : '$total ta unread';

    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.fromLTRB(16, 0, 16, 94),
          elevation: 0,
          backgroundColor: Colors.transparent,
          duration: const Duration(seconds: 2),
          content: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            decoration: BoxDecoration(
              color: isDark
                  ? const Color(0xFF10151D).withValues(alpha: 0.96)
                  : Colors.white.withValues(alpha: 0.96),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: Colors.redAccent.shade200,
                width: 1.1,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.22),
                  blurRadius: 14,
                  offset: const Offset(0, 5),
                ),
              ],
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.mark_chat_unread_rounded,
                  color: Colors.redAccent,
                  size: 18,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '$label • $totalLabel',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: isDark ? Colors.white : AppTheme.darkText,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
  }

  String _badgeText(int count) {
    if (count <= 99) return '$count';
    return '99+';
  }

  void _onTabTap(int tabIndex) {
    setState(() {
      _index = tabIndex;
      _tabPulseTicks[tabIndex] = (_tabPulseTicks[tabIndex] ?? 0) + 1;
    });
  }

  @override
  Widget build(BuildContext context) {
    final totalUnreadCount = ref.watch(totalUnreadCountProvider);

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final unselectedColor =
        isDark ? Colors.white.withValues(alpha: 0.74) : AppTheme.telegramBlue;

    const tabs = <_LiquidTabData>[
      _LiquidTabData(label: 'Chats', icon: Icons.chat_bubble_rounded),
      _LiquidTabData(label: 'Search', icon: Icons.search_rounded),
      _LiquidTabData(label: 'Profile', icon: Icons.person_rounded),
      _LiquidTabData(label: 'Settings', icon: Icons.settings_rounded),
    ];

    final pages = [
      const HomeScreen(),
      const SearchScreen(fromBottomTab: true),
      const ProfileScreen(),
      const SettingsScreen(),
    ];

    // Background zoom + blur intensity driven by tab index changes
    final backgroundZoom = Tween<double>(begin: 1.0, end: 1.03)
        .animate(CurvedAnimation(
      parent: ModalRoute.of(context)!.animation ?? kAlwaysCompleteAnimation,
      curve: Curves.easeOutCubic,
    ));

    return Scaffold(
      extendBody: true,
      body: AnimatedSwitcher(
        duration: const Duration(milliseconds: 320),
        switchInCurve: Curves.easeOutCubic,
        switchOutCurve: Curves.easeInCubic,
        child: KeyedSubtree(
          key: ValueKey(_index),
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: 1.0, end: 1.0 + (_pressedTabIndex != null ? 0.02 : 0.0)),
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOut,
            builder: (context, scale, child) => Transform.scale(
              scale: scale,
              child: child,
            ),
            child: pages[_index],
          ),
        ),
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 22),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 280),
            curve: Curves.easeOutCubic,
            decoration: const BoxDecoration(),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(26),
              child: Stack(
                children: [
                  // Frosted glass backdrop
                  BackdropFilter(
                    filter: ImageFilter.blur(
                      sigmaX: _index == _pressedTabIndex ? 34 : 28,
                      sigmaY: _index == _pressedTabIndex ? 34 : 28,
                    ),
                    child: const SizedBox(height: 64, width: double.infinity),
                  ),
                  // Subtle noise/gradient under glass
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 220),
                    height: 64,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: isDark
                            ? [
                                const Color(0x330C121C),
                                const Color(0x33070D16),
                              ]
                            : [
                                Colors.white.withValues(alpha: 0.58),
                                Colors.white.withValues(alpha: 0.44),
                              ],
                      ),
                      borderRadius: BorderRadius.circular(26),
                      border: Border.all(
                        color: isDark
                            ? Colors.white.withValues(alpha: 0.08)
                            : Colors.white.withValues(alpha: 0.65),
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: isDark
                              ? Colors.black.withValues(alpha: 0.35)
                              : const Color(0x66FFFFFF),
                          blurRadius: 28,
                          offset: const Offset(0, 12),
                        ),
                      ],
                    ),
                  ),
                  // Glass highlight ridge
                  Positioned(
                    top: 0,
                    left: 14,
                    right: 14,
                    height: 14,
                    child: IgnorePointer(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(999),
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Colors.white.withValues(alpha: isDark ? 0.14 : 0.38),
                              Colors.transparent,
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  // Tabs
                  SizedBox(
                    height: 64,
                    child: Row(
                      children: List.generate(tabs.length, (tabIndex) {
                        final tab = tabs[tabIndex];
                        final selected = _index == tabIndex;
                        final pulseTick = _tabPulseTicks[tabIndex] ?? 0;
                        final pulseBegin = pulseTick == 0 ? 1.0 : 0.9;

                        return Expanded(
                          child: GestureDetector(
                            onTap: () => _onTabTap(tabIndex),
                            onTapDown: (_) => setState(() => _pressedTabIndex = tabIndex),
                            onTapUp: (_) => setState(() => _pressedTabIndex = null),
                            onTapCancel: () => setState(() => _pressedTabIndex = null),
                            behavior: HitTestBehavior.opaque,
                            child: AnimatedScale(
                              duration: const Duration(milliseconds: 110),
                              curve: Curves.easeOutCubic,
                              scale: _pressedTabIndex == tabIndex ? 0.94 : 1.0,
                              child: TweenAnimationBuilder<double>(
                                key: ValueKey('tabPulse-$tabIndex-$pulseTick'),
                                tween: Tween(begin: pulseBegin, end: 1),
                                duration: const Duration(milliseconds: 420),
                                curve: Curves.elasticOut,
                                builder: (context, pulseScale, child) {
                                  return Transform.scale(
                                    scale: pulseScale,
                                    child: child,
                                  );
                                },
                                child: AnimatedContainer(
                                  duration: const Duration(milliseconds: 200),
                                  curve: Curves.easeOutCubic,
                                  margin: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
                                  padding: const EdgeInsets.symmetric(vertical: 7, horizontal: 8),
                                  decoration: BoxDecoration(
                                    color: selected
                                        ? (isDark
                                            ? Colors.white.withValues(alpha: 0.06)
                                            : Colors.white.withValues(alpha: 0.7))
                                        : Colors.transparent,
                                    borderRadius: BorderRadius.circular(20),
                                    border: Border.all(
                                      color: selected
                                          ? Colors.white.withValues(alpha: isDark ? 0.24 : 0.9)
                                          : Colors.transparent,
                                    ),
                                    boxShadow: selected
                                        ? [
                                            BoxShadow(
                                              color: isDark
                                                  ? Colors.black.withValues(alpha: 0.28)
                                                  : Colors.white.withValues(alpha: 0.42),
                                              blurRadius: 18,
                                              offset: const Offset(0, 6),
                                            ),
                                          ]
                                        : [],
                                  ),
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Stack(
                                        clipBehavior: Clip.none,
                                        children: [
                                          Icon(
                                            tab.icon,
                                            size: selected ? 24 : 22,
                                            color: selected
                                                ? AppTheme.telegramBlue
                                                : unselectedColor.withValues(alpha: 0.9),
                                          ),
                                          if (tabIndex == 0 && totalUnreadCount > 0)
                                            Positioned(
                                              right: -10,
                                              top: -8,
                                              child: Container(
                                                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                                                constraints: const BoxConstraints(minWidth: 18, minHeight: 16),
                                                alignment: Alignment.center,
                                                decoration: BoxDecoration(
                                                  color: Colors.redAccent,
                                                  borderRadius: BorderRadius.circular(11),
                                                  border: Border.all(
                                                    color: AppTheme.telegramBlue,
                                                    width: 1.2,
                                                  ),
                                                ),
                                                child: Text(
                                                  _badgeText(totalUnreadCount),
                                                  style: const TextStyle(
                                                    color: Colors.white,
                                                    fontSize: 9.5,
                                                    fontWeight: FontWeight.w900,
                                                    height: 1,
                                                  ),
                                                ),
                                              ),
                                            ),
                                        ],
                                      ),
                                      const SizedBox(width: 6),
                                      AnimatedSize(
                                        duration: const Duration(milliseconds: 180),
                                        curve: Curves.easeOutCubic,
                                        child: SizedBox(
                                          width: selected ? null : 0,
                                          child: selected
                                              ? Text(
                                                  tab.label,
                                                  maxLines: 1,
                                                  overflow: TextOverflow.ellipsis,
                                                  style: TextStyle(
                                                    fontSize: 12,
                                                    fontWeight: FontWeight.w800,
                                                    color: AppTheme.telegramBlue,
                                                  ),
                                                )
                                              : const SizedBox.shrink(),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                        );
                      }),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _LiquidTabData {
  const _LiquidTabData({
    required this.label,
    required this.icon,
  });

  final String label;
  final IconData icon;
}

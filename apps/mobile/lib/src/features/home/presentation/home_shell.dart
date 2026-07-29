import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/application/auth_controller.dart';
import '../../../core/realtime/realtime_controller.dart';
import '../../conversations/application/conversation_list_controller.dart';
import '../../friends/application/friends_controller.dart';
import '../../friends/presentation/friends_screen.dart';
import '../../profile/application/profile_controller.dart';
import '../../profile/presentation/my_screen.dart';

class HomeShell extends ConsumerStatefulWidget {
  const HomeShell({super.key});

  @override
  ConsumerState<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends ConsumerState<HomeShell>
    with WidgetsBindingObserver {
  int _index = 0;

  static const _destinations = [
    _Destination('广场', Icons.forum_outlined, Icons.forum_rounded),
    _Destination('地点', Icons.place_outlined, Icons.place_rounded),
    _Destination('活动', Icons.explore_outlined, Icons.explore_rounded),
    _Destination('好友', Icons.people_outline, Icons.people_rounded),
    _Destination('我的', Icons.person_outline, Icons.person_rounded),
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(
        ref.read(realtimeControllerProvider.notifier).recoverAfterResume(),
      );
      unawaited(
        ref
            .read(conversationListControllerProvider.notifier)
            .load(silent: true),
      );
      unawaited(
        ref.read(friendsControllerProvider.notifier).load(silent: true),
      );
      unawaited(
        ref.read(profileControllerProvider.notifier).load(silent: true),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(realtimeControllerProvider);
    final conversationState = ref.watch(conversationListControllerProvider);
    final friendsState = ref.watch(friendsControllerProvider);
    final friendsUnread =
        conversationState.navigationUnread + friendsState.pendingRequestCount;
    return Scaffold(
      appBar: AppBar(
        title: Text(_destinations[_index].label),
        actions: [
          IconButton(
            tooltip: '搜索',
            onPressed: () {},
            icon: const Icon(Icons.search_rounded),
          ),
          IconButton(
            tooltip: '发布',
            onPressed: () {},
            icon: const Icon(Icons.add_rounded),
          ),
        ],
      ),
      body: IndexedStack(
        index: _index,
        children: [
          for (var index = 0; index < _destinations.length; index++)
            if (_destinations[index].label == '好友')
              const FriendsScreen()
            else if (_destinations[index].label == '我的')
              const MyScreen()
            else
              _SectionPlaceholder(destination: _destinations[index]),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (index) => setState(() => _index = index),
        destinations: [
          for (final destination in _destinations)
            NavigationDestination(
              icon: _DestinationIcon(
                icon: destination.icon,
                unreadCount: destination.label == '好友' ? friendsUnread : 0,
              ),
              selectedIcon: _DestinationIcon(
                icon: destination.selectedIcon,
                unreadCount: destination.label == '好友' ? friendsUnread : 0,
              ),
              label: destination.label,
            ),
        ],
      ),
    );
  }
}

class _DestinationIcon extends StatelessWidget {
  const _DestinationIcon({required this.icon, required this.unreadCount});

  final IconData icon;
  final int unreadCount;

  @override
  Widget build(BuildContext context) {
    final child = Icon(icon);
    if (unreadCount <= 0) return child;
    return Badge.count(
      count: unreadCount,
      backgroundColor: const Color(0xFFE24A52),
      child: child,
    );
  }
}

class _SectionPlaceholder extends ConsumerWidget {
  const _SectionPlaceholder({required this.destination});

  final _Destination destination;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isProfile = destination.label == '我的';
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              destination.selectedIcon,
              size: 44,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(height: 16),
            Text(
              '${destination.label}模块已就位',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            const Text(
              '接下来接入真实数据与交互流程',
              style: TextStyle(color: Color(0xFF78847E)),
            ),
            if (isProfile) ...[
              const SizedBox(height: 26),
              OutlinedButton(
                onPressed: () {
                  ref.read(authControllerProvider.notifier).logout();
                },
                child: const Text('退出登录'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Destination {
  const _Destination(this.label, this.icon, this.selectedIcon);

  final String label;
  final IconData icon;
  final IconData selectedIcon;
}

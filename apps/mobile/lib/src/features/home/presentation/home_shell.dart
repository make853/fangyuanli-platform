import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/navigation/app_navigation.dart';
import '../../../core/realtime/realtime_controller.dart';
import '../../activities/presentation/activity_composer_screen.dart';
import '../../activities/presentation/activities_screen.dart';
import '../../conversations/application/conversation_list_controller.dart';
import '../../friends/application/friends_controller.dart';
import '../../friends/presentation/friend_scan_screen.dart';
import '../../friends/presentation/friends_screen.dart';
import '../../posts/presentation/post_composer_screen.dart';
import '../../places/presentation/places_screen.dart';
import '../../plaza/application/plaza_controller.dart';
import '../../plaza/presentation/plaza_screen.dart';
import '../../profile/application/profile_controller.dart';
import '../../profile/presentation/my_screen.dart';
import '../../search/presentation/global_search_screen.dart';
import 'quick_create_sheet.dart';

class HomeShell extends ConsumerStatefulWidget {
  const HomeShell({super.key});

  @override
  ConsumerState<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends ConsumerState<HomeShell>
    with WidgetsBindingObserver, RouteAware {
  int _index = 0;
  PageRoute<dynamic>? _route;
  bool _routeVisible = false;
  bool _appVisible = true;

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
    _appVisible = _lifecycleIsVisible(WidgetsBinding.instance.lifecycleState);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (identical(_route, route)) return;
    if (_route != null) appRouteObserver.unsubscribe(this);
    _route = route is PageRoute<dynamic> ? route : null;
    if (_route != null) appRouteObserver.subscribe(this, _route!);
  }

  @override
  void dispose() {
    appRouteObserver.unsubscribe(this);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final appVisible = _lifecycleIsVisible(state);
    if (_appVisible != appVisible && mounted) {
      setState(() => _appVisible = appVisible);
    }
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
      unawaited(
        ref.read(plazaControllerProvider.notifier).refresh(silent: true),
      );
    }
  }

  @override
  void didPush() => _setRouteVisible(true);

  @override
  void didPopNext() => _setRouteVisible(true);

  @override
  void didPushNext() => _setRouteVisible(false);

  @override
  void didPop() => _setRouteVisible(false);

  bool _lifecycleIsVisible(AppLifecycleState? state) =>
      state == null || state == AppLifecycleState.resumed;

  void _setRouteVisible(bool visible) {
    if (_routeVisible == visible) return;
    if (mounted) {
      setState(() => _routeVisible = visible);
    } else {
      _routeVisible = visible;
    }
  }

  AppSection get _currentSection => AppSection.values[_index];

  void _openSearch() {
    AppNavigation.push<void>(
      context,
      destination: AppRouteId.globalSearch,
      source: AppNavigationSource(
        section: _currentSection,
        entryPoint: AppEntryPoint.tab,
      ),
      builder: (_) => GlobalSearchScreen(sourceSection: _currentSection),
    );
  }

  Future<void> _openQuickCreate() async {
    final sourceSection = _currentSection;
    final action = await showQuickCreateSheet(context);
    if (!mounted || action == null) return;
    final source = AppNavigationSource(
      section: sourceSection,
      entryPoint: AppEntryPoint.quickCreate,
    );
    switch (action) {
      case QuickCreateAction.post:
        await AppNavigation.push<void>(
          context,
          destination: AppRouteId.postComposer,
          source: source,
          builder: (_) => const PostComposerScreen(),
        );
      case QuickCreateAction.activity:
        await AppNavigation.push<void>(
          context,
          destination: AppRouteId.activityComposer,
          source: source,
          builder: (_) => const ActivityComposerScreen(),
        );
      case QuickCreateAction.scan:
        await AppNavigation.push<void>(
          context,
          destination: AppRouteId.friendScan,
          source: source,
          builder: (_) => const FriendScanScreen(),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(realtimeControllerProvider);
    final conversationState = ref.watch(conversationListControllerProvider);
    final friendsState = ref.watch(friendsControllerProvider);
    final plazaState = ref.watch(plazaControllerProvider);
    final friendsUnread =
        conversationState.navigationUnread + friendsState.pendingRequestCount;
    return Scaffold(
      resizeToAvoidBottomInset: false,
      appBar: AppBar(
        notificationPredicate: (_) => false,
        title: Text(_destinations[_index].label),
        actions: [
          IconButton(
            tooltip: '搜索',
            onPressed: _openSearch,
            icon: const Icon(Icons.search_rounded),
          ),
          IconButton(
            tooltip: '发布',
            onPressed: _openQuickCreate,
            icon: const Icon(Icons.add_rounded),
          ),
        ],
      ),
      body: IndexedStack(
        index: _index,
        children: [
          PlazaScreen(isActive: _index == 0 && _routeVisible && _appVisible),
          const PlacesScreen(),
          const ActivitiesScreen(),
          const FriendsScreen(),
          const MyScreen(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        maintainBottomViewPadding: true,
        selectedIndex: _index,
        onDestinationSelected: (index) => setState(() => _index = index),
        destinations: [
          for (final destination in _destinations)
            NavigationDestination(
              icon: _DestinationIcon(
                icon: destination.icon,
                unreadCount: switch (destination.label) {
                  '广场' => plazaState.navigationUnread,
                  '好友' => friendsUnread,
                  _ => 0,
                },
              ),
              selectedIcon: _DestinationIcon(
                icon: destination.selectedIcon,
                unreadCount: switch (destination.label) {
                  '广场' => plazaState.navigationUnread,
                  '好友' => friendsUnread,
                  _ => 0,
                },
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

class _Destination {
  const _Destination(this.label, this.icon, this.selectedIcon);

  final String label;
  final IconData icon;
  final IconData selectedIcon;
}

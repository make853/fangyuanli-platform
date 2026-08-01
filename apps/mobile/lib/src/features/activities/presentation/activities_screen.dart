import 'package:flutter/material.dart';

import '../../../core/navigation/app_navigation.dart';
import '../../nearby/presentation/nearby_ui.dart';
import '../data/activity_preview_catalog.dart';
import '../domain/activity_models.dart';
import 'activity_card.dart';
import 'activity_chat_screen.dart';
import 'activity_detail_screen.dart';

class ActivitiesScreen extends StatefulWidget {
  const ActivitiesScreen({
    this.activities = ActivityPreviewCatalog.activities,
    super.key,
  });

  final List<ActivitySummary> activities;

  @override
  State<ActivitiesScreen> createState() => _ActivitiesScreenState();
}

class _ActivitiesScreenState extends State<ActivitiesScreen> {
  ActivityListView _view = ActivityListView.nearby;
  int _radiusKm = 30;

  List<ActivitySummary> get _visibleActivities => widget.activities
      .where((activity) => activity.views.contains(_view))
      .where(
        (activity) =>
            _radiusKm == 30 || activity.distanceMeters <= _radiusKm * 1000,
      )
      .toList(growable: false);

  void _pending(String action) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text('$action将在活动纵切接入后启用')));
  }

  @override
  Widget build(BuildContext context) {
    final visibleActivities = _visibleActivities;
    return Column(
      children: [
        const NearbyPreviewNotice(text: '活动卡片为交互预览，活动服务接入后替换为真实数据'),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
          child: SegmentedButton<ActivityListView>(
            segments: [
              for (final view in ActivityListView.values)
                ButtonSegment(value: view, label: Text(view.label)),
            ],
            selected: {_view},
            showSelectedIcon: false,
            onSelectionChanged: (value) => setState(() => _view = value.first),
          ),
        ),
        SizedBox(
          height: 43,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            children: [
              for (final radius in const [30, 1, 3, 5, 10]) ...[
                ChoiceChip(
                  label: Text(radius == 30 ? '全部距离' : '$radius公里'),
                  selected: _radiusKm == radius,
                  onSelected: (_) => setState(() => _radiusKm = radius),
                ),
                const SizedBox(width: 8),
              ],
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
          child: Material(
            color: const Color(0xFFEAF4EF),
            borderRadius: BorderRadius.circular(17),
            child: ListTile(
              leading: const Icon(
                Icons.notifications_active_outlined,
                color: Color(0xFF167A5B),
              ),
              title: const Text(
                '活动期待',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              subtitle: const Text('羽毛球、游泳 · 10公里内出现时提醒我'),
              trailing: TextButton(
                onPressed: () => _pending('活动期待设置'),
                child: const Text('设置'),
              ),
            ),
          ),
        ),
        Expanded(
          child: visibleActivities.isEmpty
              ? const Center(
                  child: Text(
                    '当前筛选下没有活动',
                    style: TextStyle(color: Color(0xFF78847E)),
                  ),
                )
              : ListView.separated(
                  key: const PageStorageKey('activities-list'),
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 28),
                  itemCount: visibleActivities.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 11),
                  itemBuilder: (context, index) {
                    final activity = visibleActivities[index];
                    return ActivityCard(
                      activity: activity,
                      onOpenChat: () => _openChat(activity),
                      onOpenDetails: () => _openDetails(activity),
                    );
                  },
                ),
        ),
      ],
    );
  }

  void _openChat(ActivitySummary activity) {
    AppNavigation.push<void>(
      context,
      destination: AppRouteId.activityChat,
      source: AppNavigationSource(
        section: AppSection.activities,
        entryPoint: AppEntryPoint.channelList,
        entityId: activity.id,
      ),
      builder: (_) => ActivityChatScreen(
        activity: activity,
        detailsBuilder: (_) => ActivityDetailScreen(activity: activity),
      ),
    );
  }

  void _openDetails(ActivitySummary activity) {
    AppNavigation.push<void>(
      context,
      destination: AppRouteId.activityDetail,
      source: AppNavigationSource(
        section: AppSection.activities,
        entryPoint: AppEntryPoint.channelList,
        entityId: activity.id,
      ),
      builder: (_) => ActivityDetailScreen(activity: activity),
    );
  }
}

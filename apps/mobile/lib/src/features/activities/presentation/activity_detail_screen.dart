import 'package:flutter/material.dart';

import '../../../core/navigation/app_navigation.dart';
import '../../nearby/presentation/nearby_ui.dart';
import '../domain/activity_models.dart';
import 'activity_chat_screen.dart';

class ActivityDetailScreen extends StatelessWidget {
  const ActivityDetailScreen({required this.activity, super.key});

  final ActivitySummary activity;

  @override
  Widget build(BuildContext context) {
    void pending(String action) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text('$action将在活动纵切接入后启用')));
    }

    final managedByMe = activity.creatorName == '董事长';
    return Scaffold(
      appBar: AppBar(
        title: const Text('活动详情'),
        actions: [
          IconButton(
            tooltip: '更多',
            onPressed: () => _showActivityMoreActions(context),
            icon: const Icon(Icons.more_horiz_rounded),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 30),
        children: [
          NearbyPreviewNotice(text: '${activity.name}目前使用交互预览数据'),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF1F6B54), Color(0xFF37916F)],
              ),
              borderRadius: BorderRadius.circular(22),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                StatusPill(
                  label: activity.statusLabel,
                  foreground: Colors.white,
                  background: Colors.white24,
                ),
                const SizedBox(height: 12),
                Text(
                  activity.name,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 7),
                Text(
                  '${activity.timeLabel} · ${activity.locationName}',
                  style: const TextStyle(color: Colors.white70),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: FilledButton(
                  onPressed: () => _openChat(context),
                  child: const Text('进入活动群'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => pending('高德地图导航'),
                  icon: const Icon(Icons.navigation_outlined),
                  label: const Text('导航'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          _ActivityDetailCard(
            title: '活动介绍',
            child: Text(
              activity.introduction,
              style: const TextStyle(color: Color(0xFF66736D), height: 1.5),
            ),
          ),
          const SizedBox(height: 12),
          _ActivityDetailCard(
            title: '活动信息',
            child: Column(
              children: [
                _DetailRow(label: '活动地点', value: activity.locationName),
                _DetailRow(
                  label: '距离',
                  value: formatNearbyDistance(activity.distanceMeters),
                ),
                _DetailRow(label: '人数', value: activity.memberLabel),
                _DetailRow(label: '加入方式', value: activity.joinRule),
                _DetailRow(label: '群聊规则', value: activity.chatRule),
              ],
            ),
          ),
          const SizedBox(height: 12),
          _ActivityDetailCard(
            title: '群主',
            child: ListTile(
              contentPadding: EdgeInsets.zero,
              leading: CircleAvatar(
                backgroundColor: const Color(0xFFDDEEE7),
                child: Text(activity.creatorName.characters.first),
              ),
              title: Text(activity.creatorName),
              subtitle: Text(managedByMe ? '创建者 · 可管理活动' : '活动创建者'),
              trailing: managedByMe
                  ? TextButton(
                      onPressed: () => pending('活动管理'),
                      child: const Text('管理活动'),
                    )
                  : null,
              onTap: () => pending('群主资料'),
            ),
          ),
          const SizedBox(height: 12),
          _ActivityDetailCard(
            title: '参与成员',
            child: ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(activity.memberLabel),
              subtitle: const Text('查看已报名成员、群主与管理员'),
              trailing: const Text('查看全部成员'),
              onTap: () => pending('成员列表'),
            ),
          ),
          const SizedBox(height: 12),
          const _ActivityDetailCard(
            title: '活动结束后',
            child: Text(
              '活动会移入“已结束”，参与者仍可以按照记录保留规则查看和继续聊天。',
              style: TextStyle(color: Color(0xFF66736D), height: 1.5),
            ),
          ),
        ],
      ),
    );
  }

  void _openChat(BuildContext context) {
    AppNavigation.push<void>(
      context,
      destination: AppRouteId.activityChat,
      source: AppNavigationSource(
        section: AppSection.activities,
        entryPoint: AppEntryPoint.channelDetail,
        routeId: AppRouteId.activityDetail,
        entityId: activity.id,
      ),
      builder: (_) => ActivityChatScreen(
        activity: activity,
        detailsBuilder: (_) => ActivityDetailScreen(activity: activity),
      ),
    );
  }

  Future<void> _showActivityMoreActions(BuildContext context) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.ios_share_rounded),
              title: const Text('分享活动'),
              onTap: () => Navigator.pop(context, '分享活动'),
            ),
            ListTile(
              leading: const Icon(Icons.report_outlined),
              title: const Text('举报活动'),
              onTap: () => Navigator.pop(context, '举报活动'),
            ),
          ],
        ),
      ),
    );
    if (!context.mounted || action == null) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text('$action将在活动纵切接入后启用')));
  }
}

class _ActivityDetailCard extends StatelessWidget {
  const _ActivityDetailCard({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 12),
            child,
          ],
        ),
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: const TextStyle(color: Color(0xFF66736D)),
            ),
          ),
          const SizedBox(width: 12),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}

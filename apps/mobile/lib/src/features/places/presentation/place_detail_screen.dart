import 'package:flutter/material.dart';

import '../../../core/navigation/app_navigation.dart';
import '../../nearby/presentation/nearby_ui.dart';
import '../domain/place_models.dart';
import 'place_chat_screen.dart';

class PlaceDetailScreen extends StatelessWidget {
  const PlaceDetailScreen({required this.place, super.key});

  final PlaceSummary place;

  @override
  Widget build(BuildContext context) {
    void pending(String action) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text('$action将在地点纵切接入后启用')));
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('地点详情'),
        actions: [
          IconButton(
            tooltip: '更多',
            onPressed: () => _showPlaceMoreActions(context),
            icon: const Icon(Icons.more_horiz_rounded),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 30),
        children: [
          if (place.conversationId.isEmpty) ...[
            NearbyPreviewNotice(text: '${place.name}目前使用交互预览数据'),
            const SizedBox(height: 14),
          ],
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: const Color(0xFF1F6B54),
              borderRadius: BorderRadius.circular(22),
            ),
            child: Row(
              children: [
                Text(place.icon, style: const TextStyle(fontSize: 44)),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        place.name,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 21,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '${formatNearbyDistance(place.distanceMeters)} · ${place.heat.label}',
                        style: const TextStyle(color: Colors.white70),
                      ),
                    ],
                  ),
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
                  child: const Text('进入地点群'),
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
          _PlaceDetailCard(
            title: '地点群信息',
            children: [
              if (place.activePeople case final activePeople?)
                _DetailRow(label: '当前活跃', value: '$activePeople人'),
              const _DetailRow(label: '可见与发言', value: '地点出现在附近范围即可'),
              _DetailRow(
                label: '认证状态',
                value: place.isVerified ? '已认证' : '未认证',
              ),
            ],
          ),
          const SizedBox(height: 12),
          _PlaceDetailCard(
            title: '身份与管理',
            children: [
              if (place.isManagedByMe)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('当前身份：群主'),
                  subtitle: const Text('可管理公告、管理员、禁言和群聊规则'),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => pending('群组管理'),
                )
              else if (place.isVerified)
                const Text('地点主体已认证；当前账号是普通附近用户。')
              else
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('地点尚未认证'),
                  subtitle: const Text('符合条件的主体可以发起认领申请'),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => pending('地点认领'),
                ),
            ],
          ),
          const SizedBox(height: 12),
          const _PlaceDetailCard(
            title: '地点群说明',
            children: [
              Text(
                '地点群由系统根据地图地点按需生成，没有个人创建者。用户只会看到自己附近范围内出现的地点群，不会向其他用户展示你的精准位置。',
                style: TextStyle(color: Color(0xFF66736D), height: 1.5),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _openChat(BuildContext context) {
    AppNavigation.push<void>(
      context,
      destination: AppRouteId.placeChat,
      source: AppNavigationSource(
        section: AppSection.places,
        entryPoint: AppEntryPoint.channelDetail,
        routeId: AppRouteId.placeDetail,
        entityId: place.id,
      ),
      builder: (_) => PlaceChatScreen(
        place: place,
        detailsBuilder: (_) => PlaceDetailScreen(place: place),
      ),
    );
  }

  Future<void> _showPlaceMoreActions(BuildContext context) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.ios_share_rounded),
              title: const Text('分享地点'),
              onTap: () => Navigator.pop(context, '分享地点'),
            ),
            ListTile(
              leading: const Icon(Icons.edit_location_alt_outlined),
              title: const Text('反馈地点信息'),
              onTap: () => Navigator.pop(context, '反馈地点信息'),
            ),
            ListTile(
              leading: const Icon(Icons.report_outlined),
              title: const Text('举报地点群'),
              onTap: () => Navigator.pop(context, '举报地点群'),
            ),
          ],
        ),
      ),
    );
    if (!context.mounted || action == null) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text('$action将在地点纵切接入后启用')));
  }
}

class _PlaceDetailCard extends StatelessWidget {
  const _PlaceDetailCard({required this.title, required this.children});

  final String title;
  final List<Widget> children;

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
            ...children,
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

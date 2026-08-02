import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/navigation/app_navigation.dart';
import '../../conversations/domain/community_chat_models.dart';
import '../../conversations/presentation/community_chat_screen.dart';
import '../../nearby/presentation/nearby_ui.dart';
import '../application/plaza_controller.dart';
import '../data/plaza_preview_catalog.dart';
import '../domain/plaza_models.dart';

enum _PlazaView { chat, feed }

class PlazaScreen extends ConsumerStatefulWidget {
  const PlazaScreen({
    this.plazas = PlazaPreviewCatalog.plazas,
    this.previewMessages = PlazaPreviewCatalog.messages,
    super.key,
  });

  final List<PlazaSummary> plazas;
  final List<CommunityMessagePreview> previewMessages;

  @override
  ConsumerState<PlazaScreen> createState() => _PlazaScreenState();
}

class _PlazaScreenState extends ConsumerState<PlazaScreen> {
  _PlazaView _view = _PlazaView.chat;
  late String _selectedPlazaId;
  final _readPlazaIds = <String>{};

  @override
  void initState() {
    super.initState();
    _selectedPlazaId = widget.plazas.first.id;
  }

  void _pending(String action) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text('$action将在广场纵切接入后启用')));
  }

  @override
  Widget build(BuildContext context) {
    final plazaState = ref.watch(plazaControllerProvider);
    final plazas = plazaState.plazas.length == 4
        ? plazaState.plazas
        : widget.plazas;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
          child: SegmentedButton<_PlazaView>(
            segments: const [
              ButtonSegment(value: _PlazaView.chat, label: Text('聊天')),
              ButtonSegment(value: _PlazaView.feed, label: Text('动态')),
            ],
            selected: {_view},
            showSelectedIcon: false,
            onSelectionChanged: (value) => setState(() => _view = value.first),
          ),
        ),
        Expanded(
          child: _view == _PlazaView.chat
              ? _buildChat(plazas, plazaState)
              : const _PlazaFeedShell(),
        ),
      ],
    );
  }

  Widget _buildChat(List<PlazaSummary> plazas, PlazaState plazaState) {
    final selectedId = plazas.any((plaza) => plaza.id == _selectedPlazaId)
        ? _selectedPlazaId
        : plazas.first.id;
    final selected = plazas.firstWhere((plaza) => plaza.id == selectedId);
    return Column(
      children: [
        SizedBox(
          height: 98,
          child: ListView.separated(
            key: const ValueKey('plaza-switcher'),
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: plazas.length,
            separatorBuilder: (_, _) => const SizedBox(width: 9),
            itemBuilder: (context, index) {
              final plaza = plazas[index];
              return _PlazaSwitchCard(
                plaza: plaza,
                selected: plaza.id == selected.id,
                unreadCount: _readPlazaIds.contains(plaza.id)
                    ? 0
                    : plaza.unreadCount,
                onTap: () => setState(() {
                  _selectedPlazaId = plaza.id;
                  _readPlazaIds.add(plaza.id);
                }),
              );
            },
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 3, 8, 1),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  _locationStatus(plazaState),
                  style: const TextStyle(
                    color: Color(0xFF78847E),
                    fontSize: 12,
                  ),
                ),
              ),
              if (!plazaState.isLoading)
                IconButton(
                  key: const ValueKey('plaza-location-refresh'),
                  tooltip: '刷新附近广场',
                  visualDensity: VisualDensity.compact,
                  onPressed: () => ref
                      .read(plazaControllerProvider.notifier)
                      .refresh(silent: plazaState.plazas.isNotEmpty),
                  icon: const Icon(Icons.my_location_rounded, size: 18),
                )
              else
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 13),
                  child: SizedBox.square(
                    dimension: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 6, 2),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  selected.name,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              TextButton(
                onPressed: () => _pending('广场通知设置'),
                child: const Text('通知设置'),
              ),
              IconButton(
                tooltip: '广场信息',
                onPressed: () => AppNavigation.push<void>(
                  context,
                  destination: AppRouteId.plazaInfo,
                  source: AppNavigationSource(
                    section: AppSection.plaza,
                    entryPoint: AppEntryPoint.channelChat,
                    routeId: AppRouteId.plazaChat,
                    entityId: selected.id,
                  ),
                  builder: (_) => PlazaInfoScreen(plaza: selected),
                ),
                icon: const Icon(Icons.more_horiz_rounded),
              ),
            ],
          ),
        ),
        Expanded(
          child: CommunityChatBody(
            key: ValueKey('plaza-chat-${selected.id}'),
            channel: CommunityChannelDescriptor(
              id: selected.conversationId ?? selected.id,
              kind: CommunityChannelKind.plaza,
              title: selected.name,
              subtitle:
                  '${selected.isPrimary ? '主广场' : '相邻广场'} · ${selected.activityLabel}',
              emptyMessage: '这个广场暂时还没有消息',
            ),
            previewMessages: selected.isPrimary
                ? widget.previewMessages
                : const [],
          ),
        ),
      ],
    );
  }

  String _locationStatus(PlazaState state) {
    if (state.hasFreshEligibility) {
      return '当前位置可进入的4个广场 · 均可发言';
    }
    if (state.isUsingCachedOverview) {
      return state.isLoading ? '正在确认当前位置 · 先显示上次广场' : '上次进入的广场 · 点击定位刷新';
    }
    if (state.errorMessage != null) return '定位后显示真实的4个广场 · 点击重试';
    return '正在获取附近广场';
  }
}

class _PlazaSwitchCard extends StatelessWidget {
  const _PlazaSwitchCard({
    required this.plaza,
    required this.selected,
    required this.unreadCount,
    required this.onTap,
  });

  final PlazaSummary plaza;
  final bool selected;
  final int unreadCount;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 116,
      child: Material(
        color: selected ? const Color(0xFFDDEEE7) : Colors.white,
        borderRadius: BorderRadius.circular(17),
        child: InkWell(
          key: ValueKey('plaza-switch-${plaza.id}'),
          borderRadius: BorderRadius.circular(17),
          onTap: onTap,
          child: Stack(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 11, 9, 9),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      plaza.isPrimary ? '主广场' : '相邻',
                      style: const TextStyle(
                        color: Color(0xFF78847E),
                        fontSize: 10,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      plaza.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    const Spacer(),
                    Text(
                      plaza.activityLabel,
                      style: const TextStyle(
                        color: Color(0xFF66736D),
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
              Positioned(
                right: 7,
                top: 7,
                child: UnreadCountBadge(count: unreadCount),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class PlazaInfoScreen extends StatelessWidget {
  const PlazaInfoScreen({required this.plaza, super.key});

  final PlazaSummary plaza;

  @override
  Widget build(BuildContext context) {
    void pending(String action) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text('$action将在广场服务接入后启用')));
    }

    return Scaffold(
      appBar: AppBar(title: const Text('广场信息')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 30),
        children: [
          if (plaza.conversationId == null) ...[
            NearbyPreviewNotice(text: '${plaza.name}目前使用交互预览数据'),
            const SizedBox(height: 14),
          ],
          Card(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    plaza.name,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '${plaza.isPrimary ? '当前主广场' : '可发言的相邻广场'} · ${plaza.activityLabel}',
                    style: const TextStyle(color: Color(0xFF66736D)),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.notifications_none_rounded),
                  title: const Text('通知设置'),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => pending('通知设置'),
                ),
                const Divider(height: 1, indent: 56),
                ListTile(
                  leading: const Icon(Icons.info_outline_rounded),
                  title: const Text('广场切换规则'),
                  subtitle: const Text('锚点移动约150米后再结合定位稳定性判断'),
                  onTap: () => pending('广场切换说明'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PlazaFeedShell extends StatefulWidget {
  const _PlazaFeedShell();

  @override
  State<_PlazaFeedShell> createState() => _PlazaFeedShellState();
}

class _PlazaFeedShellState extends State<_PlazaFeedShell> {
  bool _hot = false;
  int _radiusKm = 1;
  DateTime? _date;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 30),
      children: [
        const NearbyPreviewNotice(text: '动态列表将在动态纵切中接入真实数据'),
        const SizedBox(height: 12),
        Row(
          children: [
            SegmentedButton<bool>(
              segments: const [
                ButtonSegment(value: false, label: Text('最新')),
                ButtonSegment(value: true, label: Text('热门')),
              ],
              selected: {_hot},
              showSelectedIcon: false,
              onSelectionChanged: (value) => setState(() => _hot = value.first),
            ),
            const Spacer(),
            Text(
              _hot ? '按互动热度排序' : '新动态优先',
              style: const TextStyle(color: Color(0xFF78847E), fontSize: 11),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            ActionChip(
              avatar: const Icon(Icons.near_me_outlined, size: 17),
              label: Text('$_radiusKm公里'),
              onPressed: () async {
                final value = await showNearbySelectionSheet<int>(
                  context,
                  title: '动态可见范围',
                  selected: _radiusKm,
                  values: const [1, 3, 5, 10, 30],
                  label: (value) => '$value公里',
                );
                if (value != null && mounted) setState(() => _radiusKm = value);
              },
            ),
            ActionChip(
              avatar: const Icon(Icons.calendar_today_outlined, size: 17),
              label: Text(_date == null ? '全部日期' : _formatDate(_date!)),
              onPressed: () async {
                final value = await showDatePicker(
                  context: context,
                  initialDate: _date ?? DateTime.now(),
                  firstDate: DateTime(2020),
                  lastDate: DateTime.now(),
                );
                if (value != null && mounted) setState(() => _date = value);
              },
            ),
            if (_date != null)
              ActionChip(
                label: const Text('清除日期'),
                onPressed: () => setState(() => _date = null),
              ),
          ],
        ),
        const SizedBox(height: 90),
        const Icon(
          Icons.dynamic_feed_outlined,
          size: 48,
          color: Color(0xFFA1AAA5),
        ),
        const SizedBox(height: 12),
        const Text(
          '动态数据服务接入后显示附近内容',
          textAlign: TextAlign.center,
          style: TextStyle(color: Color(0xFF78847E)),
        ),
      ],
    );
  }

  String _formatDate(DateTime value) => '${value.month}月${value.day}日';
}

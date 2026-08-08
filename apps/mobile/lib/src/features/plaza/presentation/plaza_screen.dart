import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/navigation/app_navigation.dart';
import '../../auth/application/auth_controller.dart';
import '../../conversations/application/conversation_sync_controller.dart';
import '../../conversations/data/conversation_repository.dart';
import '../../conversations/domain/community_chat_models.dart';
import '../../conversations/presentation/community_chat_screen.dart';
import '../../nearby/presentation/nearby_ui.dart';
import '../../profile/application/profile_controller.dart';
import '../application/plaza_controller.dart';
import '../application/plaza_chat_controller.dart';
import '../data/plaza_preview_catalog.dart';
import '../domain/plaza_models.dart';

enum _PlazaView { chat, feed }

class PlazaScreen extends ConsumerStatefulWidget {
  const PlazaScreen({
    this.plazas = PlazaPreviewCatalog.plazas,
    this.previewMessages = PlazaPreviewCatalog.messages,
    this.isActive = true,
    super.key,
  });

  final List<PlazaSummary> plazas;
  final List<CommunityMessagePreview> previewMessages;
  final bool isActive;

  @override
  ConsumerState<PlazaScreen> createState() => _PlazaScreenState();
}

class _PlazaScreenState extends ConsumerState<PlazaScreen> {
  _PlazaView _view = _PlazaView.chat;
  late String _selectedPlazaId;
  PlazaSummary? _selectedPlazaSnapshot;
  final _previewReadPlazaIds = <String>{};
  final _entryUnread = <String, PlazaUnreadState>{};
  ConversationSyncController? _readVisibleController;
  ConversationSyncController? _scheduledReadVisibleController;
  bool _scheduledReadVisible = false;

  @override
  void initState() {
    super.initState();
    _selectedPlazaId = widget.plazas.first.id;
    _selectedPlazaSnapshot = widget.plazas.first;
  }

  @override
  void dispose() {
    _readVisibleController?.setReadVisible(false);
    super.dispose();
  }

  void _openPlazaInfo(PlazaSummary plaza) {
    AppNavigation.push<void>(
      context,
      destination: AppRouteId.plazaInfo,
      source: AppNavigationSource(
        section: AppSection.plaza,
        entryPoint: AppEntryPoint.channelChat,
        routeId: AppRouteId.plazaChat,
        entityId: plaza.id,
      ),
      builder: (_) => PlazaInfoScreen(plaza: plaza),
    );
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
          padding: const EdgeInsets.fromLTRB(16, 6, 8, 6),
          child: SizedBox(
            height: 48,
            child: Stack(
              alignment: Alignment.center,
              children: [
                SegmentedButton<_PlazaView>(
                  segments: const [
                    ButtonSegment(value: _PlazaView.chat, label: Text('聊天')),
                    ButtonSegment(value: _PlazaView.feed, label: Text('动态')),
                  ],
                  selected: {_view},
                  showSelectedIcon: false,
                  onSelectionChanged: (value) =>
                      setState(() => _view = value.first),
                ),
                Align(
                  alignment: Alignment.centerRight,
                  child: plazaState.isLoading
                      ? const Padding(
                          padding: EdgeInsets.all(10),
                          child: SizedBox.square(
                            dimension: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        )
                      : IconButton(
                          key: const ValueKey('plaza-location-refresh'),
                          tooltip: '刷新附近广场',
                          visualDensity: VisualDensity.compact,
                          onPressed: () => ref
                              .read(plazaControllerProvider.notifier)
                              .refresh(silent: plazaState.plazas.isNotEmpty),
                          icon: const Icon(Icons.my_location_rounded, size: 19),
                        ),
                ),
              ],
            ),
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
    final currentSelection = plazas
        .where((plaza) => plaza.id == _selectedPlazaId)
        .firstOrNull;
    if (currentSelection != null) {
      _selectedPlazaSnapshot = currentSelection;
    }
    final historicalSelection =
        currentSelection == null &&
        _selectedPlazaSnapshot?.id == _selectedPlazaId;
    final selected = currentSelection ?? _selectedPlazaSnapshot ?? plazas.first;
    final selectedUnread =
        _entryUnread[selected.id] ??
        PlazaUnreadState(
          count: selected.unreadCount,
          appearance: selected.unreadAppearance,
          firstUnreadSequence: selected.firstUnreadSequence,
        );
    if (selectedUnread.count > 0 &&
        selectedUnread.firstUnreadSequence != null) {
      _entryUnread.putIfAbsent(selected.id, () => selectedUnread);
    }
    final canSend = !historicalSelection && selected.canSpeak;
    final readOnlyMessage = historicalSelection
        ? '已离开此广场，仅可查看历史消息'
        : selected.canSpeak
        ? null
        : '当前广场仅可查看';
    final conversationId = selected.conversationId;
    final currentUserId = ref.watch(
      authControllerProvider.select((state) => state.session?.userId),
    );
    final ownProfile = ref.watch(profileControllerProvider).profile;
    final liveScope = conversationId == null
        ? null
        : PlazaChatScope(conversationId: conversationId);
    final liveState = liveScope == null
        ? null
        : ref.watch(plazaChatControllerProvider(liveScope));
    final liveController = liveScope == null
        ? null
        : ref.read(plazaChatControllerProvider(liveScope).notifier);
    _scheduleReadVisibility(
      liveController,
      widget.isActive && _view == _PlazaView.chat && !historicalSelection,
    );
    return Column(
      children: [
        SizedBox(
          key: const ValueKey('plaza-switcher'),
          height: 76,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var index = 0; index < plazas.length; index++) ...[
                  if (index > 0) const SizedBox(width: 7),
                  Expanded(
                    child: _PlazaSwitchCard(
                      plaza: plazas[index],
                      selected:
                          !historicalSelection &&
                          plazas[index].id == selected.id,
                      unreadCount:
                          _previewReadPlazaIds.contains(plazas[index].id)
                          ? 0
                          : plazas[index].unreadCount,
                      onTap: () => setState(() {
                        final plaza = plazas[index];
                        if (plaza.unreadCount > 0 &&
                            plaza.firstUnreadSequence != null) {
                          _entryUnread.putIfAbsent(
                            plaza.id,
                            () => PlazaUnreadState(
                              count: plaza.unreadCount,
                              appearance: plaza.unreadAppearance,
                              firstUnreadSequence: plaza.firstUnreadSequence,
                            ),
                          );
                        }
                        _selectedPlazaId = plazas[index].id;
                        _selectedPlazaSnapshot = plazas[index];
                        if (plazas[index].conversationId == null) {
                          _previewReadPlazaIds.add(plazas[index].id);
                        } else {
                          ref
                              .read(plazaControllerProvider.notifier)
                              .markLocallyRead(plazas[index].id);
                        }
                      }),
                      onMore: () => _openPlazaInfo(plazas[index]),
                    ),
                  ),
                ],
              ],
            ),
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
            showPreviewNotice: liveState == null,
            liveState: liveState,
            currentUserId: currentUserId,
            onSend: liveScope == null || !canSend
                ? null
                : (value) => ref
                      .read(plazaChatControllerProvider(liveScope).notifier)
                      .send(
                        value,
                        senderName: ownProfile?.displayName ?? '我',
                        senderProfileVersion: ownProfile?.profileVersion ?? 1,
                        senderAvatar: ownProfile?.avatar,
                      ),
            onRetry: liveScope == null || !canSend
                ? null
                : (clientMessageId) => ref
                      .read(plazaChatControllerProvider(liveScope).notifier)
                      .retry(clientMessageId),
            onLoadEarlier: liveScope == null
                ? null
                : ref
                      .read(plazaChatControllerProvider(liveScope).notifier)
                      .loadEarlier,
            onLoadLater: liveScope == null
                ? null
                : ref
                      .read(plazaChatControllerProvider(liveScope).notifier)
                      .loadLater,
            initialUnreadCount: selectedUnread.count,
            initialFirstUnreadSequence: selectedUnread.firstUnreadSequence,
            onLocateSequence: liveScope == null
                ? null
                : (sequence) async {
                    final located = await ref
                        .read(plazaChatControllerProvider(liveScope).notifier)
                        .loadAround(sequence);
                    if (located && mounted) {
                      setState(() => _entryUnread.remove(selected.id));
                    }
                    return located;
                  },
            readOnlyMessage: readOnlyMessage,
            bottomChromeHeight:
                (NavigationBarTheme.of(context).height ?? 80) +
                MediaQuery.viewPaddingOf(context).bottom,
          ),
        ),
      ],
    );
  }

  void _scheduleReadVisibility(
    ConversationSyncController? controller,
    bool visible,
  ) {
    if (identical(_scheduledReadVisibleController, controller) &&
        _scheduledReadVisible == visible) {
      return;
    }
    _scheduledReadVisibleController = controller;
    _scheduledReadVisible = visible;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted ||
          !identical(_scheduledReadVisibleController, controller) ||
          _scheduledReadVisible != visible) {
        return;
      }
      final nextController = visible ? controller : null;
      if (identical(_readVisibleController, nextController)) return;
      _readVisibleController?.setReadVisible(false);
      _readVisibleController = nextController;
      _readVisibleController?.setReadVisible(true);
    });
  }
}

class _PlazaSwitchCard extends StatelessWidget {
  const _PlazaSwitchCard({
    required this.plaza,
    required this.selected,
    required this.unreadCount,
    required this.onTap,
    required this.onMore,
  });

  final PlazaSummary plaza;
  final bool selected;
  final int unreadCount;
  final VoidCallback onTap;
  final VoidCallback onMore;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? const Color(0xFFDDEEE7) : Colors.white,
      borderRadius: BorderRadius.circular(14),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        key: ValueKey('plaza-switch-${plaza.id}'),
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Stack(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 7, 6, 6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(right: 22),
                    child: Text(
                      plaza.isPrimary ? '主广场' : '相邻',
                      maxLines: 1,
                      style: const TextStyle(
                        color: Color(0xFF78847E),
                        fontSize: 10,
                      ),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Padding(
                    padding: EdgeInsets.only(right: unreadCount > 0 ? 16 : 0),
                    child: Text(
                      plaza.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 11,
                        height: 1.12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Positioned(
              right: 4,
              top: 2,
              child: SizedBox.square(
                dimension: 27,
                child: IconButton(
                  key: ValueKey('plaza-more-${plaza.id}'),
                  tooltip: '${plaza.name}信息',
                  padding: EdgeInsets.zero,
                  visualDensity: VisualDensity.compact,
                  onPressed: onMore,
                  icon: const Icon(Icons.more_horiz_rounded, size: 17),
                ),
              ),
            ),
            Positioned(
              right: 5,
              bottom: 5,
              child: UnreadCountBadge(count: unreadCount),
            ),
          ],
        ),
      ),
    );
  }
}

class PlazaInfoScreen extends ConsumerStatefulWidget {
  const PlazaInfoScreen({required this.plaza, super.key});

  final PlazaSummary plaza;

  @override
  ConsumerState<PlazaInfoScreen> createState() => _PlazaInfoScreenState();
}

class _PlazaInfoScreenState extends ConsumerState<PlazaInfoScreen> {
  late String _notificationMode = widget.plaza.notificationMode;
  bool _savingNotificationMode = false;

  Future<void> _setNotificationsEnabled(bool enabled) async {
    final conversationId = widget.plaza.conversationId;
    if (conversationId == null || _savingNotificationMode) return;
    setState(() => _savingNotificationMode = true);
    try {
      final mode = await ref
          .read(conversationSettingsRepositoryProvider)
          .updateNotificationMode(conversationId, enabled ? 'normal' : 'muted');
      if (!mounted) return;
      setState(() {
        _notificationMode = mode;
        _savingNotificationMode = false;
      });
      ref
          .read(plazaControllerProvider.notifier)
          .setNotificationMode(widget.plaza.id, mode);
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(content: Text(enabled ? '已接收此广场通知' : '此广场已开启免打扰')),
        );
    } catch (error) {
      if (!mounted) return;
      setState(() => _savingNotificationMode = false);
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text('设置失败：$error')));
    }
  }

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
          if (widget.plaza.conversationId == null) ...[
            NearbyPreviewNotice(text: '${widget.plaza.name}目前使用交互预览数据'),
            const SizedBox(height: 14),
          ],
          Card(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.plaza.name,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '${widget.plaza.isPrimary ? '当前主广场' : '可发言的相邻广场'} · ${widget.plaza.activityLabel}',
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
                SwitchListTile(
                  secondary: const Icon(Icons.notifications_none_rounded),
                  title: const Text('接收此广场通知'),
                  subtitle: Text(
                    _notificationMode == 'muted'
                        ? '未读仍会保留，但显示为灰点且不计入底栏红点'
                        : '新消息显示红点，并计入广场底栏未读',
                  ),
                  value: _notificationMode != 'muted',
                  onChanged:
                      widget.plaza.conversationId == null ||
                          _savingNotificationMode
                      ? null
                      : _setNotificationsEnabled,
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

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/navigation/app_navigation.dart';
import '../../friends/application/friends_controller.dart';
import '../../friends/domain/friend_models.dart';
import '../../friends/presentation/friend_profile_screen.dart';
import '../../media/domain/media_upload_models.dart';
import '../../profile/application/profile_controller.dart';
import '../../profile/presentation/profile_detail_screen.dart';
import '../application/direct_chat_controller.dart';
import '../domain/conversation_message.dart';
import 'chat_composer.dart';
import 'chat_message_bubble.dart';
import 'chat_message_timeline.dart';
import 'chat_time.dart';
import 'chat_unread_jump.dart';
import 'direct_chat_settings_screen.dart';

class DirectChatScreen extends ConsumerStatefulWidget {
  const DirectChatScreen({
    required this.conversationId,
    required this.title,
    required this.currentUserId,
    this.peerUserId,
    this.peerAvatar,
    this.initialUnreadCount = 0,
    this.initialFirstUnreadSequence,
    super.key,
  });

  final String conversationId;
  final String title;
  final String currentUserId;
  final String? peerUserId;
  final MediaAsset? peerAvatar;
  final int initialUnreadCount;
  final int? initialFirstUnreadSequence;

  @override
  ConsumerState<DirectChatScreen> createState() => _DirectChatScreenState();
}

class _DirectChatScreenState extends ConsumerState<DirectChatScreen>
    with WidgetsBindingObserver, RouteAware {
  final _textController = TextEditingController();
  final _focusNode = FocusNode();
  final _composerController = ChatComposerController();
  late final ChatTimelineViewportController _timelineController;
  late final DirectChatController _chatController;
  final _messageKeys = <int, GlobalKey>{};
  PageRoute<dynamic>? _route;
  bool _routeVisible = false;
  bool _appVisible = true;
  late int _unreadJumpCount;
  late int? _unreadJumpSequence;

  @override
  void initState() {
    super.initState();
    _timelineController = ChatTimelineViewportController();
    _chatController = ref.read(
      directChatControllerProvider(widget.conversationId).notifier,
    );
    _unreadJumpCount = widget.initialUnreadCount;
    _unreadJumpSequence = widget.initialFirstUnreadSequence;
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
    _routeVisible = false;
    _syncReadVisibility();
    _textController.dispose();
    _focusNode.dispose();
    _timelineController.dispose();
    _composerController.dispose();
    super.dispose();
  }

  @override
  void didPush() {
    _routeVisible = true;
    _syncReadVisibility();
  }

  @override
  void didPopNext() {
    _routeVisible = true;
    _syncReadVisibility();
  }

  @override
  void didPushNext() {
    _routeVisible = false;
    _syncReadVisibility();
  }

  @override
  void didPop() {
    _routeVisible = false;
    _syncReadVisibility();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _appVisible = _lifecycleIsVisible(state);
    _syncReadVisibility();
  }

  bool _lifecycleIsVisible(AppLifecycleState? state) =>
      state == null || state == AppLifecycleState.resumed;

  void _syncReadVisibility() {
    _chatController.setReadVisible(_routeVisible && _appVisible);
  }

  Future<void> _send() async {
    final value = _textController.text;
    final ownProfile = ref.read(profileControllerProvider).profile;
    final succeeded = await ref
        .read(directChatControllerProvider(widget.conversationId).notifier)
        .send(
          value,
          senderName: ownProfile?.displayName ?? '我',
          senderProfileVersion: ownProfile?.profileVersion ?? 1,
          senderAvatar: ownProfile?.avatar,
        );
    if (!mounted) return;
    if (succeeded) {
      _textController.clear();
      _timelineController.scrollToLatest(jump: true);
    }
  }

  void _showUnavailableAction(String action) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text('$action将在聊天媒体链路中接入')));
  }

  void _openProfile(String? userId) {
    if (userId == null) return;
    if (userId == widget.currentUserId) {
      AppNavigation.push<void>(
        context,
        destination: AppRouteId.myProfile,
        source: AppNavigationSource(
          section: AppSection.friends,
          entryPoint: AppEntryPoint.directChat,
          routeId: AppRouteId.directChat,
          entityId: widget.conversationId,
        ),
        builder: (_) => const MyProfileDetailScreen(),
      );
      return;
    }
    final contacts = ref.read(friendsControllerProvider).contacts;
    FriendContact? contact;
    for (final item in contacts) {
      if (item.userId == userId) {
        contact = item;
        break;
      }
    }
    if (contact == null) {
      _showUnavailableAction('用户资料');
      return;
    }
    AppNavigation.push<void>(
      context,
      destination: AppRouteId.friendProfile,
      source: AppNavigationSource(
        section: AppSection.friends,
        entryPoint: AppEntryPoint.directChat,
        routeId: AppRouteId.directChat,
        entityId: widget.conversationId,
      ),
      builder: (_) => FriendProfileScreen(initialContact: contact!),
    );
  }

  Future<void> _openSettings(String title, DirectChatState state) async {
    final result = await AppNavigation.push<DirectChatSettingsResult>(
      context,
      destination: AppRouteId.directChatSettings,
      source: AppNavigationSource(
        section: AppSection.friends,
        entryPoint: AppEntryPoint.directChat,
        routeId: AppRouteId.directChat,
        entityId: widget.conversationId,
      ),
      builder: (_) => DirectChatSettingsScreen(
        conversationId: widget.conversationId,
        title: title,
        messages: state.messages,
      ),
    );
    if (!mounted || result == null) return;
    if (result.closeConversation) {
      Navigator.pop(context);
      return;
    }
    final sequence = result.sequence;
    if (sequence == null) return;
    if (!await _locateSequence(sequence) && mounted) {
      _showUnavailableAction('该条聊天记录定位');
    }
  }

  Future<bool> _locateSequence(int sequence) async {
    var target = _messageKeys[sequence]?.currentContext;
    if (target == null) {
      final loaded = await _chatController.loadAround(sequence);
      if (!mounted || !loaded) return false;
      await WidgetsBinding.instance.endOfFrame;
      if (!mounted) return false;
      target = _messageKeys[sequence]?.currentContext;
    }
    if (target == null && _timelineController.scrollController.hasClients) {
      final messages = ref
          .read(directChatControllerProvider(widget.conversationId))
          .messages;
      target = await _timelineController.revealSequence(
        messages: messages,
        sequence: sequence,
        keys: _messageKeys,
      );
      if (!mounted) return false;
    }
    if (target == null || !target.mounted) return false;
    await Scrollable.ensureVisible(
      target,
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOut,
      alignment: 0.25,
    );
    return true;
  }

  Future<void> _openUnreadJump() async {
    final sequence = _unreadJumpSequence;
    if (sequence == null) return;
    final located = await _locateSequence(sequence);
    if (!mounted || !located) return;
    setState(() {
      _unreadJumpCount = 0;
      _unreadJumpSequence = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final provider = directChatControllerProvider(widget.conversationId);
    final state = ref.watch(provider);
    final ownProfile = ref.watch(profileControllerProvider).profile;
    FriendContact? currentContact;
    for (final contact in ref.watch(friendsControllerProvider).contacts) {
      if (contact.directConversationId == widget.conversationId) {
        currentContact = contact;
        break;
      }
    }
    final currentTitle = currentContact?.visibleName ?? widget.title;

    ref.listen(provider, (previous, next) {
      if (next.errorMessage != null &&
          next.errorMessage != previous?.errorMessage) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text(next.errorMessage!)));
      }
      final oldMessages = previous?.messages ?? const [];
      final newMessages = next.messages;
      final oldLatest = oldMessages.isEmpty ? null : oldMessages.last;
      final newLatest = newMessages.isEmpty ? null : newMessages.last;
      if (_logicalMessageId(newLatest) != _logicalMessageId(oldLatest)) {
        final followsLatest =
            oldMessages.isEmpty ||
            _timelineController.isNearLatest ||
            newLatest?.senderUserId == widget.currentUserId;
        if (followsLatest) {
          _timelineController.scrollToLatest(jump: true);
        }
      }
    });

    return Scaffold(
      resizeToAvoidBottomInset: false,
      appBar: AppBar(
        title: Text(currentTitle),
        actions: [
          IconButton(
            tooltip: '聊天设置',
            onPressed: () => _openSettings(currentTitle, state),
            icon: const Icon(Icons.more_horiz_rounded),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: Stack(
              children: [
                Positioned.fill(
                  child: GestureDetector(
                    behavior: HitTestBehavior.translucent,
                    onTap: () => _composerController.dismiss(_focusNode),
                    child: _MessageList(
                      state: state,
                      userId: widget.currentUserId,
                      controller: _timelineController.scrollController,
                      ownAvatar: ownProfile?.avatar,
                      ownInitial: ownProfile?.initial ?? '我',
                      peerAvatar: currentContact?.avatar ?? widget.peerAvatar,
                      onAvatarTap: _openProfile,
                      onRetry: (clientMessageId) =>
                          ref.read(provider.notifier).retry(clientMessageId),
                      onLoadEarlier: ref.read(provider.notifier).loadEarlier,
                      onLoadLater: ref.read(provider.notifier).loadLater,
                      keyForSequence: (sequence) =>
                          _messageKeys.putIfAbsent(sequence, GlobalKey.new),
                    ),
                  ),
                ),
                if (_unreadJumpCount > 0 && _unreadJumpSequence != null)
                  Positioned(
                    top: 12,
                    right: 12,
                    child: ChatUnreadJump(
                      count: _unreadJumpCount,
                      onTap: _openUnreadJump,
                    ),
                  ),
              ],
            ),
          ),
          ChatComposer(
            controller: _composerController,
            textController: _textController,
            focusNode: _focusNode,
            onSend: _send,
            onUnavailableAction: _showUnavailableAction,
          ),
        ],
      ),
    );
  }

  String? _logicalMessageId(ConversationMessage? message) =>
      message?.clientMessageId ?? message?.messageId;
}

class _MessageList extends StatelessWidget {
  const _MessageList({
    required this.state,
    required this.userId,
    required this.controller,
    required this.ownInitial,
    required this.onAvatarTap,
    required this.keyForSequence,
    required this.onRetry,
    required this.onLoadEarlier,
    required this.onLoadLater,
    this.ownAvatar,
    this.peerAvatar,
  });

  final DirectChatState state;
  final String userId;
  final ScrollController controller;
  final MediaAsset? ownAvatar;
  final String ownInitial;
  final MediaAsset? peerAvatar;
  final ValueChanged<String?> onAvatarTap;
  final Key Function(int sequence) keyForSequence;
  final ValueChanged<String> onRetry;
  final Future<bool> Function() onLoadEarlier;
  final Future<bool> Function() onLoadLater;

  @override
  Widget build(BuildContext context) {
    if (state.isLoading && state.messages.isEmpty) {
      return ListView(
        key: const ValueKey('chat-stable-loading-surface'),
        controller: controller,
      );
    }
    if (state.messages.isEmpty) {
      return const Center(
        child: Text('还没有消息，打个招呼吧', style: TextStyle(color: Color(0xFF78847E))),
      );
    }
    return ChatMessageTimeline(
      controller: controller,
      messages: state.messages,
      hasEarlier: state.hasEarlier,
      hasLater: state.hasLater,
      onLoadEarlier: onLoadEarlier,
      onLoadLater: onLoadLater,
      itemBuilder: (_, message, previous) =>
          _message(message, previous: previous),
    );
  }

  Widget _message(
    ConversationMessage message, {
    required ConversationMessage? previous,
  }) {
    final isMine = message.senderUserId == userId;
    final showTime = ChatTimePresentation.shouldShowDivider(
      message.createdAt,
      previous?.createdAt,
    );
    return KeyedSubtree(
      key: message.isPending
          ? ValueKey(message.messageId)
          : keyForSequence(message.sequence),
      child: ChatMessageBubble(
        text: message.previewText,
        deliveryState: message.deliveryState,
        isMine: isMine,
        avatar: isMine ? ownAvatar : peerAvatar ?? message.senderAvatar,
        avatarInitial: isMine ? ownInitial : _initial(message.senderName),
        onAvatarTap: () => onAvatarTap(message.senderUserId),
        timestampLabel: showTime
            ? ChatTimePresentation.format(message.createdAt)
            : null,
        onRetry: message.clientMessageId == null
            ? null
            : () => onRetry(message.clientMessageId!),
      ),
    );
  }

  String _initial(String value) {
    final normalized = value.trim();
    return normalized.isEmpty ? '友' : normalized.characters.first;
  }
}

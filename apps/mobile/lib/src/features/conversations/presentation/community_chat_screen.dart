import 'package:flutter/material.dart';

import '../../../core/navigation/app_navigation.dart';
import '../../nearby/presentation/nearby_ui.dart';
import '../application/conversation_sync_controller.dart';
import '../domain/community_chat_models.dart';
import '../domain/conversation_message.dart';
import 'chat_composer.dart';
import 'chat_message_bubble.dart';
import 'chat_message_timeline.dart';
import 'chat_time.dart';

class CommunityChatScreen extends StatelessWidget {
  const CommunityChatScreen({
    required this.channel,
    required this.sourceSection,
    required this.detailsRoute,
    required this.detailsBuilder,
    this.previewMessages = const [],
    super.key,
  });

  final CommunityChannelDescriptor channel;
  final AppSection sourceSection;
  final AppRouteId detailsRoute;
  final WidgetBuilder detailsBuilder;
  final List<CommunityMessagePreview> previewMessages;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: false,
      appBar: AppBar(
        title: Column(
          children: [
            Text(channel.title, style: const TextStyle(fontSize: 16)),
            Text(
              channel.subtitle,
              style: const TextStyle(
                color: Color(0xFF78847E),
                fontSize: 11,
                fontWeight: FontWeight.w400,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: _detailsTooltip(channel.kind),
            onPressed: () {
              AppNavigation.push<void>(
                context,
                destination: detailsRoute,
                source: AppNavigationSource(
                  section: sourceSection,
                  entryPoint: AppEntryPoint.channelChat,
                  routeId: _chatRoute(channel.kind),
                  entityId: channel.id,
                ),
                builder: detailsBuilder,
              );
            },
            icon: const Icon(Icons.more_horiz_rounded),
          ),
        ],
      ),
      body: CommunityChatBody(
        channel: channel,
        previewMessages: previewMessages,
      ),
    );
  }
}

class CommunityChatBody extends StatefulWidget {
  const CommunityChatBody({
    required this.channel,
    this.previewMessages = const [],
    this.showPreviewNotice = true,
    this.liveState,
    this.currentUserId,
    this.onSend,
    this.onRetry,
    this.readOnlyMessage,
    this.bottomChromeHeight = 0,
    super.key,
  });

  final CommunityChannelDescriptor channel;
  final List<CommunityMessagePreview> previewMessages;
  final bool showPreviewNotice;
  final ConversationChatState? liveState;
  final String? currentUserId;
  final Future<bool> Function(String value)? onSend;
  final ValueChanged<String>? onRetry;
  final String? readOnlyMessage;
  final double bottomChromeHeight;

  @override
  State<CommunityChatBody> createState() => _CommunityChatBodyState();
}

class _CommunityChatBodyState extends State<CommunityChatBody> {
  final _textController = TextEditingController();
  final _focusNode = FocusNode();
  final _composerController = ChatComposerController();
  late final ChatTimelineViewportController _timelineController;
  bool _announcementVisible = true;

  @override
  void initState() {
    super.initState();
    _timelineController = ChatTimelineViewportController();
  }

  Future<void> _send() async {
    final send = widget.onSend;
    if (send == null) {
      _pending('发送消息');
      return;
    }
    final succeeded = await send(_textController.text);
    if (!mounted || !succeeded) return;
    _textController.clear();
    _timelineController.scrollToLatest(jump: true);
  }

  @override
  void didUpdateWidget(covariant CommunityChatBody oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.channel.id != widget.channel.id) {
      _textController.clear();
      _composerController.dismiss(_focusNode);
      _announcementVisible = true;
      return;
    }

    final oldMessages = oldWidget.liveState?.messages ?? const [];
    final newMessages = widget.liveState?.messages ?? const [];
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
  }

  String? _logicalMessageId(ConversationMessage? message) =>
      message?.clientMessageId ?? message?.messageId;

  @override
  void dispose() {
    _textController.dispose();
    _focusNode.dispose();
    _timelineController.dispose();
    _composerController.dispose();
    super.dispose();
  }

  void _pending(String action) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text('$action将在群聊纵切接入后启用')));
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        if (widget.showPreviewNotice)
          const NearbyPreviewNotice(text: '当前为交互预览，正式数据接入后替换为真实群聊'),
        if (_announcementVisible && widget.channel.announcement != null)
          _Announcement(
            text: widget.channel.announcement!,
            onClose: () => setState(() => _announcementVisible = false),
          ),
        Expanded(
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onTap: () => _composerController.dismiss(_focusNode),
            child: widget.liveState == null
                ? _previewMessages()
                : _liveMessages(widget.liveState!),
          ),
        ),
        if (widget.readOnlyMessage case final message?)
          _ChatReadOnlySurface(message: message)
        else
          ChatComposer(
            controller: _composerController,
            textController: _textController,
            focusNode: _focusNode,
            onSend: _send,
            onUnavailableAction: _pending,
            bottomChromeHeight: widget.bottomChromeHeight,
          ),
      ],
    );
  }

  String _initial(String value) {
    final normalized = value.trim();
    return normalized.isEmpty ? '友' : normalized.characters.first;
  }

  Widget _previewMessages() {
    if (widget.previewMessages.isEmpty) {
      return Center(
        child: Text(
          widget.channel.emptyMessage,
          style: const TextStyle(color: Color(0xFF78847E)),
        ),
      );
    }
    return ListView(
      key: ValueKey('community-chat-${widget.channel.id}'),
      padding: const EdgeInsets.fromLTRB(14, 18, 14, 16),
      children: [
        for (final message in widget.previewMessages)
          ChatMessageBubble(
            text: message.text,
            deliveryState: 'sent',
            isMine: message.isMine,
            avatarInitial: _initial(message.senderName),
            senderLabel: message.isMine ? null : message.senderName,
            onAvatarTap: () => _pending('用户资料'),
          ),
      ],
    );
  }

  Widget _liveMessages(ConversationChatState state) {
    if (state.isLoading && state.messages.isEmpty) {
      return const SizedBox.expand(
        key: ValueKey('community-chat-stable-loading-surface'),
      );
    }
    if (state.messages.isEmpty) {
      return Center(
        child: Text(
          state.errorMessage ?? widget.channel.emptyMessage,
          style: const TextStyle(color: Color(0xFF78847E)),
          textAlign: TextAlign.center,
        ),
      );
    }
    return ChatMessageTimeline(
      timelineKey: ValueKey('community-chat-${widget.channel.id}'),
      controller: _timelineController.scrollController,
      messages: state.messages,
      itemBuilder: (_, message, previous) =>
          _liveMessage(message, previous: previous),
    );
  }

  Widget _liveMessage(
    ConversationMessage message, {
    required ConversationMessage? previous,
  }) {
    final isMine = message.senderUserId == widget.currentUserId;
    final showTime = ChatTimePresentation.shouldShowDivider(
      message.createdAt,
      previous?.createdAt,
    );
    return ChatMessageBubble(
      text: message.previewText,
      deliveryState: message.deliveryState,
      isMine: isMine,
      avatar: message.senderAvatar,
      avatarInitial: _initial(message.senderName),
      senderLabel: isMine ? null : message.senderName,
      timestampLabel: showTime
          ? ChatTimePresentation.format(message.createdAt)
          : null,
      onAvatarTap: () => _pending('用户资料'),
      onRetry: message.clientMessageId == null || widget.onRetry == null
          ? null
          : () => widget.onRetry?.call(message.clientMessageId!),
    );
  }
}

class _ChatReadOnlySurface extends StatelessWidget {
  const _ChatReadOnlySurface({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const ValueKey('chat-read-only-surface'),
      constraints: const BoxConstraints(minHeight: 64),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Color(0xFFE5EAE7))),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(
            Icons.visibility_outlined,
            size: 18,
            color: Color(0xFF78847E),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Color(0xFF66736D), fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}

class _Announcement extends StatelessWidget {
  const _Announcement({required this.text, required this.onClose});

  final String text;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFFEAF4EF),
      padding: const EdgeInsets.fromLTRB(14, 8, 6, 8),
      child: Row(
        children: [
          const Text(
            '公告',
            style: TextStyle(
              color: Color(0xFF167A5B),
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12),
            ),
          ),
          IconButton(
            tooltip: '关闭公告',
            visualDensity: VisualDensity.compact,
            onPressed: onClose,
            icon: const Icon(Icons.close_rounded, size: 18),
          ),
        ],
      ),
    );
  }
}

AppRouteId _chatRoute(CommunityChannelKind kind) => switch (kind) {
  CommunityChannelKind.plaza => AppRouteId.plazaChat,
  CommunityChannelKind.place => AppRouteId.placeChat,
  CommunityChannelKind.activity => AppRouteId.activityChat,
};

String _detailsTooltip(CommunityChannelKind kind) => switch (kind) {
  CommunityChannelKind.plaza => '广场信息',
  CommunityChannelKind.place => '地点详情',
  CommunityChannelKind.activity => '活动详情',
};

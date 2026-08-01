import 'package:flutter/material.dart';

import '../../../core/navigation/app_navigation.dart';
import '../../nearby/presentation/nearby_ui.dart';
import '../domain/community_chat_models.dart';
import 'chat_composer.dart';
import 'chat_message_bubble.dart';

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
    super.key,
  });

  final CommunityChannelDescriptor channel;
  final List<CommunityMessagePreview> previewMessages;
  final bool showPreviewNotice;

  @override
  State<CommunityChatBody> createState() => _CommunityChatBodyState();
}

class _CommunityChatBodyState extends State<CommunityChatBody> {
  final _textController = TextEditingController();
  final _focusNode = FocusNode();
  final _composerController = ChatComposerController();
  bool _announcementVisible = true;

  @override
  void didUpdateWidget(covariant CommunityChatBody oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.channel.id != widget.channel.id) {
      _textController.clear();
      _composerController.dismiss(_focusNode);
      _announcementVisible = true;
    }
  }

  @override
  void dispose() {
    _textController.dispose();
    _focusNode.dispose();
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
            child: widget.previewMessages.isEmpty
                ? Center(
                    child: Text(
                      widget.channel.emptyMessage,
                      style: const TextStyle(color: Color(0xFF78847E)),
                    ),
                  )
                : ListView(
                    key: ValueKey('community-chat-${widget.channel.id}'),
                    padding: const EdgeInsets.fromLTRB(14, 18, 14, 16),
                    children: [
                      for (final message in widget.previewMessages)
                        ChatMessageBubble(
                          text: message.text,
                          deliveryState: 'sent',
                          isMine: message.isMine,
                          avatarInitial: _initial(message.senderName),
                          senderLabel: message.isMine
                              ? null
                              : message.senderName,
                          onAvatarTap: () => _pending('用户资料'),
                        ),
                    ],
                  ),
          ),
        ),
        ChatComposer(
          controller: _composerController,
          textController: _textController,
          focusNode: _focusNode,
          isSending: false,
          onSend: () async => _pending('发送消息'),
          onUnavailableAction: _pending,
        ),
      ],
    );
  }

  String _initial(String value) {
    final normalized = value.trim();
    return normalized.isEmpty ? '友' : normalized.characters.first;
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

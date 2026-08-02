import 'package:flutter/material.dart';

import '../domain/conversation_message.dart';

/// Owns the common viewport-following behavior used by all chat scenes.
///
/// It keeps the latest message visible while the keyboard changes the usable
/// height, but does not pull a user away from older messages they are reading.
class ChatTimelineViewportController with WidgetsBindingObserver {
  ChatTimelineViewportController() {
    WidgetsBinding.instance.addObserver(this);
  }

  final ScrollController scrollController = ScrollController();
  bool _disposed = false;

  bool get isNearLatest {
    if (!scrollController.hasClients) return true;
    final position = scrollController.position;
    return position.maxScrollExtent - position.pixels <= 96;
  }

  void scrollToLatest({bool jump = false}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_disposed || !scrollController.hasClients) return;
      final target = scrollController.position.maxScrollExtent;
      if (jump) {
        scrollController.jumpTo(target);
      } else {
        scrollController.animateTo(
          target,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  void didChangeMetrics() {
    if (isNearLatest) {
      scrollToLatest(jump: true);
    }
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    WidgetsBinding.instance.removeObserver(this);
    scrollController.dispose();
  }
}

typedef ChatTimelineItemBuilder =
    Widget Function(
      BuildContext context,
      ConversationMessage message,
      ConversationMessage? previous,
    );

/// Shared chronological layout for every conversation scene.
///
/// A normal (non-reversed) list keeps short conversations top-aligned. Screens
/// use their scroll controller to move to [ScrollPosition.maxScrollExtent]
/// when opening a long conversation or following newly sent messages.
class ChatMessageTimeline extends StatelessWidget {
  const ChatMessageTimeline({
    required this.messages,
    required this.controller,
    required this.itemBuilder,
    this.timelineKey,
    super.key,
  });

  final List<ConversationMessage> messages;
  final ScrollController controller;
  final ChatTimelineItemBuilder itemBuilder;
  final Key? timelineKey;

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      key: timelineKey,
      controller: controller,
      padding: const EdgeInsets.fromLTRB(14, 18, 14, 16),
      itemCount: messages.length,
      itemBuilder: (context, index) => itemBuilder(
        context,
        messages[index],
        index == 0 ? null : messages[index - 1],
      ),
    );
  }
}

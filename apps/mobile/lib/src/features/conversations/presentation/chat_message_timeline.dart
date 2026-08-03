import 'package:flutter/material.dart';

import '../domain/conversation_message.dart';

/// Owns the common viewport-following behavior used by all chat scenes.
///
/// It keeps the latest message visible while the keyboard changes the usable
/// height, but does not pull a user away from older messages they are reading.
class ChatTimelineViewportController {
  ChatTimelineViewportController();

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

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    scrollController.dispose();
  }
}

/// Keeps a near-bottom chat viewport anchored while its height changes.
///
/// Keyboard insets alter the list's content dimensions during layout. Doing
/// the correction here means the new position is chosen before the frame is
/// painted, instead of briefly showing an old offset and jumping afterwards.
class ChatTimelineScrollPhysics extends ScrollPhysics {
  const ChatTimelineScrollPhysics({
    super.parent,
    this.followLatestThreshold = 96,
  });

  final double followLatestThreshold;

  @override
  ChatTimelineScrollPhysics applyTo(ScrollPhysics? ancestor) {
    return ChatTimelineScrollPhysics(
      parent: buildParent(ancestor),
      followLatestThreshold: followLatestThreshold,
    );
  }

  @override
  double adjustPositionForNewDimensions({
    required ScrollMetrics oldPosition,
    required ScrollMetrics newPosition,
    required bool isScrolling,
    required double velocity,
  }) {
    final distanceFromLatest = oldPosition.maxScrollExtent - oldPosition.pixels;
    final shouldFollowLatest =
        !isScrolling &&
        distanceFromLatest >= 0 &&
        distanceFromLatest <= followLatestThreshold;
    if (shouldFollowLatest) {
      return (newPosition.maxScrollExtent - distanceFromLatest).clamp(
        newPosition.minScrollExtent,
        newPosition.maxScrollExtent,
      );
    }
    return super.adjustPositionForNewDimensions(
      oldPosition: oldPosition,
      newPosition: newPosition,
      isScrolling: isScrolling,
      velocity: velocity,
    );
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
class ChatMessageTimeline extends StatefulWidget {
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
  State<ChatMessageTimeline> createState() => _ChatMessageTimelineState();
}

class _ChatMessageTimelineState extends State<ChatMessageTimeline> {
  bool _initialPositionReady = false;

  @override
  void initState() {
    super.initState();
    _positionBeforeReveal();
  }

  @override
  void didUpdateWidget(covariant ChatMessageTimeline oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller ||
        (oldWidget.messages.isEmpty && widget.messages.isNotEmpty)) {
      _initialPositionReady = false;
      _positionBeforeReveal();
    }
  }

  void _positionBeforeReveal() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (widget.controller.hasClients) {
        widget.controller.jumpTo(widget.controller.position.maxScrollExtent);
      }
      setState(() => _initialPositionReady = true);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Opacity(
      key: const ValueKey('chat-timeline-initial-position-gate'),
      opacity: _initialPositionReady ? 1 : 0,
      child: ListView.builder(
        key: widget.timelineKey,
        controller: widget.controller,
        physics: ChatTimelineScrollPhysics(
          parent: ScrollConfiguration.of(context).getScrollPhysics(context),
        ),
        padding: const EdgeInsets.fromLTRB(14, 18, 14, 20),
        itemCount: widget.messages.length,
        itemBuilder: (context, index) => widget.itemBuilder(
          context,
          widget.messages[index],
          index == 0 ? null : widget.messages[index - 1],
        ),
      ),
    );
  }
}

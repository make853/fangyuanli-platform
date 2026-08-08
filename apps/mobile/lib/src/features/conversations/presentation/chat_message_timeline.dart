import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

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

  /// Reveals a variable-height message without requiring every timeline item
  /// to stay mounted. The first estimate uses sequence order, then visible
  /// keyed children refine the direction until the target is built.
  Future<BuildContext?> revealSequence({
    required List<ConversationMessage> messages,
    required int sequence,
    required Map<int, GlobalKey> keys,
  }) async {
    var target = keys[sequence]?.currentContext;
    if (target != null) return target;
    if (!scrollController.hasClients || messages.length <= 1) return null;
    final index = messages.indexWhere(
      (message) => !message.isPending && message.sequence == sequence,
    );
    if (index < 0) return null;

    var position = scrollController.position;
    var offset = position.maxScrollExtent * index / (messages.length - 1);
    for (var attempt = 0; attempt < 8; attempt += 1) {
      if (_disposed || !scrollController.hasClients) return null;
      position = scrollController.position;
      position.jumpTo(
        offset.clamp(position.minScrollExtent, position.maxScrollExtent),
      );
      await WidgetsBinding.instance.endOfFrame;
      target = keys[sequence]?.currentContext;
      if (target != null) return target;

      final visible = <int>[];
      for (final entry in keys.entries) {
        if (entry.value.currentContext != null) visible.add(entry.key);
      }
      if (visible.isEmpty) continue;
      visible.sort();
      final step = position.viewportDimension * 0.8;
      if (sequence < visible.first) {
        offset = position.pixels - step;
      } else if (sequence > visible.last) {
        offset = position.pixels + step;
      } else {
        break;
      }
    }
    return keys[sequence]?.currentContext;
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
    this.hasEarlier = false,
    this.hasLater = false,
    this.onLoadEarlier,
    this.onLoadLater,
    super.key,
  });

  final List<ConversationMessage> messages;
  final ScrollController controller;
  final ChatTimelineItemBuilder itemBuilder;
  final Key? timelineKey;
  final bool hasEarlier;
  final bool hasLater;
  final Future<bool> Function()? onLoadEarlier;
  final Future<bool> Function()? onLoadLater;

  @override
  State<ChatMessageTimeline> createState() => _ChatMessageTimelineState();
}

class _ChatMessageTimelineState extends State<ChatMessageTimeline> {
  static const _maxInitialPositionPasses = 4;
  static const _positionEpsilon = 0.5;

  bool _initialPositionReady = false;
  int _positionRequest = 0;
  bool _requestingEarlier = false;
  bool _requestingLater = false;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_handleScroll);
    _positionBeforeReveal();
  }

  @override
  void didUpdateWidget(covariant ChatMessageTimeline oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_handleScroll);
      widget.controller.addListener(_handleScroll);
    }
    if (oldWidget.controller != widget.controller ||
        oldWidget.timelineKey != widget.timelineKey ||
        (oldWidget.messages.isEmpty && widget.messages.isNotEmpty)) {
      _positionBeforeReveal();
    }
  }

  void _handleScroll() {
    if (!widget.controller.hasClients || !_initialPositionReady) return;
    final position = widget.controller.position;
    if (position.userScrollDirection == ScrollDirection.idle) return;
    if (widget.hasEarlier && position.pixels <= 120) {
      _requestEarlier();
    }
    if (widget.hasLater && position.maxScrollExtent - position.pixels <= 120) {
      _requestLater();
    }
  }

  Future<void> _requestEarlier() async {
    final load = widget.onLoadEarlier;
    if (load == null || _requestingEarlier || !widget.controller.hasClients) {
      return;
    }
    _requestingEarlier = true;
    final oldPosition = widget.controller.position;
    final oldPixels = oldPosition.pixels;
    final oldMaxExtent = oldPosition.maxScrollExtent;
    try {
      final changed = await load();
      if (!changed || !mounted) return;
      await WidgetsBinding.instance.endOfFrame;
      if (!mounted || !widget.controller.hasClients) return;
      final newPosition = widget.controller.position;
      final target = oldPixels + newPosition.maxScrollExtent - oldMaxExtent;
      widget.controller.jumpTo(
        target.clamp(newPosition.minScrollExtent, newPosition.maxScrollExtent),
      );
    } finally {
      _requestingEarlier = false;
    }
  }

  Future<void> _requestLater() async {
    final load = widget.onLoadLater;
    if (load == null || _requestingLater) return;
    _requestingLater = true;
    try {
      await load();
    } finally {
      _requestingLater = false;
    }
  }

  void _positionBeforeReveal() {
    _initialPositionReady = false;
    final request = ++_positionRequest;
    _settleAtLatest(
      request: request,
      remainingPasses: _maxInitialPositionPasses,
    );
  }

  void _settleAtLatest({
    required int request,
    required int remainingPasses,
    double? previousMaxExtent,
  }) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || request != _positionRequest) return;
      if (!widget.controller.hasClients ||
          !widget.controller.position.hasContentDimensions) {
        if (remainingPasses > 1) {
          _scheduleNextPositionPass(
            request: request,
            remainingPasses: remainingPasses - 1,
            previousMaxExtent: previousMaxExtent,
          );
          return;
        }
        setState(() => _initialPositionReady = true);
        return;
      }

      final position = widget.controller.position;
      final target = position.maxScrollExtent;
      if ((position.pixels - target).abs() > _positionEpsilon) {
        widget.controller.jumpTo(target);
      }

      final extentIsStable =
          previousMaxExtent != null &&
          (target - previousMaxExtent).abs() <= _positionEpsilon;
      if (extentIsStable || remainingPasses <= 1) {
        setState(() => _initialPositionReady = true);
        return;
      }

      _scheduleNextPositionPass(
        request: request,
        remainingPasses: remainingPasses - 1,
        previousMaxExtent: target,
      );
    });
  }

  void _scheduleNextPositionPass({
    required int request,
    required int remainingPasses,
    required double? previousMaxExtent,
  }) {
    _settleAtLatest(
      request: request,
      remainingPasses: remainingPasses,
      previousMaxExtent: previousMaxExtent,
    );
    WidgetsBinding.instance.scheduleFrame();
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

  @override
  void dispose() {
    widget.controller.removeListener(_handleScroll);
    super.dispose();
  }
}

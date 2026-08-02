import 'package:flutter/material.dart';

import '../domain/conversation_message.dart';

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

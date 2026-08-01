import 'package:flutter/material.dart';

import '../../media/domain/media_upload_models.dart';
import '../../profile/presentation/profile_media_widgets.dart';
import '../domain/direct_message.dart';

class ChatMessageBubble extends StatelessWidget {
  const ChatMessageBubble({
    required this.message,
    required this.isMine,
    required this.avatarInitial,
    this.avatar,
    this.onAvatarTap,
    super.key,
  });

  final DirectMessage message;
  final bool isMine;
  final String avatarInitial;
  final MediaAsset? avatar;
  final VoidCallback? onAvatarTap;

  @override
  Widget build(BuildContext context) {
    final avatarWidget = _MessageAvatar(
      key: ValueKey(isMine ? 'message-avatar-mine' : 'message-avatar-peer'),
      media: avatar,
      initial: avatarInitial,
      onTap: onAvatarTap,
    );
    final bubble = Flexible(
      child: Column(
        crossAxisAlignment: isMine
            ? CrossAxisAlignment.end
            : CrossAxisAlignment.start,
        children: [
          DecoratedBox(
            key: const ValueKey('message-bubble'),
            decoration: BoxDecoration(
              color: isMine ? const Color(0xFFBDE9D6) : const Color(0xFFFFFFFF),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 10),
              child: Text(message.text),
            ),
          ),
          if (message.deliveryState == 'failed') ...[
            const SizedBox(height: 4),
            const Text(
              '发送失败',
              style: TextStyle(color: Color(0xFFB54842), fontSize: 11),
            ),
          ],
        ],
      ),
    );

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        mainAxisAlignment: isMine
            ? MainAxisAlignment.end
            : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: isMine
            ? [bubble, const SizedBox(width: 8), avatarWidget]
            : [avatarWidget, const SizedBox(width: 8), bubble],
      ),
    );
  }
}

class _MessageAvatar extends StatelessWidget {
  const _MessageAvatar({
    required this.media,
    required this.initial,
    required this.onTap,
    super.key,
  });

  final MediaAsset? media;
  final String initial;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: ProfileAvatarImage(
          media: media,
          initial: initial,
          size: 38,
          borderRadius: 12,
        ),
      ),
    );
  }
}

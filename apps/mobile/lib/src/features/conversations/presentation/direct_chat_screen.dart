import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../friends/application/friends_controller.dart';
import '../../friends/domain/friend_models.dart';
import '../../friends/presentation/friend_profile_screen.dart';
import '../../media/domain/media_upload_models.dart';
import '../../profile/application/profile_controller.dart';
import '../../profile/data/profile_repository.dart';
import '../../profile/presentation/profile_detail_screen.dart';
import '../application/direct_chat_controller.dart';
import 'chat_composer.dart';
import 'chat_message_bubble.dart';

class DirectChatScreen extends ConsumerStatefulWidget {
  const DirectChatScreen({
    required this.conversationId,
    required this.title,
    required this.currentUserId,
    super.key,
  });

  final String conversationId;
  final String title;
  final String currentUserId;

  @override
  ConsumerState<DirectChatScreen> createState() => _DirectChatScreenState();
}

class _DirectChatScreenState extends ConsumerState<DirectChatScreen> {
  final _textController = TextEditingController();
  final _focusNode = FocusNode();
  final _scrollController = ScrollController();
  final _composerController = ChatComposerController();

  @override
  void dispose() {
    _textController.dispose();
    _focusNode.dispose();
    _scrollController.dispose();
    _composerController.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final value = _textController.text;
    final succeeded = await ref
        .read(directChatControllerProvider(widget.conversationId).notifier)
        .send(value);
    if (!mounted) return;
    if (succeeded) {
      _textController.clear();
      _focusNode.requestFocus();
      _scrollToLatest();
    }
  }

  void _scrollToLatest() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) return;
      _scrollController.animateTo(
        0,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
      );
    });
  }

  void _showUnavailableAction(String action) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text('$action将在聊天媒体链路中接入')));
  }

  void _openProfile(String? userId) {
    if (userId == null) return;
    if (userId == widget.currentUserId) {
      Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => const MyProfileDetailScreen()),
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
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => FriendProfileScreen(initialContact: contact!),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final provider = directChatControllerProvider(widget.conversationId);
    final state = ref.watch(provider);
    final ownProfile = ref.watch(profileControllerProvider).profile;
    String? peerUserId;
    for (final message in state.messages) {
      if (message.senderUserId != null &&
          message.senderUserId != widget.currentUserId) {
        peerUserId = message.senderUserId;
        break;
      }
    }
    final peerProfile = peerUserId == null
        ? null
        : ref.watch(userProfileProvider(peerUserId)).asData?.value;

    ref.listen(provider, (previous, next) {
      if (next.errorMessage != null &&
          next.errorMessage != previous?.errorMessage) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text(next.errorMessage!)));
      }
    });

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        actions: [
          IconButton(
            tooltip: '刷新消息',
            onPressed: state.isLoading
                ? null
                : ref.read(provider.notifier).load,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTap: () => _composerController.dismiss(_focusNode),
              child: _MessageList(
                state: state,
                userId: widget.currentUserId,
                controller: _scrollController,
                ownAvatar: ownProfile?.avatar,
                ownInitial: ownProfile?.initial ?? '我',
                peerAvatar: peerProfile?.avatar,
                onAvatarTap: _openProfile,
              ),
            ),
          ),
          ChatComposer(
            controller: _composerController,
            textController: _textController,
            focusNode: _focusNode,
            isSending: state.isSending,
            onSend: _send,
            onUnavailableAction: _showUnavailableAction,
          ),
        ],
      ),
    );
  }
}

class _MessageList extends StatelessWidget {
  const _MessageList({
    required this.state,
    required this.userId,
    required this.controller,
    required this.ownInitial,
    required this.onAvatarTap,
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

  @override
  Widget build(BuildContext context) {
    if (state.isLoading && state.messages.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (state.messages.isEmpty) {
      return const Center(
        child: Text('还没有消息，打个招呼吧', style: TextStyle(color: Color(0xFF78847E))),
      );
    }
    return ListView.builder(
      controller: controller,
      reverse: true,
      padding: const EdgeInsets.fromLTRB(14, 18, 14, 16),
      itemCount: state.messages.length,
      itemBuilder: (context, index) {
        final message = state.messages[state.messages.length - 1 - index];
        final isMine = message.senderUserId == userId;
        return ChatMessageBubble(
          message: message,
          isMine: isMine,
          avatar: isMine ? ownAvatar : peerAvatar,
          avatarInitial: isMine ? ownInitial : _initial(message.senderName),
          onAvatarTap: () => onAvatarTap(message.senderUserId),
        );
      },
    );
  }

  String _initial(String value) {
    final normalized = value.trim();
    return normalized.isEmpty ? '友' : normalized.characters.first;
  }
}

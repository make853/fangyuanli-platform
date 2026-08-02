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
import '../domain/direct_message.dart';
import 'chat_composer.dart';
import 'chat_message_bubble.dart';
import 'chat_time.dart';
import 'direct_chat_settings_screen.dart';

class DirectChatScreen extends ConsumerStatefulWidget {
  const DirectChatScreen({
    required this.conversationId,
    required this.title,
    required this.currentUserId,
    this.peerUserId,
    this.peerAvatar,
    super.key,
  });

  final String conversationId;
  final String title;
  final String currentUserId;
  final String? peerUserId;
  final MediaAsset? peerAvatar;

  @override
  ConsumerState<DirectChatScreen> createState() => _DirectChatScreenState();
}

class _DirectChatScreenState extends ConsumerState<DirectChatScreen> {
  final _textController = TextEditingController();
  final _focusNode = FocusNode();
  final _scrollController = ScrollController();
  final _composerController = ChatComposerController();
  final _messageKeys = <int, GlobalKey>{};

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
    final target = _messageKeys[sequence]?.currentContext;
    if (target == null) {
      _showUnavailableAction('该条聊天记录定位');
      return;
    }
    if (!target.mounted) return;
    await Scrollable.ensureVisible(
      target,
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOut,
      alignment: 0.25,
    );
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
    });

    return Scaffold(
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
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTap: () => _composerController.dismiss(_focusNode),
              child: _MessageList(
                state: state,
                userId: widget.currentUserId,
                controller: _scrollController,
                ownAvatar: ownProfile?.avatar,
                ownInitial: ownProfile?.initial ?? '我',
                peerAvatar: currentContact?.avatar ?? widget.peerAvatar,
                onAvatarTap: _openProfile,
                keyForSequence: (sequence) =>
                    _messageKeys.putIfAbsent(sequence, GlobalKey.new),
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
    required this.keyForSequence,
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
    return ListView(
      controller: controller,
      reverse: true,
      padding: const EdgeInsets.fromLTRB(14, 18, 14, 16),
      children: [
        for (var index = state.messages.length - 1; index >= 0; index--)
          _message(
            state.messages[index],
            previous: index == 0 ? null : state.messages[index - 1],
          ),
      ],
    );
  }

  Widget _message(DirectMessage message, {required DirectMessage? previous}) {
    final isMine = message.senderUserId == userId;
    final showTime = ChatTimePresentation.shouldShowDivider(
      message.createdAt,
      previous?.createdAt,
    );
    return KeyedSubtree(
      key: keyForSequence(message.sequence),
      child: ChatMessageBubble(
        text: message.text,
        deliveryState: message.deliveryState,
        isMine: isMine,
        avatar: isMine ? ownAvatar : peerAvatar ?? message.senderAvatar,
        avatarInitial: isMine ? ownInitial : _initial(message.senderName),
        onAvatarTap: () => onAvatarTap(message.senderUserId),
        timestampLabel: showTime
            ? ChatTimePresentation.format(message.createdAt)
            : null,
      ),
    );
  }

  String _initial(String value) {
    final normalized = value.trim();
    return normalized.isEmpty ? '友' : normalized.characters.first;
  }
}

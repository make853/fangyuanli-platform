import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../application/direct_chat_controller.dart';
import '../domain/direct_message.dart';

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

  @override
  void dispose() {
    _textController.dispose();
    _focusNode.dispose();
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
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = directChatControllerProvider(widget.conversationId);
    final state = ref.watch(provider);

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
            child: _MessageList(state: state, userId: widget.currentUserId),
          ),
          _Composer(
            controller: _textController,
            focusNode: _focusNode,
            isSending: state.isSending,
            onSend: _send,
          ),
        ],
      ),
    );
  }
}

class _MessageList extends StatelessWidget {
  const _MessageList({required this.state, required this.userId});

  final DirectChatState state;
  final String userId;

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
      reverse: true,
      padding: const EdgeInsets.fromLTRB(14, 18, 14, 16),
      itemCount: state.messages.length,
      itemBuilder: (context, index) {
        final message = state.messages[state.messages.length - 1 - index];
        return _MessageBubble(
          message: message,
          isMine: message.senderUserId == userId,
        );
      },
    );
  }
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({required this.message, required this.isMine});

  final DirectMessage message;
  final bool isMine;

  @override
  Widget build(BuildContext context) {
    final bubbleColor = isMine
        ? const Color(0xFFBDE9D6)
        : const Color(0xFFFFFFFF);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        mainAxisAlignment: isMine
            ? MainAxisAlignment.end
            : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!isMine) ...[
            CircleAvatar(
              radius: 18,
              backgroundColor: const Color(0xFFDDEEE7),
              child: Text(
                message.senderName.trim().isEmpty
                    ? '友'
                    : message.senderName.trim().characters.first,
                style: const TextStyle(
                  color: Color(0xFF167A5B),
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(width: 8),
          ],
          Flexible(
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: bubbleColor,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 13,
                  vertical: 10,
                ),
                child: Text(message.text),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Composer extends StatelessWidget {
  const _Composer({
    required this.controller,
    required this.focusNode,
    required this.isSending,
    required this.onSend,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final bool isSending;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Material(
        color: const Color(0xFFF5F7F6),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
          child: Row(
            children: [
              const Icon(Icons.mic_none_rounded, color: Color(0xFF35433D)),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: controller,
                  focusNode: focusNode,
                  minLines: 1,
                  maxLines: 4,
                  textInputAction: TextInputAction.send,
                  onSubmitted: isSending ? null : (_) => onSend(),
                  decoration: const InputDecoration(
                    hintText: '输入消息',
                    filled: true,
                    fillColor: Colors.white,
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: 13,
                      vertical: 10,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                tooltip: '发送',
                onPressed: isSending ? null : onSend,
                icon: isSending
                    ? const SizedBox.square(
                        dimension: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.send_rounded),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

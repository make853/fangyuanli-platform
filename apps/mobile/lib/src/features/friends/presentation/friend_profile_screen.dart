import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/application/auth_controller.dart';
import '../../conversations/presentation/direct_chat_screen.dart';
import '../application/friends_controller.dart';
import '../domain/friend_models.dart';

class FriendProfileScreen extends ConsumerWidget {
  const FriendProfileScreen({required this.initialContact, super.key});

  final FriendContact initialContact;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(friendsControllerProvider);
    final contact = _currentContact(state);
    final isProcessing = state.processingUserIds.contains(contact.userId);

    return Scaffold(
      appBar: AppBar(title: const Text('好友资料')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
        children: [
          _ProfileHeader(contact: contact),
          const SizedBox(height: 14),
          FilledButton.icon(
            onPressed: contact.directConversationId.isEmpty
                ? null
                : () => _openChat(context, ref, contact),
            icon: const Icon(Icons.chat_bubble_outline_rounded),
            label: const Text('发消息'),
          ),
          const SizedBox(height: 14),
          _SettingsCard(
            children: [
              ListTile(
                title: const Text('编辑备注'),
                subtitle: Text(contact.remarkName ?? '未设置'),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: isProcessing
                    ? null
                    : () => _editRemark(context, ref, contact),
              ),
              const Divider(height: 1, indent: 16, endIndent: 16),
              ListTile(
                title: const Text('设置权限'),
                subtitle: Text(
                  contact.canViewMyPosts ? '允许查看我的动态信息、聊天' : '仅聊天',
                ),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: isProcessing
                    ? null
                    : () => _editPermission(context, ref, contact),
              ),
              const Divider(height: 1, indent: 16, endIndent: 16),
              SwitchListTile(
                title: const Text('置顶聊天'),
                subtitle: const Text('置顶后显示在普通和系统会话上方'),
                value: contact.pinned,
                onChanged: isProcessing
                    ? null
                    : (value) =>
                          _updatePinned(context, ref, contact.userId, value),
              ),
            ],
          ),
          const SizedBox(height: 14),
          _SettingsCard(
            children: [
              ListTile(
                title: const Text(
                  '删除好友',
                  style: TextStyle(color: Color(0xFFB54842)),
                ),
                onTap: isProcessing
                    ? null
                    : () => _deleteFriend(context, ref, contact),
              ),
              const Divider(height: 1, indent: 16, endIndent: 16),
              ListTile(
                title: const Text(
                  '加入黑名单',
                  style: TextStyle(color: Color(0xFFB54842)),
                ),
                subtitle: const Text('对方将无法向你发送消息'),
                onTap: isProcessing
                    ? null
                    : () => _blockUser(context, ref, contact),
              ),
            ],
          ),
          if (isProcessing) ...[
            const SizedBox(height: 18),
            const Center(child: CircularProgressIndicator()),
          ],
        ],
      ),
    );
  }

  FriendContact _currentContact(FriendsState state) {
    for (final contact in state.contacts) {
      if (contact.userId == initialContact.userId) return contact;
    }
    return initialContact;
  }

  void _openChat(BuildContext context, WidgetRef ref, FriendContact contact) {
    final userId = ref.read(authControllerProvider).session?.userId;
    if (userId == null) return;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) =>
            DirectChatScreen(contact: contact, currentUserId: userId),
      ),
    );
  }

  Future<void> _editRemark(
    BuildContext context,
    WidgetRef ref,
    FriendContact contact,
  ) async {
    final value = await showDialog<String>(
      context: context,
      builder: (_) => _RemarkDialog(initialValue: contact.remarkName ?? ''),
    );
    if (value == null || !context.mounted) return;
    final succeeded = await ref
        .read(friendsControllerProvider.notifier)
        .updateRemark(contact.userId, value);
    if (!context.mounted) return;
    _showResult(context, ref, succeeded, '备注已更新');
  }

  Future<void> _editPermission(
    BuildContext context,
    WidgetRef ref,
    FriendContact contact,
  ) async {
    final value = await showModalBottomSheet<bool>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 4, 20, 12),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  '设置权限',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
                ),
              ),
            ),
            RadioGroup<bool>(
              groupValue: contact.canViewMyPosts,
              onChanged: (value) => Navigator.pop(context, value),
              child: const Column(
                children: [
                  ListTile(
                    title: Text('允许查看我的动态信息、聊天'),
                    leading: Radio<bool>(value: true),
                  ),
                  ListTile(
                    title: Text('仅聊天'),
                    leading: Radio<bool>(value: false),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
    if (value == null || !context.mounted) return;
    final succeeded = await ref
        .read(friendsControllerProvider.notifier)
        .updatePostPermission(contact.userId, value);
    if (!context.mounted) return;
    _showResult(context, ref, succeeded, '权限已更新');
  }

  Future<void> _updatePinned(
    BuildContext context,
    WidgetRef ref,
    String userId,
    bool pinned,
  ) async {
    final succeeded = await ref
        .read(friendsControllerProvider.notifier)
        .updatePinned(userId, pinned);
    if (!context.mounted) return;
    _showResult(context, ref, succeeded, pinned ? '已置顶聊天' : '已取消置顶');
  }

  Future<void> _deleteFriend(
    BuildContext context,
    WidgetRef ref,
    FriendContact contact,
  ) async {
    final confirmed = await _confirm(
      context,
      title: '删除好友？',
      message: '删除后双方将不能继续私聊。此操作不会拉黑对方。',
      action: '删除',
    );
    if (!confirmed || !context.mounted) return;
    final succeeded = await ref
        .read(friendsControllerProvider.notifier)
        .deleteFriend(contact.userId);
    if (!context.mounted) return;
    if (succeeded) {
      Navigator.pop(context);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('好友已删除')));
    } else {
      _showResult(context, ref, false, '');
    }
  }

  Future<void> _blockUser(
    BuildContext context,
    WidgetRef ref,
    FriendContact contact,
  ) async {
    final confirmed = await _confirm(
      context,
      title: '加入黑名单？',
      message: '加入后对方无法向你发送消息。以后可以在“账号与安全 → 黑名单”中解除。',
      action: '加入黑名单',
    );
    if (!confirmed || !context.mounted) return;
    final succeeded = await ref
        .read(friendsControllerProvider.notifier)
        .blockUser(contact.userId);
    if (!context.mounted) return;
    if (succeeded) {
      Navigator.pop(context);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('已加入黑名单')));
    } else {
      _showResult(context, ref, false, '');
    }
  }

  Future<bool> _confirm(
    BuildContext context, {
    required String title,
    required String message,
    required String action,
  }) async {
    return await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text(title),
            content: Text(message),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFFB54842),
                ),
                child: Text(action),
              ),
            ],
          ),
        ) ??
        false;
  }

  void _showResult(
    BuildContext context,
    WidgetRef ref,
    bool succeeded,
    String successMessage,
  ) {
    final message = succeeded
        ? successMessage
        : ref.read(friendsControllerProvider).errorMessage ?? '操作失败，请稍后重试';
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }
}

class _RemarkDialog extends StatefulWidget {
  const _RemarkDialog({required this.initialValue});

  final String initialValue;

  @override
  State<_RemarkDialog> createState() => _RemarkDialogState();
}

class _RemarkDialogState extends State<_RemarkDialog> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialValue);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('编辑备注'),
      content: TextField(
        controller: _controller,
        autofocus: true,
        maxLength: 64,
        decoration: const InputDecoration(hintText: '输入备注，留空可删除备注'),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, _controller.text),
          child: const Text('保存'),
        ),
      ],
    );
  }
}

class _ProfileHeader extends StatelessWidget {
  const _ProfileHeader({required this.contact});

  final FriendContact contact;

  @override
  Widget build(BuildContext context) {
    final initial = contact.visibleName.trim().isEmpty
        ? '友'
        : contact.visibleName.trim().characters.first;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 34,
            backgroundColor: const Color(0xFFDDEEE7),
            child: Text(
              initial,
              style: const TextStyle(
                color: Color(0xFF167A5B),
                fontSize: 24,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  contact.visibleName,
                  style: const TextStyle(
                    fontSize: 21,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (contact.remarkName != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    '昵称：${contact.nickname}',
                    style: const TextStyle(color: Color(0xFF78847E)),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SettingsCard extends StatelessWidget {
  const _SettingsCard({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: Column(children: children),
    );
  }
}

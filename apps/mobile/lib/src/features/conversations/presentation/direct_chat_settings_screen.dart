import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/navigation/app_navigation.dart';
import '../../friends/application/friend_relationship_coordinator.dart';
import '../../friends/application/friends_controller.dart';
import '../../friends/domain/friend_models.dart';
import '../domain/direct_message.dart';

class DirectChatSettingsResult {
  const DirectChatSettingsResult._({
    this.sequence,
    this.closeConversation = false,
  });

  const DirectChatSettingsResult.locate(int sequence)
    : this._(sequence: sequence);

  const DirectChatSettingsResult.close() : this._(closeConversation: true);

  final int? sequence;
  final bool closeConversation;
}

class DirectChatSettingsScreen extends ConsumerWidget {
  const DirectChatSettingsScreen({
    required this.conversationId,
    required this.title,
    required this.messages,
    super.key,
  });

  final String conversationId;
  final String title;
  final List<DirectMessage> messages;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(friendsControllerProvider);
    final contact = _contactFor(state.contacts);
    final processing =
        contact != null && state.processingUserIds.contains(contact.userId);

    return Scaffold(
      appBar: AppBar(title: const Text('聊天设置')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
        children: [
          _SettingsCard(
            children: [
              ListTile(
                leading: const Icon(Icons.search_rounded),
                title: const Text('查找聊天记录'),
                subtitle: const Text('按内容、发送者或日期查找'),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => _openSearch(context),
              ),
              const Divider(height: 1, indent: 56, endIndent: 16),
              SwitchListTile(
                secondary: const Icon(Icons.push_pin_outlined),
                title: const Text('置顶聊天'),
                subtitle: Text(
                  contact?.pinned == true ? '已在消息列表顶部显示' : '在消息列表顶部显示',
                ),
                value: contact?.pinned ?? false,
                onChanged: contact == null || processing
                    ? null
                    : (value) => _updatePinned(context, ref, contact, value),
              ),
              const Divider(height: 1, indent: 56, endIndent: 16),
              ListTile(
                leading: const Icon(Icons.edit_outlined),
                title: const Text('编辑备注'),
                subtitle: Text(contact?.remarkName ?? '未设置'),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: contact == null || processing
                    ? null
                    : () => _editRemark(context, ref, contact),
              ),
              const Divider(height: 1, indent: 56, endIndent: 16),
              ListTile(
                leading: const Icon(Icons.shield_outlined),
                title: const Text('设置权限'),
                subtitle: Text(
                  contact == null
                      ? '好友资料加载中'
                      : contact.canViewMyPosts
                      ? '允许查看我的动态信息、聊天'
                      : '仅聊天',
                ),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: contact == null || processing
                    ? null
                    : () => _editPermission(context, ref, contact),
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
                onTap: contact == null || processing
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
                onTap: contact == null || processing
                    ? null
                    : () => _blockUser(context, ref, contact),
              ),
            ],
          ),
          if (contact == null) ...[
            const SizedBox(height: 12),
            const Text(
              '好友关系资料尚未加载完成，关系设置暂不可用。',
              textAlign: TextAlign.center,
              style: TextStyle(color: Color(0xFF78847E), fontSize: 12),
            ),
          ],
        ],
      ),
    );
  }

  FriendContact? _contactFor(List<FriendContact> contacts) {
    for (final contact in contacts) {
      if (contact.directConversationId == conversationId) return contact;
    }
    return null;
  }

  Future<void> _openSearch(BuildContext context) async {
    final sequence = await AppNavigation.push<int>(
      context,
      destination: AppRouteId.chatHistorySearch,
      source: AppNavigationSource(
        section: AppSection.friends,
        entryPoint: AppEntryPoint.settings,
        routeId: AppRouteId.directChatSettings,
        entityId: conversationId,
      ),
      builder: (_) =>
          ChatHistorySearchScreen(conversationTitle: title, messages: messages),
    );
    if (sequence == null || !context.mounted) return;
    Navigator.pop(context, DirectChatSettingsResult.locate(sequence));
  }

  Future<void> _updatePinned(
    BuildContext context,
    WidgetRef ref,
    FriendContact contact,
    bool value,
  ) async {
    final succeeded = await ref
        .read(friendRelationshipCoordinatorProvider)
        .updatePinned(contact.userId, value);
    if (!context.mounted) return;
    _showResult(context, ref, succeeded, value ? '已置顶聊天' : '已取消置顶');
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
        .read(friendRelationshipCoordinatorProvider)
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
        .read(friendRelationshipCoordinatorProvider)
        .updatePostPermission(contact.userId, value);
    if (!context.mounted) return;
    _showResult(context, ref, succeeded, '权限已更新');
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
        .read(friendRelationshipCoordinatorProvider)
        .deleteFriend(contact);
    if (!context.mounted) return;
    if (!succeeded) {
      _showResult(context, ref, false, '');
      return;
    }
    Navigator.pop(context, const DirectChatSettingsResult.close());
  }

  Future<void> _blockUser(
    BuildContext context,
    WidgetRef ref,
    FriendContact contact,
  ) async {
    final confirmed = await _confirm(
      context,
      title: '加入黑名单？',
      message: '加入后对方无法向你发送消息，以后可以在账号与安全中解除。',
      action: '加入黑名单',
    );
    if (!confirmed || !context.mounted) return;
    final succeeded = await ref
        .read(friendRelationshipCoordinatorProvider)
        .blockUser(contact);
    if (!context.mounted) return;
    if (!succeeded) {
      _showResult(context, ref, false, '');
      return;
    }
    Navigator.pop(context, const DirectChatSettingsResult.close());
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

class ChatHistorySearchScreen extends StatefulWidget {
  const ChatHistorySearchScreen({
    required this.conversationTitle,
    required this.messages,
    super.key,
  });

  final String conversationTitle;
  final List<DirectMessage> messages;

  @override
  State<ChatHistorySearchScreen> createState() =>
      _ChatHistorySearchScreenState();
}

class _ChatHistorySearchScreenState extends State<ChatHistorySearchScreen> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final query = _controller.text.trim().toLowerCase();
    final results = widget.messages.reversed.where((message) {
      if (query.isEmpty) return true;
      return message.text.toLowerCase().contains(query) ||
          message.senderName.toLowerCase().contains(query) ||
          _date(message.createdAt).contains(query);
    }).toList();

    return Scaffold(
      appBar: AppBar(title: const Text('查找聊天记录')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
            child: TextField(
              controller: _controller,
              autofocus: true,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                hintText: '搜索内容、发送者或日期',
                prefixIcon: Icon(Icons.search_rounded),
              ),
            ),
          ),
          Expanded(
            child: results.isEmpty
                ? const Center(
                    child: Text(
                      '没有找到相关聊天记录',
                      style: TextStyle(color: Color(0xFF78847E)),
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(12, 4, 12, 24),
                    itemCount: results.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final message = results[index];
                      final name = message.senderName.trim().isEmpty
                          ? '用户'
                          : message.senderName;
                      return ListTile(
                        leading: CircleAvatar(
                          backgroundColor: const Color(0xFFDDEEE7),
                          child: Text(name.characters.first),
                        ),
                        title: Row(
                          children: [
                            Expanded(child: Text(name)),
                            Text(
                              _date(message.createdAt),
                              style: const TextStyle(
                                color: Color(0xFF8B9691),
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ),
                        subtitle: Text(
                          message.text,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        onTap: () => Navigator.pop(context, message.sequence),
                      );
                    },
                  ),
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 8, 16, 14),
            child: Text(
              '当前搜索已加载到本机的聊天记录，完整服务端历史搜索将在后续接入。',
              textAlign: TextAlign.center,
              style: TextStyle(color: Color(0xFF8B9691), fontSize: 11),
            ),
          ),
        ],
      ),
    );
  }

  String _date(DateTime value) {
    final month = value.month.toString().padLeft(2, '0');
    final day = value.day.toString().padLeft(2, '0');
    return '${value.year}-$month-$day';
  }
}

class _SettingsCard extends StatelessWidget {
  const _SettingsCard({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(children: children),
    );
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

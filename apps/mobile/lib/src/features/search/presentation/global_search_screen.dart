import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/navigation/app_navigation.dart';
import '../../auth/application/auth_controller.dart';
import '../../conversations/application/conversation_list_controller.dart';
import '../../conversations/presentation/direct_chat_screen.dart';
import '../../friends/application/friends_controller.dart';
import '../../friends/domain/friend_models.dart';
import '../../friends/presentation/friend_profile_screen.dart';
import '../../friends/presentation/friend_requests_screen.dart';
import '../../friends/presentation/system_inbox_screen.dart';
import '../application/global_search_index.dart';
import '../domain/global_search_models.dart';

class GlobalSearchScreen extends ConsumerStatefulWidget {
  const GlobalSearchScreen({required this.sourceSection, super.key});

  final AppSection sourceSection;

  @override
  ConsumerState<GlobalSearchScreen> createState() => _GlobalSearchScreenState();
}

class _GlobalSearchScreenState extends ConsumerState<GlobalSearchScreen> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  static const _index = GlobalSearchIndex();

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final friends = ref.watch(friendsControllerProvider);
    final conversations = ref.watch(conversationListControllerProvider);
    final groups = _index.search(
      query: _controller.text,
      contacts: friends.contacts,
      conversations: conversations.items,
    );
    final hasQuery = normalizeSearchText(_controller.text).isNotEmpty;

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: TextField(
          key: const ValueKey('global-search-field'),
          controller: _controller,
          focusNode: _focusNode,
          autofocus: true,
          textInputAction: TextInputAction.search,
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
            hintText: '搜索',
            prefixIcon: const Icon(Icons.search_rounded, size: 21),
            suffixIcon: _controller.text.isEmpty
                ? null
                : IconButton(
                    tooltip: '清除',
                    onPressed: () {
                      _controller.clear();
                      setState(() {});
                      _focusNode.requestFocus();
                    },
                    icon: const Icon(Icons.cancel_rounded, size: 19),
                  ),
            filled: true,
            fillColor: const Color(0xFFF0F3F1),
            isDense: true,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide.none,
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
        ],
      ),
      body: !hasQuery
          ? const SizedBox.shrink()
          : groups.isEmpty
          ? const Center(
              child: Text(
                '未找到相关内容',
                style: TextStyle(color: Color(0xFF78847E)),
              ),
            )
          : ListView.separated(
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 28),
              itemCount: groups.length,
              separatorBuilder: (_, _) => const SizedBox(height: 14),
              itemBuilder: (context, index) {
                final group = groups[index];
                return _SearchGroupCard(
                  group: group,
                  onOpen: (item) => _openItem(context, item),
                  onMore: group.hasMore ? () => _openAll(context, group) : null,
                );
              },
            ),
    );
  }

  void _openAll(BuildContext context, GlobalSearchGroup group) {
    final allItems = GlobalSearchIndex(previewLimit: 1000)
        .search(
          query: _controller.text,
          contacts: ref.read(friendsControllerProvider).contacts,
          conversations: ref.read(conversationListControllerProvider).items,
        )
        .where((candidate) => candidate.category == group.category)
        .expand((candidate) => candidate.items)
        .toList(growable: false);
    AppNavigation.push<void>(
      context,
      destination: AppRouteId.globalSearchCategory,
      source: AppNavigationSource(
        section: widget.sourceSection,
        entryPoint: AppEntryPoint.globalSearch,
        routeId: AppRouteId.globalSearch,
      ),
      builder: (_) => GlobalSearchCategoryScreen(
        category: group.category,
        items: allItems,
        onOpen: _openItem,
      ),
    );
  }

  void _openItem(BuildContext context, GlobalSearchItem item) {
    final source = AppNavigationSource(
      section: widget.sourceSection,
      entryPoint: AppEntryPoint.globalSearch,
      routeId: AppRouteId.globalSearch,
      entityId: item.id,
    );
    switch (item.category) {
      case GlobalSearchCategory.friends:
        final contact = _contact(item.id);
        if (contact == null) return;
        AppNavigation.push<void>(
          context,
          destination: AppRouteId.friendProfile,
          source: source,
          builder: (_) => FriendProfileScreen(initialContact: contact),
        );
      case GlobalSearchCategory.directMessages:
        final userId = ref.read(authControllerProvider).session?.userId;
        final conversationId = item.conversationId;
        if (userId == null || conversationId == null) return;
        AppNavigation.push<void>(
          context,
          destination: AppRouteId.directChat,
          source: source,
          builder: (_) => DirectChatScreen(
            conversationId: conversationId,
            title: item.title,
            currentUserId: userId,
          ),
        );
      case GlobalSearchCategory.systemConversations:
        if (item.id == 'friend_requests') {
          AppNavigation.push<void>(
            context,
            destination: AppRouteId.friendRequests,
            source: source,
            builder: (_) => const FriendRequestsScreen(),
          );
          return;
        }
        AppNavigation.push<void>(
          context,
          destination: AppRouteId.systemInbox,
          source: source,
          builder: (_) => SystemInboxScreen(
            title: item.title,
            emptyMessage: _systemEmptyMessage(item.id),
          ),
        );
    }
  }

  FriendContact? _contact(String userId) {
    for (final contact in ref.read(friendsControllerProvider).contacts) {
      if (contact.userId == userId) return contact;
    }
    return null;
  }

  String _systemEmptyMessage(String id) => switch (id) {
    'activity_notifications' => '暂无新的活动通知',
    'post_notifications' => '暂无新的动态通知',
    'activity_expectations' => '附近暂时没有匹配的活动',
    _ => '暂无新消息',
  };
}

class GlobalSearchCategoryScreen extends StatelessWidget {
  const GlobalSearchCategoryScreen({
    required this.category,
    required this.items,
    required this.onOpen,
    super.key,
  });

  final GlobalSearchCategory category;
  final List<GlobalSearchItem> items;
  final void Function(BuildContext context, GlobalSearchItem item) onOpen;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_categoryTitle(category))),
      body: ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 28),
        itemCount: items.length,
        separatorBuilder: (_, _) => const SizedBox(height: 8),
        itemBuilder: (context, index) => _SearchResultTile(
          item: items[index],
          onTap: () => onOpen(context, items[index]),
        ),
      ),
    );
  }
}

class _SearchGroupCard extends StatelessWidget {
  const _SearchGroupCard({
    required this.group,
    required this.onOpen,
    this.onMore,
  });

  final GlobalSearchGroup group;
  final ValueChanged<GlobalSearchItem> onOpen;
  final VoidCallback? onMore;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(18),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
            child: Text(
              _categoryTitle(group.category),
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
            ),
          ),
          for (var index = 0; index < group.items.length; index++) ...[
            _SearchResultTile(
              item: group.items[index],
              onTap: () => onOpen(group.items[index]),
            ),
            if (index != group.items.length - 1)
              const Divider(height: 1, indent: 60, endIndent: 16),
          ],
          if (onMore != null) ...[
            const Divider(height: 1),
            TextButton(
              onPressed: onMore,
              child: Text('查看更多${_categoryTitle(group.category)}'),
            ),
          ],
        ],
      ),
    );
  }
}

class _SearchResultTile extends StatelessWidget {
  const _SearchResultTile({required this.item, required this.onTap});

  final GlobalSearchItem item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final icon = switch (item.category) {
      GlobalSearchCategory.friends => Icons.person_rounded,
      GlobalSearchCategory.directMessages => Icons.chat_bubble_outline_rounded,
      GlobalSearchCategory.systemConversations => Icons.notifications_rounded,
    };
    return ListTile(
      onTap: onTap,
      leading: CircleAvatar(
        backgroundColor: const Color(0xFFDDEEE7),
        child: item.category == GlobalSearchCategory.friends
            ? Text(
                item.title.trim().isEmpty
                    ? '友'
                    : item.title.trim().characters.first,
                style: const TextStyle(
                  color: Color(0xFF167A5B),
                  fontWeight: FontWeight.w700,
                ),
              )
            : Icon(icon, color: const Color(0xFF167A5B), size: 21),
      ),
      title: Text(item.title),
      subtitle: item.subtitle.isEmpty
          ? null
          : Text(item.subtitle, maxLines: 2, overflow: TextOverflow.ellipsis),
      trailing: const Icon(Icons.chevron_right_rounded),
    );
  }
}

String _categoryTitle(GlobalSearchCategory category) => switch (category) {
  GlobalSearchCategory.friends => '好友',
  GlobalSearchCategory.directMessages => '好友聊天记录',
  GlobalSearchCategory.systemConversations => '系统消息',
};

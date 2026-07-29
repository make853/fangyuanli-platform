import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../application/friends_controller.dart';
import '../domain/friend_models.dart';
import 'friend_requests_screen.dart';

class FriendsScreen extends ConsumerStatefulWidget {
  const FriendsScreen({super.key});

  @override
  ConsumerState<FriendsScreen> createState() => _FriendsScreenState();
}

class _FriendsScreenState extends ConsumerState<FriendsScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(friendsControllerProvider);
    return Column(
      children: [
        Material(
          color: Colors.white,
          child: TabBar(
            controller: _tabController,
            tabs: const [
              Tab(text: '消息'),
              Tab(text: '联系人'),
            ],
          ),
        ),
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [
              _MessagesTab(state: state),
              _ContactsTab(state: state),
            ],
          ),
        ),
      ],
    );
  }
}

class _MessagesTab extends ConsumerWidget {
  const _MessagesTab({required this.state});

  final FriendsState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return RefreshIndicator(
      onRefresh: ref.read(friendsControllerProvider.notifier).load,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
        children: [
          if (state.isLoading && state.requests.isEmpty)
            const LinearProgressIndicator(minHeight: 2),
          if (state.errorMessage != null) ...[
            _InlineError(
              message: state.errorMessage!,
              onRetry: ref.read(friendsControllerProvider.notifier).load,
            ),
            const SizedBox(height: 12),
          ],
          _SystemMessageTile(
            title: '好友申请',
            subtitle: state.pendingRequestCount == 0
                ? '暂无新的好友申请'
                : '${state.pendingRequestCount} 条申请等待处理',
            icon: Icons.person_add_alt_1_rounded,
            iconColor: const Color(0xFF2F7D68),
            unreadCount: state.pendingRequestCount,
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const FriendRequestsScreen(),
                ),
              );
            },
          ),
          const SizedBox(height: 10),
          _SystemMessageTile(
            title: '活动通知',
            subtitle: '报名、审批和活动变更',
            icon: Icons.event_available_rounded,
            iconColor: const Color(0xFFE58A3A),
            onTap: () => _openEmptyInbox(context, '活动通知', '暂无新的活动通知'),
          ),
          const SizedBox(height: 10),
          _SystemMessageTile(
            title: '动态通知',
            subtitle: '点赞、评论和回复',
            icon: Icons.favorite_rounded,
            iconColor: const Color(0xFFE05C64),
            onTap: () => _openEmptyInbox(context, '动态通知', '暂无新的动态通知'),
          ),
          const SizedBox(height: 10),
          _SystemMessageTile(
            title: '发现期待活动',
            subtitle: '符合你爱好和关键词的活动',
            icon: Icons.auto_awesome_rounded,
            iconColor: const Color(0xFF6A77C7),
            onTap: () => _openEmptyInbox(context, '发现期待活动', '附近暂时没有匹配的活动'),
          ),
        ],
      ),
    );
  }

  void _openEmptyInbox(BuildContext context, String title, String message) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => _EmptyInboxScreen(title: title, message: message),
      ),
    );
  }
}

class _ContactsTab extends ConsumerWidget {
  const _ContactsTab({required this.state});

  final FriendsState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (state.isLoading && state.contacts.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    return RefreshIndicator(
      onRefresh: ref.read(friendsControllerProvider.notifier).load,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
        children: [
          if (state.errorMessage != null) ...[
            _InlineError(
              message: state.errorMessage!,
              onRetry: ref.read(friendsControllerProvider.notifier).load,
            ),
            const SizedBox(height: 12),
          ],
          if (state.contacts.isEmpty && state.errorMessage == null)
            const _EmptyContacts()
          else
            for (final contact in state.contacts) ...[
              _ContactTile(contact: contact),
              const SizedBox(height: 8),
            ],
        ],
      ),
    );
  }
}

class _SystemMessageTile extends StatelessWidget {
  const _SystemMessageTile({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.iconColor,
    required this.onTap,
    this.unreadCount = 0,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final Color iconColor;
  final VoidCallback onTap;
  final int unreadCount;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: iconColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, color: iconColor, size: 24),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        color: Color(0xFF78847E),
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
              if (unreadCount > 0)
                Container(
                  constraints: const BoxConstraints(minWidth: 21),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFE24A52),
                    borderRadius: BorderRadius.circular(11),
                  ),
                  child: Text(
                    unreadCount > 99 ? '99+' : '$unreadCount',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                )
              else
                const Icon(
                  Icons.chevron_right_rounded,
                  color: Color(0xFFA1AAA5),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ContactTile extends StatelessWidget {
  const _ContactTile({required this.contact});

  final FriendContact contact;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: contact.pinned ? const Color(0xFFE7EFEA) : Colors.white,
        borderRadius: BorderRadius.circular(15),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        children: [
          _InitialAvatar(name: contact.visibleName),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        contact.visibleName,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    if (contact.pinned) ...[
                      const SizedBox(width: 6),
                      const Icon(
                        Icons.push_pin_rounded,
                        size: 14,
                        color: Color(0xFF587067),
                      ),
                    ],
                  ],
                ),
                if (contact.remarkName != null &&
                    contact.remarkName!.trim().isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(
                    '昵称：${contact.displayName}',
                    style: const TextStyle(
                      color: Color(0xFF78847E),
                      fontSize: 12,
                    ),
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

class _InitialAvatar extends StatelessWidget {
  const _InitialAvatar({required this.name});

  final String name;

  @override
  Widget build(BuildContext context) {
    final initial = name.trim().isEmpty ? '友' : name.trim().characters.first;
    return CircleAvatar(
      radius: 22,
      backgroundColor: const Color(0xFFDDEEE7),
      child: Text(
        initial,
        style: const TextStyle(
          color: Color(0xFF167A5B),
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _EmptyContacts extends StatelessWidget {
  const _EmptyContacts();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.only(top: 92),
      child: Column(
        children: [
          Icon(
            Icons.people_outline_rounded,
            size: 42,
            color: Color(0xFFA1AAA5),
          ),
          SizedBox(height: 12),
          Text('还没有好友', style: TextStyle(fontWeight: FontWeight.w600)),
          SizedBox(height: 5),
          Text(
            '同意好友申请后，对方会出现在这里',
            style: TextStyle(color: Color(0xFF78847E), fontSize: 13),
          ),
        ],
      ),
    );
  }
}

class _InlineError extends StatelessWidget {
  const _InlineError({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF0ED),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.error_outline_rounded,
            color: Color(0xFFB84C42),
            size: 19,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(color: Color(0xFF8D4039), fontSize: 13),
            ),
          ),
          TextButton(onPressed: onRetry, child: const Text('重试')),
        ],
      ),
    );
  }
}

class _EmptyInboxScreen extends StatelessWidget {
  const _EmptyInboxScreen({required this.title, required this.message});

  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.notifications_none_rounded,
              size: 44,
              color: Color(0xFFA1AAA5),
            ),
            const SizedBox(height: 12),
            Text(message, style: const TextStyle(color: Color(0xFF78847E))),
          ],
        ),
      ),
    );
  }
}

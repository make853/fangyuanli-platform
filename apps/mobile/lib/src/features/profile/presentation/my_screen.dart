import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/application/auth_controller.dart';
import '../../friends/application/friends_controller.dart';
import '../../friends/domain/friend_models.dart';
import '../application/profile_controller.dart';
import 'privacy_screen.dart';
import 'profile_detail_screen.dart';

class MyScreen extends ConsumerWidget {
  const MyScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(authControllerProvider).session;
    final profileState = ref.watch(profileControllerProvider);
    final profile = profileState.profile;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 28),
      children: [
        Material(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const MyProfileDetailScreen(),
                ),
              );
            },
            child: Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(18),
              ),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 31,
                    backgroundColor: Color(0xFFDDEEE7),
                    child: profile == null
                        ? const Icon(
                            Icons.person_rounded,
                            color: Color(0xFF167A5B),
                            size: 31,
                          )
                        : Text(
                            profile.initial,
                            style: const TextStyle(
                              color: Color(0xFF167A5B),
                              fontSize: 22,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          profile?.nickname ?? '我的账号',
                          style: const TextStyle(
                            fontSize: 19,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          profile?.fangyuanNumber == null
                              ? session == null
                                    ? '登录状态读取中'
                                    : '手机号账号已登录'
                              : '方圆号：${profile!.fangyuanNumber}',
                          style: const TextStyle(
                            color: Color(0xFF78847E),
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Icon(Icons.chevron_right_rounded),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 14),
        Material(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          child: ListTile(
            leading: const Icon(Icons.shield_outlined),
            title: const Text('账号与安全'),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const AccountSecurityScreen(),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class AccountSecurityScreen extends ConsumerWidget {
  const AccountSecurityScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final blockCount = ref.watch(
      friendsControllerProvider.select((state) => state.blockedUsers.length),
    );
    return Scaffold(
      appBar: AppBar(title: const Text('账号与安全')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 28),
        children: [
          Material(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                ListTile(
                  title: const Text('隐私'),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const PrivacyScreen(),
                      ),
                    );
                  },
                ),
                const Divider(height: 1, indent: 16, endIndent: 16),
                ListTile(
                  title: const Text('黑名单'),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (blockCount > 0)
                        Text(
                          '$blockCount',
                          style: const TextStyle(color: Color(0xFF78847E)),
                        ),
                      const SizedBox(width: 5),
                      const Icon(Icons.chevron_right_rounded),
                    ],
                  ),
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const BlockListScreen(),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          FilledButton.tonal(
            onPressed: () async {
              await ref.read(authControllerProvider.notifier).logout();
              if (context.mounted) {
                Navigator.of(context).popUntil((route) => route.isFirst);
              }
            },
            style: FilledButton.styleFrom(
              foregroundColor: const Color(0xFFB54842),
            ),
            child: const Text('退出登录'),
          ),
        ],
      ),
    );
  }
}

class BlockListScreen extends ConsumerWidget {
  const BlockListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(friendsControllerProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('黑名单')),
      body: RefreshIndicator(
        onRefresh: ref.read(friendsControllerProvider.notifier).load,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 28),
          children: [
            if (state.isLoading && state.blockedUsers.isEmpty)
              const Padding(
                padding: EdgeInsets.only(top: 100),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (state.blockedUsers.isEmpty)
              const Padding(
                padding: EdgeInsets.only(top: 100),
                child: Center(
                  child: Column(
                    children: [
                      Icon(
                        Icons.person_off_outlined,
                        size: 42,
                        color: Color(0xFFA1AAA5),
                      ),
                      SizedBox(height: 12),
                      Text('黑名单为空', style: TextStyle(color: Color(0xFF78847E))),
                    ],
                  ),
                ),
              )
            else
              for (final blocked in state.blockedUsers) ...[
                _BlockedUserTile(
                  blocked: blocked,
                  processing: state.processingUserIds.contains(
                    blocked.target.userId,
                  ),
                  onUnblock: () => _unblock(context, ref, blocked),
                ),
                const SizedBox(height: 8),
              ],
          ],
        ),
      ),
    );
  }

  Future<void> _unblock(
    BuildContext context,
    WidgetRef ref,
    BlockedUser blocked,
  ) async {
    final confirmed =
        await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('移出黑名单？'),
            content: Text(
              blocked.priorRelation == PriorRelation.friend
                  ? '移出后将恢复原好友关系。'
                  : '移出后对方仍是陌生人。',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('移出'),
              ),
            ],
          ),
        ) ??
        false;
    if (!confirmed || !context.mounted) return;
    final succeeded = await ref
        .read(friendsControllerProvider.notifier)
        .unblockUser(blocked.target.userId);
    if (!context.mounted) return;
    final message = succeeded
        ? (blocked.priorRelation == PriorRelation.friend
              ? '已移出黑名单并恢复好友关系'
              : '已移出黑名单')
        : ref.read(friendsControllerProvider).errorMessage ?? '操作失败，请稍后重试';
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }
}

class _BlockedUserTile extends StatelessWidget {
  const _BlockedUserTile({
    required this.blocked,
    required this.processing,
    required this.onUnblock,
  });

  final BlockedUser blocked;
  final bool processing;
  final VoidCallback onUnblock;

  @override
  Widget build(BuildContext context) {
    final name = blocked.target.displayName;
    final initial = name.trim().isEmpty ? '友' : name.trim().characters.first;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(15),
      ),
      child: Row(
        children: [
          CircleAvatar(
            backgroundColor: const Color(0xFFEEF1EF),
            child: Text(
              initial,
              style: const TextStyle(color: Color(0xFF66736D)),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  blocked.priorRelation == PriorRelation.friend
                      ? '原好友关系'
                      : '原陌生人关系',
                  style: const TextStyle(
                    color: Color(0xFF78847E),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          TextButton(
            onPressed: processing ? null : onUnblock,
            child: processing
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('移出'),
          ),
        ],
      ),
    );
  }
}

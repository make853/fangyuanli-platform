import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/presentation/feature_entry.dart';
import '../../auth/application/auth_controller.dart';
import '../../friends/application/friends_controller.dart';
import '../../friends/domain/friend_models.dart';
import '../application/profile_controller.dart';
import 'privacy_screen.dart';
import 'profile_detail_screen.dart';

class MyScreen extends ConsumerWidget {
  const MyScreen({super.key});

  static const _contentEntries = [
    FeatureEntry(
      id: 'friend_posts',
      title: '好友动态',
      subtitle: '查看好友最近发布的动态',
      icon: Icons.dynamic_feed_outlined,
    ),
    FeatureEntry(
      id: 'my_activities',
      title: '我的活动',
      subtitle: '报名、创建和管理的活动',
      icon: Icons.event_available_outlined,
    ),
    FeatureEntry(
      id: 'managed_places',
      title: '我管理的地点',
      subtitle: '已认证或参与管理的地点群',
      icon: Icons.storefront_outlined,
    ),
  ];

  static const _nearbyEntries = [
    FeatureEntry(
      id: 'activity_expectations',
      title: '活动期待',
      subtitle: '有符合期待的活动时提醒我',
      icon: Icons.notifications_active_outlined,
    ),
    FeatureEntry(
      id: 'visit_history',
      title: '历史进入',
      subtitle: '仅自己可见',
      icon: Icons.history_rounded,
    ),
  ];

  static const _settingEntries = [
    FeatureEntry(id: 'help', title: '帮助与反馈', icon: Icons.help_outline_rounded),
    FeatureEntry(
      id: 'about',
      title: '关于方圆里',
      subtitle: 'staging · UI 基线 v0.73',
      icon: Icons.info_outline_rounded,
    ),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(authControllerProvider).session;
    final profileState = ref.watch(profileControllerProvider);
    final profile = profileState.profile;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
      children: [
        _MyProfileCard(
          nickname: profile?.nickname ?? '我的账号',
          signature: profile == null
              ? (session == null ? '登录状态读取中' : '手机号账号已登录')
              : (profile.signature.isEmpty ? '还没有填写个人签名' : profile.signature),
          initial: profile?.initial,
          onOpenProfile: () {
            Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const MyProfileDetailScreen(),
              ),
            );
          },
          onOpenQrCode: () => showFeatureComingSoon(context, '我的二维码'),
        ),
        const _SectionTitle('我的内容'),
        _FeatureSection(
          entries: _contentEntries,
          onTap: (entry) => showFeatureComingSoon(context, entry.title),
        ),
        const _SectionTitle('附近记录'),
        _FeatureSection(
          entries: _nearbyEntries,
          onTap: (entry) => showFeatureComingSoon(context, entry.title),
        ),
        const _SectionTitle('设置'),
        _FeatureSection(
          entries: [
            FeatureEntry(
              id: 'notifications',
              title: '消息通知与免打扰',
              subtitle: profileState.privacy?.globalGroupMuted == true
                  ? '已开启'
                  : '未开启',
              icon: Icons.notifications_none_rounded,
              availability: FeatureAvailability.available,
            ),
            const FeatureEntry(
              id: 'account_security',
              title: '账号与安全',
              icon: Icons.shield_outlined,
              availability: FeatureAvailability.available,
            ),
            ..._settingEntries,
          ],
          onTap: (entry) {
            if (entry.id == 'notifications') {
              _toggleGlobalGroupMute(context, ref);
              return;
            }
            if (entry.id == 'account_security') {
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const AccountSecurityScreen(),
                ),
              );
              return;
            }
            showFeatureComingSoon(context, entry.title);
          },
        ),
      ],
    );
  }

  Future<void> _toggleGlobalGroupMute(
    BuildContext context,
    WidgetRef ref,
  ) async {
    final current = ref.read(profileControllerProvider).privacy;
    if (current == null) {
      await ref.read(profileControllerProvider.notifier).load();
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('设置已刷新，请再试一次')));
      return;
    }
    final nextValue = !current.globalGroupMuted;
    final succeeded = await ref
        .read(profileControllerProvider.notifier)
        .updatePrivacy(globalGroupMuted: nextValue);
    if (!context.mounted) return;
    final message = succeeded
        ? (nextValue ? '群消息免打扰已开启' : '群消息免打扰已关闭')
        : ref.read(profileControllerProvider).errorMessage ?? '设置失败，请稍后重试';
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }
}

class _MyProfileCard extends StatelessWidget {
  const _MyProfileCard({
    required this.nickname,
    required this.signature,
    required this.initial,
    required this.onOpenProfile,
    required this.onOpenQrCode,
  });

  final String nickname;
  final String signature;
  final String? initial;
  final VoidCallback onOpenProfile;
  final VoidCallback onOpenQrCode;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(20),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onOpenProfile,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 18, 10, 18),
          child: Row(
            children: [
              Container(
                width: 64,
                height: 64,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: const Color(0xFFDDEEE7),
                  borderRadius: BorderRadius.circular(21),
                ),
                child: initial == null
                    ? const Icon(
                        Icons.person_rounded,
                        color: Color(0xFF167A5B),
                        size: 32,
                      )
                    : Text(
                        initial!,
                        style: const TextStyle(
                          color: Color(0xFF167A5B),
                          fontSize: 23,
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
                      nickname,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      signature,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFF78847E),
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                key: const ValueKey('my-profile-qr'),
                tooltip: '我的二维码',
                onPressed: onOpenQrCode,
                icon: const Icon(Icons.qr_code_2_rounded, size: 22),
              ),
              const Icon(Icons.chevron_right_rounded, color: Color(0xFFA1AAA5)),
            ],
          ),
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.title);

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 20, 4, 8),
      child: Text(
        title,
        style: const TextStyle(
          color: Color(0xFF66736D),
          fontSize: 13,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _FeatureSection extends StatelessWidget {
  const _FeatureSection({required this.entries, required this.onTap});

  final List<FeatureEntry> entries;
  final ValueChanged<FeatureEntry> onTap;

  @override
  Widget build(BuildContext context) {
    final visibleEntries = entries
        .where((entry) => entry.availability != FeatureAvailability.hidden)
        .toList();
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(17),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          for (var index = 0; index < visibleEntries.length; index++) ...[
            _FeatureTile(
              entry: visibleEntries[index],
              onTap: () => onTap(visibleEntries[index]),
            ),
            if (index != visibleEntries.length - 1)
              const Divider(height: 1, indent: 54, endIndent: 16),
          ],
        ],
      ),
    );
  }
}

class _FeatureTile extends StatelessWidget {
  const _FeatureTile({required this.entry, required this.onTap});

  final FeatureEntry entry;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      key: ValueKey('feature-entry-${entry.id}'),
      minLeadingWidth: 28,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
      leading: Icon(entry.icon, color: const Color(0xFF3A4942), size: 22),
      title: Text(entry.title),
      subtitle: entry.subtitle == null
          ? null
          : Text(
              entry.subtitle!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12),
            ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (entry.availability == FeatureAvailability.comingSoon)
            const Text(
              '开发中',
              style: TextStyle(color: Color(0xFFA1AAA5), fontSize: 12),
            ),
          const SizedBox(width: 4),
          const Icon(Icons.chevron_right_rounded, color: Color(0xFFA1AAA5)),
        ],
      ),
      onTap: onTap,
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

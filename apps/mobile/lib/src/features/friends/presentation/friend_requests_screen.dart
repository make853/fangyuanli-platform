import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/navigation/app_navigation.dart';
import '../../profile/presentation/profile_detail_screen.dart';
import '../application/friends_controller.dart';
import '../domain/friend_models.dart';

class FriendRequestsScreen extends ConsumerWidget {
  const FriendRequestsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(friendsControllerProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('好友申请')),
      body: RefreshIndicator(
        onRefresh: ref.read(friendsControllerProvider.notifier).load,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
          children: [
            if (state.isLoading && state.requests.isEmpty)
              const Padding(
                padding: EdgeInsets.only(top: 100),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (state.requests.isEmpty)
              const Padding(
                padding: EdgeInsets.only(top: 100),
                child: Center(
                  child: Text(
                    '暂无好友申请',
                    style: TextStyle(color: Color(0xFF78847E)),
                  ),
                ),
              )
            else
              for (final request in state.requests) ...[
                _RequestCard(
                  request: request,
                  isProcessing: state.processingRequestIds.contains(
                    request.requestId,
                  ),
                  onOpenProfile: () => _openProfile(context, request),
                  onDecision: (accept) =>
                      _decide(context, ref, request.requestId, accept),
                ),
                const SizedBox(height: 10),
              ],
          ],
        ),
      ),
    );
  }

  void _openProfile(BuildContext context, FriendRequest request) {
    AppNavigation.push<void>(
      context,
      destination: AppRouteId.userProfile,
      source: AppNavigationSource(
        section: AppSection.friends,
        entryPoint: AppEntryPoint.systemNotification,
        routeId: AppRouteId.friendRequests,
        entityId: request.requestId,
      ),
      builder: (_) => UserProfileDetailScreen(userId: request.sender.userId),
    );
  }

  Future<void> _decide(
    BuildContext context,
    WidgetRef ref,
    String requestId,
    bool accept,
  ) async {
    final succeeded = await ref
        .read(friendsControllerProvider.notifier)
        .decide(requestId: requestId, accept: accept);
    if (!context.mounted) return;
    final state = ref.read(friendsControllerProvider);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          succeeded
              ? (accept ? '已同意好友申请' : '已拒绝好友申请')
              : state.errorMessage ?? '操作失败，请稍后重试',
        ),
      ),
    );
  }
}

class _RequestCard extends StatelessWidget {
  const _RequestCard({
    required this.request,
    required this.isProcessing,
    required this.onOpenProfile,
    required this.onDecision,
  });

  final FriendRequest request;
  final bool isProcessing;
  final VoidCallback onOpenProfile;
  final ValueChanged<bool> onDecision;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Material(
            color: Colors.transparent,
            child: InkWell(
              key: ValueKey('friend-request-profile-${request.requestId}'),
              customBorder: const CircleBorder(),
              onTap: onOpenProfile,
              child: CircleAvatar(
                radius: 22,
                backgroundColor: const Color(0xFFDDEEE7),
                child: Text(
                  request.sender.displayName.trim().isEmpty
                      ? '友'
                      : request.sender.displayName.trim().characters.first,
                  style: const TextStyle(
                    color: Color(0xFF167A5B),
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        request.sender.displayName,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    _StatusBadge(status: request.status),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  request.applicationNote,
                  style: const TextStyle(
                    color: Color(0xFF66736D),
                    fontSize: 13,
                    height: 1.35,
                  ),
                ),
                if (request.status == FriendRequestStatus.pending) ...[
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      OutlinedButton(
                        onPressed: isProcessing
                            ? null
                            : () => onDecision(false),
                        child: const Text('拒绝'),
                      ),
                      const SizedBox(width: 10),
                      FilledButton(
                        onPressed: isProcessing ? null : () => onDecision(true),
                        style: FilledButton.styleFrom(
                          minimumSize: const Size(76, 40),
                          padding: const EdgeInsets.symmetric(horizontal: 18),
                        ),
                        child: isProcessing
                            ? const SizedBox(
                                width: 17,
                                height: 17,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Text('同意'),
                      ),
                    ],
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

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.status});

  final FriendRequestStatus status;

  @override
  Widget build(BuildContext context) {
    final (label, foreground, background) = switch (status) {
      FriendRequestStatus.pending => (
        '待处理',
        const Color(0xFFB36A20),
        const Color(0xFFFFF1DD),
      ),
      FriendRequestStatus.accepted => (
        '已同意',
        const Color(0xFF167A5B),
        const Color(0xFFDDEEE7),
      ),
      FriendRequestStatus.rejected => (
        '已拒绝',
        const Color(0xFF78847E),
        const Color(0xFFEEF1EF),
      ),
      FriendRequestStatus.cancelled => (
        '已撤回',
        const Color(0xFF78847E),
        const Color(0xFFEEF1EF),
      ),
      FriendRequestStatus.expired => (
        '已过期',
        const Color(0xFF78847E),
        const Color(0xFFEEF1EF),
      ),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: foreground,
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

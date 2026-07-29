import 'package:fangyuanli_mobile/src/features/friends/data/relationship_repository.dart';
import 'package:fangyuanli_mobile/src/features/friends/domain/friend_models.dart';
import 'package:fangyuanli_mobile/src/features/friends/presentation/friends_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeRelationshipRepository implements RelationshipRepository {
  var status = FriendRequestStatus.pending;

  FriendRequest get request => FriendRequest(
    requestId: 'request-1',
    sender: const UserSummary(userId: 'remote-user', displayName: '远山'),
    receiver: const UserSummary(userId: 'local-user', displayName: '小方'),
    status: status,
    applicationNote: '想和你一起参加附近活动',
    createdAt: DateTime(2026, 7, 29, 17),
  );

  @override
  Future<FriendDecision> decide({
    required String requestId,
    required bool accept,
  }) async {
    status = accept
        ? FriendRequestStatus.accepted
        : FriendRequestStatus.rejected;
    return FriendDecision(request: request);
  }

  @override
  Future<PageResult<FriendContact>> loadFriends() async {
    return const PageResult(items: [], hasMore: false);
  }

  @override
  Future<PageResult<FriendRequest>> loadReceivedRequests() async {
    return PageResult(items: [request], hasMore: false);
  }
}

void main() {
  testWidgets('好友申请从消息进入，处理后原记录显示已同意', (tester) async {
    final repository = _FakeRelationshipRepository();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          relationshipRepositoryProvider.overrideWithValue(repository),
        ],
        child: const MaterialApp(home: Scaffold(body: FriendsScreen())),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('好友申请'), findsOneWidget);
    expect(find.text('1 条申请等待处理'), findsOneWidget);

    await tester.tap(find.text('好友申请'));
    await tester.pumpAndSettle();
    expect(find.text('想和你一起参加附近活动'), findsOneWidget);

    await tester.tap(find.text('同意'));
    await tester.pumpAndSettle();

    expect(find.text('已同意'), findsOneWidget);
    expect(find.text('想和你一起参加附近活动'), findsOneWidget);

    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('消息'), findsOneWidget);
    expect(find.text('联系人'), findsOneWidget);
  });
}

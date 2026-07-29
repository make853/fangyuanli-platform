import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_failure.dart';
import '../../../core/network/authenticated_api_client.dart';
import '../../auth/application/auth_controller.dart';
import '../domain/friend_models.dart';

abstract interface class RelationshipRepository {
  Future<PageResult<FriendRequest>> loadReceivedRequests();

  Future<PageResult<FriendContact>> loadFriends();

  Future<FriendDecision> decide({
    required String requestId,
    required bool accept,
  });

  Future<FriendSettings> updateFriendSettings({
    required String friendUserId,
    String? remarkName,
    bool clearRemark = false,
    bool? canViewMyPosts,
    bool? pinned,
  });

  Future<void> deleteFriend(String friendUserId);

  Future<BlockedUser> blockUser(String targetUserId);

  Future<BlockedUser> unblockUser(String targetUserId);

  Future<PageResult<BlockedUser>> loadBlocks();
}

class HttpRelationshipRepository implements RelationshipRepository {
  const HttpRelationshipRepository(this._client);

  final AuthenticatedApiClient _client;

  @override
  Future<PageResult<FriendRequest>> loadReceivedRequests() async {
    final envelope = await _client.get(
      '/friend-requests',
      queryParameters: const {
        'direction': 'received',
        'status': 'all',
        'limit': 100,
      },
    );
    return _parsePage(envelope, FriendRequest.fromJson);
  }

  @override
  Future<PageResult<FriendContact>> loadFriends() async {
    final envelope = await _client.get(
      '/friends',
      queryParameters: const {'limit': 100},
    );
    return _parsePage(envelope, FriendContact.fromJson);
  }

  @override
  Future<FriendDecision> decide({
    required String requestId,
    required bool accept,
  }) async {
    final envelope = await _client.post(
      '/friend-requests/$requestId/decision',
      idempotent: true,
      data: {'decision': accept ? 'accept' : 'reject'},
    );
    return FriendDecision.fromJson(_data(envelope));
  }

  @override
  Future<FriendSettings> updateFriendSettings({
    required String friendUserId,
    String? remarkName,
    bool clearRemark = false,
    bool? canViewMyPosts,
    bool? pinned,
  }) async {
    final body = <String, dynamic>{
      if (remarkName != null || clearRemark)
        'remarkName': clearRemark ? null : remarkName,
      'canViewMyPosts': ?canViewMyPosts,
      'pinned': ?pinned,
    };
    final envelope = await _client.patch(
      '/friends/$friendUserId/settings',
      data: body,
      idempotent: true,
    );
    return FriendSettings.fromJson(_data(envelope));
  }

  @override
  Future<void> deleteFriend(String friendUserId) {
    return _client.deleteWithoutResponse(
      '/friends/$friendUserId',
      idempotent: true,
    );
  }

  @override
  Future<BlockedUser> blockUser(String targetUserId) async {
    final envelope = await _client.put(
      '/blocks/$targetUserId',
      data: const <String, dynamic>{},
      idempotent: true,
    );
    return BlockedUser.fromJson(_data(envelope));
  }

  @override
  Future<BlockedUser> unblockUser(String targetUserId) async {
    final envelope = await _client.delete(
      '/blocks/$targetUserId',
      idempotent: true,
    );
    return BlockedUser.fromJson(_data(envelope));
  }

  @override
  Future<PageResult<BlockedUser>> loadBlocks() async {
    final envelope = await _client.get(
      '/blocks',
      queryParameters: const {'limit': 100},
    );
    return _parsePage(envelope, BlockedUser.fromJson);
  }

  PageResult<T> _parsePage<T>(
    Map<String, dynamic> envelope,
    T Function(Map<String, dynamic>) fromJson,
  ) {
    final data = _data(envelope);
    final rawItems = data['items'];
    if (rawItems is! List) {
      throw const ApiFailure(message: '服务器返回的数据格式不正确');
    }
    return PageResult(
      items: [
        for (final item in rawItems)
          fromJson(Map<String, dynamic>.from(item as Map)),
      ],
      hasMore: data['hasMore'] as bool? ?? false,
      nextCursor: data['nextCursor'] as String?,
    );
  }

  Map<String, dynamic> _data(Map<String, dynamic> envelope) {
    final data = envelope['data'];
    if (data is! Map<String, dynamic>) {
      throw const ApiFailure(message: '服务器返回的数据格式不正确');
    }
    return data;
  }
}

final relationshipRepositoryProvider = Provider<RelationshipRepository>((ref) {
  final environment = ref.watch(appEnvironmentProvider);
  final authController = ref.read(authControllerProvider.notifier);
  return HttpRelationshipRepository(
    AuthenticatedApiClient(
      environment: environment,
      loadSession: authController.validSession,
    ),
  );
});

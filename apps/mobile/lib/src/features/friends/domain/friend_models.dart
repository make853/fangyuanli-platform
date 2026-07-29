enum FriendRequestStatus { pending, accepted, rejected, cancelled, expired }

class UserSummary {
  const UserSummary({required this.userId, required this.displayName});

  factory UserSummary.fromJson(Map<String, dynamic> json) {
    return UserSummary(
      userId: json['userId'] as String,
      displayName: json['displayName'] as String,
    );
  }

  final String userId;
  final String displayName;
}

class FriendRequest {
  const FriendRequest({
    required this.requestId,
    required this.sender,
    required this.receiver,
    required this.status,
    required this.applicationNote,
    required this.createdAt,
    this.decidedAt,
  });

  factory FriendRequest.fromJson(Map<String, dynamic> json) {
    return FriendRequest(
      requestId: json['requestId'] as String,
      sender: UserSummary.fromJson(json['sender'] as Map<String, dynamic>),
      receiver: UserSummary.fromJson(json['receiver'] as Map<String, dynamic>),
      status: FriendRequestStatus.values.byName(json['status'] as String),
      applicationNote: json['applicationNote'] as String,
      createdAt: DateTime.parse(json['createdAt'] as String).toLocal(),
      decidedAt: json['decidedAt'] == null
          ? null
          : DateTime.parse(json['decidedAt'] as String).toLocal(),
    );
  }

  final String requestId;
  final UserSummary sender;
  final UserSummary receiver;
  final FriendRequestStatus status;
  final String applicationNote;
  final DateTime createdAt;
  final DateTime? decidedAt;
}

class FriendContact {
  const FriendContact({
    required this.userId,
    required this.displayName,
    required this.nickname,
    required this.canViewMyPosts,
    required this.pinned,
    required this.directConversationId,
    this.remarkName,
  });

  factory FriendContact.fromJson(Map<String, dynamic> json) {
    return FriendContact(
      userId: json['userId'] as String,
      displayName: json['displayName'] as String,
      nickname: json['nickname'] as String,
      remarkName: json['remarkName'] as String?,
      canViewMyPosts: json['canViewMyPosts'] as bool? ?? true,
      pinned: json['pinned'] as bool? ?? false,
      directConversationId: json['directConversationId'] as String? ?? '',
    );
  }

  final String userId;
  final String displayName;
  final String nickname;
  final String? remarkName;
  final bool canViewMyPosts;
  final bool pinned;
  final String directConversationId;

  String get visibleName {
    final remark = remarkName?.trim();
    return remark == null || remark.isEmpty ? displayName : remark;
  }
}

class FriendDecision {
  const FriendDecision({
    required this.request,
    this.friendshipId,
    this.friendUserId,
    this.directConversationId,
  });

  factory FriendDecision.fromJson(Map<String, dynamic> json) {
    return FriendDecision(
      request: FriendRequest.fromJson(json['request'] as Map<String, dynamic>),
      friendshipId: json['friendshipId'] as String?,
      friendUserId: json['friendUserId'] as String?,
      directConversationId: json['directConversationId'] as String?,
    );
  }

  final FriendRequest request;
  final String? friendshipId;
  final String? friendUserId;
  final String? directConversationId;
}

class PageResult<T> {
  const PageResult({
    required this.items,
    required this.hasMore,
    this.nextCursor,
  });

  final List<T> items;
  final bool hasMore;
  final String? nextCursor;
}

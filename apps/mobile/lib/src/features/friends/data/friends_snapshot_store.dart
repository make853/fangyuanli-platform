import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/storage/account_snapshot_store.dart';
import '../domain/friend_models.dart';

class FriendsSnapshot {
  const FriendsSnapshot({
    required this.requests,
    required this.contacts,
    required this.blockedUsers,
  });

  factory FriendsSnapshot.fromJson(Map<String, dynamic> json) {
    return FriendsSnapshot(
      requests: [
        for (final item in json['requests'] as List? ?? const [])
          FriendRequest.fromJson(Map<String, dynamic>.from(item as Map)),
      ],
      contacts: [
        for (final item in json['contacts'] as List? ?? const [])
          FriendContact.fromJson(Map<String, dynamic>.from(item as Map)),
      ],
      blockedUsers: [
        for (final item in json['blockedUsers'] as List? ?? const [])
          BlockedUser.fromJson(Map<String, dynamic>.from(item as Map)),
      ],
    );
  }

  final List<FriendRequest> requests;
  final List<FriendContact> contacts;
  final List<BlockedUser> blockedUsers;

  Map<String, dynamic> toJson() => {
    'requests': [for (final item in requests) item.toJson()],
    'contacts': [for (final item in contacts) item.toJson()],
    'blockedUsers': [for (final item in blockedUsers) item.toJson()],
  };
}

abstract interface class FriendsSnapshotStore {
  Future<FriendsSnapshot?> read(String ownerUserId);

  Future<void> write(String ownerUserId, FriendsSnapshot snapshot);
}

class PersistentFriendsSnapshotStore implements FriendsSnapshotStore {
  const PersistentFriendsSnapshotStore(this._records);

  static const _snapshotKey = 'friends.overview';
  static const _payloadVersion = 1;

  final AccountSnapshotStore _records;

  @override
  Future<FriendsSnapshot?> read(String ownerUserId) async {
    final record = await _records.read(
      ownerUserId: ownerUserId,
      snapshotKey: _snapshotKey,
    );
    if (record == null) return null;
    if (record.payloadVersion != _payloadVersion) {
      await _records.delete(
        ownerUserId: ownerUserId,
        snapshotKey: _snapshotKey,
      );
      return null;
    }
    try {
      return FriendsSnapshot.fromJson(record.payload);
    } on Object {
      await _records.delete(
        ownerUserId: ownerUserId,
        snapshotKey: _snapshotKey,
      );
      return null;
    }
  }

  @override
  Future<void> write(String ownerUserId, FriendsSnapshot snapshot) {
    return _records.write(
      ownerUserId: ownerUserId,
      snapshotKey: _snapshotKey,
      payloadVersion: _payloadVersion,
      payload: snapshot.toJson(),
    );
  }
}

final friendsSnapshotStoreProvider = Provider<FriendsSnapshotStore>((ref) {
  return PersistentFriendsSnapshotStore(
    ref.watch(accountSnapshotStoreProvider),
  );
});

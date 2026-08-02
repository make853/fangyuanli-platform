import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/storage/account_snapshot_store.dart';
import '../domain/conversation_summary.dart';

class ConversationListSnapshot {
  const ConversationListSnapshot({
    required this.items,
    required this.navigationUnread,
  });

  factory ConversationListSnapshot.fromJson(Map<String, dynamic> json) {
    return ConversationListSnapshot(
      items: [
        for (final item in json['items'] as List? ?? const [])
          ConversationSummary.fromJson(Map<String, dynamic>.from(item as Map)),
      ],
      navigationUnread: json['navigationUnread'] as int? ?? 0,
    );
  }

  final List<ConversationSummary> items;
  final int navigationUnread;

  Map<String, dynamic> toJson() => {
    'items': [for (final item in items) item.toJson()],
    'navigationUnread': navigationUnread,
  };
}

abstract interface class ConversationListSnapshotStore {
  Future<ConversationListSnapshot?> read(String ownerUserId);

  Future<void> write(String ownerUserId, ConversationListSnapshot snapshot);
}

class PersistentConversationListSnapshotStore
    implements ConversationListSnapshotStore {
  const PersistentConversationListSnapshotStore(this._records);

  static const _snapshotKey = 'conversations.overview';
  static const _payloadVersion = 1;

  final AccountSnapshotStore _records;

  @override
  Future<ConversationListSnapshot?> read(String ownerUserId) async {
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
      return ConversationListSnapshot.fromJson(record.payload);
    } on Object {
      await _records.delete(
        ownerUserId: ownerUserId,
        snapshotKey: _snapshotKey,
      );
      return null;
    }
  }

  @override
  Future<void> write(String ownerUserId, ConversationListSnapshot snapshot) {
    return _records.write(
      ownerUserId: ownerUserId,
      snapshotKey: _snapshotKey,
      payloadVersion: _payloadVersion,
      payload: snapshot.toJson(),
    );
  }
}

final conversationListSnapshotStoreProvider =
    Provider<ConversationListSnapshotStore>((ref) {
      return PersistentConversationListSnapshotStore(
        ref.watch(accountSnapshotStoreProvider),
      );
    });

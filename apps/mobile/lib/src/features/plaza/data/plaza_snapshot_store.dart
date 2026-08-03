import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/storage/account_snapshot_store.dart';
import '../domain/plaza_models.dart';

class PlazaOverviewSnapshot {
  const PlazaOverviewSnapshot({
    required this.plazas,
    required this.anchorRadiusMeters,
  });

  factory PlazaOverviewSnapshot.fromJson(Map<String, dynamic> json) {
    return PlazaOverviewSnapshot(
      plazas: [
        for (final item in json['plazas'] as List? ?? const [])
          PlazaSummary.fromJson(Map<String, dynamic>.from(item as Map)),
      ],
      anchorRadiusMeters: json['anchorRadiusMeters'] as int? ?? 150,
    );
  }

  final List<PlazaSummary> plazas;
  final int anchorRadiusMeters;

  Map<String, dynamic> toJson() => {
    'plazas': [for (final plaza in plazas) plaza.toJson()],
    'anchorRadiusMeters': anchorRadiusMeters,
  };
}

abstract interface class PlazaSnapshotStore {
  PlazaOverviewSnapshot? peek(String ownerUserId);

  Future<PlazaOverviewSnapshot?> read(String ownerUserId);

  Future<void> write(String ownerUserId, PlazaOverviewSnapshot snapshot);
}

class PersistentPlazaSnapshotStore implements PlazaSnapshotStore {
  const PersistentPlazaSnapshotStore(this._records);

  static const _snapshotKey = 'plaza.overview';
  static const _payloadVersion = 1;

  final AccountSnapshotStore _records;

  @override
  PlazaOverviewSnapshot? peek(String ownerUserId) {
    final record = _records.peek(
      ownerUserId: ownerUserId,
      snapshotKey: _snapshotKey,
    );
    return _decodeRecord(record);
  }

  @override
  Future<PlazaOverviewSnapshot?> read(String ownerUserId) async {
    final record = await _records.read(
      ownerUserId: ownerUserId,
      snapshotKey: _snapshotKey,
    );
    final snapshot = _decodeRecord(record);
    if (snapshot != null) return snapshot;
    if (record != null) {
      await _records.delete(
        ownerUserId: ownerUserId,
        snapshotKey: _snapshotKey,
      );
    }
    return null;
  }

  PlazaOverviewSnapshot? _decodeRecord(AccountSnapshotRecord? record) {
    if (record == null || record.payloadVersion != _payloadVersion) return null;
    try {
      final snapshot = PlazaOverviewSnapshot.fromJson(record.payload);
      if (snapshot.plazas.length != 4) throw const FormatException();
      return snapshot;
    } on Object {
      return null;
    }
  }

  @override
  Future<void> write(String ownerUserId, PlazaOverviewSnapshot snapshot) {
    return _records.write(
      ownerUserId: ownerUserId,
      snapshotKey: _snapshotKey,
      payloadVersion: _payloadVersion,
      payload: snapshot.toJson(),
    );
  }
}

final plazaSnapshotStoreProvider = Provider<PlazaSnapshotStore>((ref) {
  return PersistentPlazaSnapshotStore(ref.watch(accountSnapshotStoreProvider));
});

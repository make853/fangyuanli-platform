import 'dart:io';

import 'package:fangyuanli_mobile/src/core/storage/account_snapshot_store.dart';
import 'package:fangyuanli_mobile/src/core/storage/app_database.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();

  test(
    'generic account snapshots are versioned and account isolated',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'fangyuanli-account-snapshot-',
      );
      final appDatabase = AppDatabase(
        databaseFactoryOverride: databaseFactoryFfi,
        pathLoader: () async => '${directory.path}/local.db',
      );
      final store = SqliteAccountSnapshotStore(appDatabase);

      await store.write(
        ownerUserId: 'owner-a',
        snapshotKey: 'friends.overview',
        payloadVersion: 1,
        payload: const {
          'contacts': [
            {'userId': 'user-b'},
          ],
        },
      );

      final ownerA = await store.read(
        ownerUserId: 'owner-a',
        snapshotKey: 'friends.overview',
      );
      final ownerB = await store.read(
        ownerUserId: 'owner-b',
        snapshotKey: 'friends.overview',
      );

      expect(ownerA?.payloadVersion, 1);
      expect(ownerA?.payload['contacts'], hasLength(1));
      expect(ownerB, isNull);
      expect(
        await (await appDatabase.open()).getVersion(),
        AppDatabase.schemaVersion,
      );

      await appDatabase.close();
      await directory.delete(recursive: true);
    },
  );
}

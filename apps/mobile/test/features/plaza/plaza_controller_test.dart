import 'dart:async';

import 'package:fangyuanli_mobile/src/core/config/app_environment.dart';
import 'package:fangyuanli_mobile/src/core/network/authenticated_api_client.dart';
import 'package:fangyuanli_mobile/src/core/realtime/realtime_event.dart';
import 'package:fangyuanli_mobile/src/features/plaza/application/plaza_chat_controller.dart';
import 'package:fangyuanli_mobile/src/features/plaza/application/plaza_controller.dart';
import 'package:fangyuanli_mobile/src/features/plaza/data/device_location_source.dart';
import 'package:fangyuanli_mobile/src/features/plaza/data/geo_context_repository.dart';
import 'package:fangyuanli_mobile/src/features/plaza/data/plaza_snapshot_store.dart';
import 'package:fangyuanli_mobile/src/features/plaza/domain/geo_context_models.dart';
import 'package:fangyuanli_mobile/src/features/plaza/domain/plaza_models.dart';
import 'package:flutter_test/flutter_test.dart';

class _CompletingLocationSource implements DeviceLocationSource {
  final completer = Completer<DevicePosition>();

  @override
  Future<DevicePosition> currentPosition() => completer.future;
}

class _FakeGeoContextRepository implements GeoContextRepository {
  _FakeGeoContextRepository(this.context);

  final GeoContext context;
  DevicePosition? receivedPosition;
  String? expectedUserId;

  @override
  Future<GeoContext> refresh(
    DevicePosition position, {
    String? expectedUserId,
  }) async {
    receivedPosition = position;
    this.expectedUserId = expectedUserId;
    return context;
  }
}

class _MemoryPlazaSnapshotStore implements PlazaSnapshotStore {
  _MemoryPlazaSnapshotStore(this.snapshot);

  PlazaOverviewSnapshot? snapshot;

  @override
  PlazaOverviewSnapshot? peek(String ownerUserId) => snapshot;
  String? readOwner;
  String? writeOwner;

  @override
  Future<PlazaOverviewSnapshot?> read(String ownerUserId) async {
    readOwner = ownerUserId;
    return snapshot;
  }

  @override
  Future<void> write(String ownerUserId, PlazaOverviewSnapshot snapshot) async {
    writeOwner = ownerUserId;
    this.snapshot = snapshot;
  }
}

void main() {
  test('广场聊天作用域只由稳定会话标识决定', () {
    const first = PlazaChatScope(conversationId: 'conversation-main');
    const rebuilt = PlazaChatScope(conversationId: 'conversation-main');
    const neighbor = PlazaChatScope(conversationId: 'conversation-neighbor');

    expect(first, rebuilt);
    expect(first.hashCode, rebuilt.hashCode);
    expect(first, isNot(neighbor));
  });

  test('先显示账户缓存，再静默刷新真实四广场及短期资格', () async {
    const cachedPlazas = [
      PlazaSummary(id: 'cached-main', name: '缓存主广场', isPrimary: true),
      PlazaSummary(id: 'cached-east', name: '缓存东广场', isPrimary: false),
      PlazaSummary(id: 'cached-north', name: '缓存北广场', isPrimary: false),
      PlazaSummary(id: 'cached-northeast', name: '缓存东北广场', isPrimary: false),
    ];
    final livePlazas = List.generate(
      4,
      (index) => PlazaSummary(
        id: 'live-$index',
        conversationId: 'conversation-$index',
        name: index == 0 ? '真实主广场' : '真实相邻广场$index',
        isPrimary: index == 0,
        unreadCount: index,
        unreadAppearance: index == 0
            ? UnreadAppearance.none
            : UnreadAppearance.red,
      ),
    );
    final source = _CompletingLocationSource();
    final repository = _FakeGeoContextRepository(
      GeoContext(
        locationContextToken: 'opaque-context-token',
        expiresAt: DateTime.now().toUtc().add(const Duration(minutes: 5)),
        anchor: const GeoAnchorState(
          radiusMeters: 150,
          isReused: true,
          recalculationPending: false,
        ),
        plazas: livePlazas,
      ),
    );
    final store = _MemoryPlazaSnapshotStore(
      const PlazaOverviewSnapshot(
        plazas: cachedPlazas,
        anchorRadiusMeters: 150,
      ),
    );
    final controller = PlazaController(
      source,
      repository,
      snapshotStore: store,
      ownerUserId: 'user-a',
    );

    expect(controller.state.plazas.first.name, '缓存主广场');
    await _waitFor(() => controller.state.plazas.isNotEmpty);
    expect(controller.state.plazas.first.name, '缓存主广场');
    expect(controller.state.isUsingCachedOverview, isTrue);
    expect(controller.state.hasFreshEligibility, isFalse);

    final position = DevicePosition(
      coordinateSystem: GeoCoordinateSystem.gcj02,
      longitude: 116.397,
      latitude: 39.908,
      accuracyMeters: 12,
      capturedAt: DateTime.now().toUtc(),
    );
    source.completer.complete(position);

    await _waitFor(() => controller.state.hasFreshEligibility);
    expect(controller.state.plazas.first.name, '真实主广场');
    expect(controller.state.locationContextToken, 'opaque-context-token');
    expect(controller.state.navigationUnread, 6);
    expect(controller.state.isUsingCachedOverview, isFalse);
    expect(repository.receivedPosition, same(position));
    expect(repository.expectedUserId, 'user-a');
    await _waitFor(() => store.writeOwner == 'user-a');
    expect(store.snapshot?.plazas.first.name, '真实主广场');
  });

  test('API 仓储拒绝把 WGS-84 冒充高德坐标提交', () async {
    final client = AuthenticatedApiClient(
      environment: const AppEnvironment(
        flavor: AppFlavor.local,
        apiBaseUrl: 'http://127.0.0.1:3000',
        realtimeUrl: 'ws://127.0.0.1:3000/ws/v1',
      ),
      loadSession: ({bool forceRefresh = false}) async => null,
    );
    addTearDown(client.close);
    final repository = ApiGeoContextRepository(client);

    await expectLater(
      repository.refresh(
        DevicePosition(
          coordinateSystem: GeoCoordinateSystem.wgs84,
          longitude: 116.397,
          latitude: 39.908,
          accuracyMeters: 12,
          capturedAt: DateTime.now().toUtc(),
        ),
      ),
      throwsA(isA<DeviceLocationUnavailable>()),
    );
  });

  test('四广场快照不持久化短期位置令牌', () {
    final snapshot = PlazaOverviewSnapshot(
      plazas: List.generate(
        4,
        (index) => PlazaSummary(
          id: 'plaza-$index',
          conversationId: 'conversation-$index',
          name: '广场$index',
          isPrimary: index == 0,
        ),
      ),
      anchorRadiusMeters: 150,
    );

    final json = snapshot.toJson();

    expect(json, isNot(contains('locationContextToken')));
    expect(PlazaOverviewSnapshot.fromJson(json).plazas, hasLength(4));
  });

  test('广场未读实时事件只更新对应卡片并区分红点灰点', () async {
    final events = StreamController<RealtimeEvent>();
    const plazas = [
      PlazaSummary(
        id: 'plaza-1',
        conversationId: 'conversation-1',
        name: '主广场',
        isPrimary: true,
      ),
      PlazaSummary(
        id: 'plaza-2',
        conversationId: 'conversation-2',
        name: '相邻广场',
        isPrimary: false,
      ),
    ];
    final controller = PlazaController(
      _CompletingLocationSource(),
      _FakeGeoContextRepository(
        GeoContext(
          locationContextToken: 'token',
          expiresAt: DateTime.now().toUtc().add(const Duration(minutes: 5)),
          anchor: const GeoAnchorState(
            radiusMeters: 150,
            isReused: true,
            recalculationPending: false,
          ),
          plazas: const [],
        ),
      ),
      snapshotStore: _MemoryPlazaSnapshotStore(
        const PlazaOverviewSnapshot(plazas: plazas, anchorRadiusMeters: 150),
      ),
      ownerUserId: 'user-a',
      refreshOnInitialize: false,
      realtimeEvents: events.stream,
    );
    await _waitFor(() => controller.state.plazas.length == 2);

    events.add(
      const RealtimeEvent(
        name: 'conversation.unread.changed',
        payload: {
          'conversationId': 'conversation-2',
          'navigationKey': 'plaza',
          'navigationUnreadCount': 0,
          'unread': {
            'count': 3,
            'appearance': 'gray',
            'firstUnreadSequence': 7,
          },
        },
      ),
    );
    await Future<void>.delayed(Duration.zero);

    expect(controller.state.plazas.first.unreadCount, 0);
    expect(controller.state.plazas.last.unreadCount, 3);
    expect(
      controller.state.plazas.last.unreadAppearance,
      UnreadAppearance.gray,
    );
    expect(controller.state.navigationUnread, 0);

    await events.close();
    controller.dispose();
  });

  test('单广场免打扰立即把红色未读改为灰色且不计入底栏', () async {
    final controller = PlazaController(
      _CompletingLocationSource(),
      _FakeGeoContextRepository(
        GeoContext(
          locationContextToken: 'token',
          expiresAt: DateTime.now().toUtc().add(const Duration(minutes: 5)),
          anchor: const GeoAnchorState(
            radiusMeters: 150,
            isReused: true,
            recalculationPending: false,
          ),
          plazas: const [],
        ),
      ),
      snapshotStore: _MemoryPlazaSnapshotStore(
        const PlazaOverviewSnapshot(
          plazas: [
            PlazaSummary(
              id: 'plaza-1',
              conversationId: 'conversation-1',
              name: '主广场',
              isPrimary: true,
              unreadCount: 4,
              unreadAppearance: UnreadAppearance.red,
            ),
          ],
          anchorRadiusMeters: 150,
        ),
      ),
      ownerUserId: 'user-a',
      refreshOnInitialize: false,
    );
    await _waitFor(() => controller.state.plazas.isNotEmpty);

    controller.setNotificationMode('plaza-1', 'muted');

    expect(controller.state.plazas.single.notificationMode, 'muted');
    expect(
      controller.state.plazas.single.unreadAppearance,
      UnreadAppearance.gray,
    );
    expect(controller.state.navigationUnread, 0);
    controller.dispose();
  });
}

Future<void> _waitFor(bool Function() predicate) async {
  final deadline = DateTime.now().add(const Duration(seconds: 2));
  while (!predicate()) {
    if (DateTime.now().isAfter(deadline)) {
      fail('等待异步状态超时');
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

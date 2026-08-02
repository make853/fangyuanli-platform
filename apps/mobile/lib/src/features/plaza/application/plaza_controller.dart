import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/realtime/realtime_controller.dart';
import '../../../core/realtime/realtime_event.dart';
import '../../auth/application/auth_controller.dart';
import '../data/device_location_source.dart';
import '../data/geo_context_repository.dart';
import '../data/plaza_snapshot_store.dart';
import '../domain/plaza_models.dart';

class PlazaState {
  const PlazaState({
    this.plazas = const [],
    this.anchorRadiusMeters = 150,
    this.locationContextToken,
    this.locationContextExpiresAt,
    this.isLoading = false,
    this.hasFreshEligibility = false,
    this.isUsingCachedOverview = false,
    this.errorMessage,
  });

  final List<PlazaSummary> plazas;
  final int anchorRadiusMeters;
  final String? locationContextToken;
  final DateTime? locationContextExpiresAt;
  final bool isLoading;
  final bool hasFreshEligibility;
  final bool isUsingCachedOverview;
  final String? errorMessage;

  int get navigationUnread => plazas
      .where((plaza) => plaza.unreadAppearance == UnreadAppearance.red)
      .fold(0, (total, plaza) => total + plaza.unreadCount);

  PlazaState copyWith({
    List<PlazaSummary>? plazas,
    int? anchorRadiusMeters,
    String? locationContextToken,
    DateTime? locationContextExpiresAt,
    bool? isLoading,
    bool? hasFreshEligibility,
    bool? isUsingCachedOverview,
    String? errorMessage,
    bool clearError = false,
  }) {
    return PlazaState(
      plazas: plazas ?? this.plazas,
      anchorRadiusMeters: anchorRadiusMeters ?? this.anchorRadiusMeters,
      locationContextToken: locationContextToken ?? this.locationContextToken,
      locationContextExpiresAt:
          locationContextExpiresAt ?? this.locationContextExpiresAt,
      isLoading: isLoading ?? this.isLoading,
      hasFreshEligibility: hasFreshEligibility ?? this.hasFreshEligibility,
      isUsingCachedOverview:
          isUsingCachedOverview ?? this.isUsingCachedOverview,
      errorMessage: clearError ? null : errorMessage ?? this.errorMessage,
    );
  }
}

class PlazaController extends StateNotifier<PlazaState> {
  PlazaController(
    this._locationSource,
    this._repository, {
    this.snapshotStore,
    this.ownerUserId,
    Stream<RealtimeEvent>? realtimeEvents,
    bool refreshOnInitialize = true,
  }) : super(const PlazaState()) {
    _realtimeSubscription = realtimeEvents?.listen(_onRealtimeEvent);
    unawaited(_initialize(refreshOnInitialize: refreshOnInitialize));
  }

  final DeviceLocationSource _locationSource;
  final GeoContextRepository _repository;
  final PlazaSnapshotStore? snapshotStore;
  final String? ownerUserId;
  Future<void>? _activeRefresh;
  Future<void> _snapshotWrite = Future.value();
  StreamSubscription<RealtimeEvent>? _realtimeSubscription;

  Future<void> _initialize({required bool refreshOnInitialize}) async {
    final cached = await _readSnapshot();
    if (!mounted) return;
    if (cached != null) {
      state = state.copyWith(
        plazas: cached.plazas,
        anchorRadiusMeters: cached.anchorRadiusMeters,
        isUsingCachedOverview: true,
      );
    }
    if (refreshOnInitialize) {
      await refresh(silent: cached != null);
    }
  }

  Future<void> refresh({bool silent = false}) {
    final active = _activeRefresh;
    if (active != null) return active;
    final request = _refresh(silent: silent);
    _activeRefresh = request;
    return request.whenComplete(() {
      if (identical(_activeRefresh, request)) _activeRefresh = null;
    });
  }

  Future<void> _refresh({required bool silent}) async {
    if (!silent) {
      state = state.copyWith(isLoading: true, clearError: true);
    }
    try {
      final position = await _locationSource.currentPosition();
      final context = await _repository.refresh(
        position,
        expectedUserId: ownerUserId,
      );
      if (!mounted) return;
      state = state.copyWith(
        plazas: context.plazas,
        anchorRadiusMeters: context.anchor.radiusMeters,
        locationContextToken: context.locationContextToken,
        locationContextExpiresAt: context.expiresAt,
        isLoading: false,
        hasFreshEligibility: !context.isExpired,
        isUsingCachedOverview: false,
        clearError: true,
      );
      _persistSnapshot();
    } catch (error) {
      if (!mounted) return;
      state = state.copyWith(
        isLoading: false,
        hasFreshEligibility: false,
        errorMessage: error.toString(),
      );
    }
  }

  Future<PlazaOverviewSnapshot?> _readSnapshot() async {
    final store = snapshotStore;
    final owner = ownerUserId;
    if (store == null || owner == null || owner.isEmpty) return null;
    try {
      return await store.read(owner);
    } catch (_) {
      return null;
    }
  }

  void _persistSnapshot() {
    final store = snapshotStore;
    final owner = ownerUserId;
    if (store == null || owner == null || owner.isEmpty) return;
    final snapshot = PlazaOverviewSnapshot(
      plazas: List.of(state.plazas),
      anchorRadiusMeters: state.anchorRadiusMeters,
    );
    _snapshotWrite = _snapshotWrite
        .then((_) => store.write(owner, snapshot))
        .catchError((_) {});
  }

  void markLocallyRead(String plazaId) {
    final updated = [
      for (final plaza in state.plazas)
        if (plaza.id == plazaId)
          plaza.copyWithUnread(const PlazaUnreadState())
        else
          plaza,
    ];
    state = state.copyWith(plazas: updated);
    _persistSnapshot();
  }

  void _onRealtimeEvent(RealtimeEvent event) {
    if (event.name != 'conversation.unread.changed' ||
        event.payload['navigationKey'] != 'plaza') {
      return;
    }
    final conversationId = event.payload['conversationId'];
    final unreadJson = event.payload['unread'];
    if (conversationId is! String || unreadJson is! Map) return;
    final unread = PlazaUnreadState.fromJson(
      Map<String, dynamic>.from(unreadJson),
    );
    var changed = false;
    final updated = [
      for (final plaza in state.plazas)
        if (plaza.conversationId == conversationId)
          plaza.copyWithUnread(unread)
        else
          plaza,
    ];
    changed = state.plazas.any(
      (plaza) => plaza.conversationId == conversationId,
    );
    if (!changed) return;
    state = state.copyWith(plazas: updated);
    _persistSnapshot();
  }

  @override
  void dispose() {
    unawaited(_realtimeSubscription?.cancel());
    super.dispose();
  }
}

final plazaControllerProvider =
    StateNotifierProvider.autoDispose<PlazaController, PlazaState>((ref) {
      final realtime = ref.watch(realtimeControllerProvider.notifier);
      return PlazaController(
        ref.watch(deviceLocationSourceProvider),
        ref.watch(geoContextRepositoryProvider),
        snapshotStore: ref.watch(plazaSnapshotStoreProvider),
        ownerUserId: ref.watch(
          authControllerProvider.select((state) => state.session?.userId),
        ),
        realtimeEvents: realtime.events,
      );
    });

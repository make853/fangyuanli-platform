import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/application/auth_controller.dart';
import '../../plaza/application/plaza_controller.dart';
import '../data/place_repository.dart';
import '../domain/place_models.dart';

class PlaceState {
  const PlaceState({
    this.items = const [],
    this.category = PlaceCategory.all,
    this.isLoading = true,
    this.errorMessage,
  });

  final List<PlaceSummary> items;
  final PlaceCategory category;
  final bool isLoading;
  final String? errorMessage;

  int get navigationUnread => items
      .where((item) => item.unreadAppearance == PlaceUnreadAppearance.red)
      .fold(0, (total, item) => total + item.unreadCount);

  PlaceState copyWith({
    List<PlaceSummary>? items,
    PlaceCategory? category,
    bool? isLoading,
    String? errorMessage,
    bool clearError = false,
  }) {
    return PlaceState(
      items: items ?? this.items,
      category: category ?? this.category,
      isLoading: isLoading ?? this.isLoading,
      errorMessage: clearError ? null : errorMessage ?? this.errorMessage,
    );
  }
}

class PlaceController extends StateNotifier<PlaceState> {
  PlaceController(this._repository, {this.expectedUserId})
    : super(const PlaceState());

  final PlaceRepository _repository;
  final String? expectedUserId;
  String? _locationContextToken;
  int _requestGeneration = 0;

  void updateLocationContext(String? value) {
    final token = value?.trim();
    if (token == null || token.isEmpty || token == _locationContextToken) {
      return;
    }
    _locationContextToken = token;
    unawaited(load(silent: state.items.isNotEmpty));
  }

  Future<void> selectCategory(PlaceCategory category) async {
    if (category == state.category && state.items.isNotEmpty) return;
    state = state.copyWith(category: category);
    await load(silent: false);
  }

  Future<void> refresh() => load(silent: state.items.isNotEmpty);

  Future<void> load({required bool silent}) async {
    final token = _locationContextToken;
    if (token == null) return;
    final generation = ++_requestGeneration;
    if (!silent) {
      state = state.copyWith(isLoading: true, clearError: true);
    }
    try {
      final items = await _repository.discover(
        locationContextToken: token,
        category: state.category,
        expectedUserId: expectedUserId,
      );
      if (!mounted || generation != _requestGeneration) return;
      state = state.copyWith(
        items: List.unmodifiable(items),
        isLoading: false,
        clearError: true,
      );
    } catch (error) {
      if (!mounted || generation != _requestGeneration) return;
      state = state.copyWith(isLoading: false, errorMessage: error.toString());
    }
  }
}

final placeControllerProvider =
    StateNotifierProvider.autoDispose<PlaceController, PlaceState>((ref) {
      final controller = PlaceController(
        ref.watch(placeRepositoryProvider),
        expectedUserId: ref.watch(
          authControllerProvider.select((state) => state.session?.userId),
        ),
      );
      ref.listen<String?>(
        plazaControllerProvider.select((state) => state.locationContextToken),
        (_, token) => controller.updateLocationContext(token),
        fireImmediately: true,
      );
      return controller;
    });

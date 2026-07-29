import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/relationship_repository.dart';
import '../domain/friend_models.dart';

class FriendsState {
  const FriendsState({
    this.requests = const [],
    this.contacts = const [],
    this.processingRequestIds = const {},
    this.isLoading = false,
    this.errorMessage,
  });

  final List<FriendRequest> requests;
  final List<FriendContact> contacts;
  final Set<String> processingRequestIds;
  final bool isLoading;
  final String? errorMessage;

  int get pendingRequestCount => requests
      .where((request) => request.status == FriendRequestStatus.pending)
      .length;

  FriendsState copyWith({
    List<FriendRequest>? requests,
    List<FriendContact>? contacts,
    Set<String>? processingRequestIds,
    bool? isLoading,
    String? errorMessage,
    bool clearError = false,
  }) {
    return FriendsState(
      requests: requests ?? this.requests,
      contacts: contacts ?? this.contacts,
      processingRequestIds: processingRequestIds ?? this.processingRequestIds,
      isLoading: isLoading ?? this.isLoading,
      errorMessage: clearError ? null : errorMessage ?? this.errorMessage,
    );
  }
}

class FriendsController extends StateNotifier<FriendsState> {
  FriendsController(this._repository) : super(const FriendsState()) {
    unawaited(load());
  }

  final RelationshipRepository _repository;

  Future<void> load() async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final results = await Future.wait([
        _repository.loadReceivedRequests(),
        _repository.loadFriends(),
      ]);
      final requestPage = results[0] as PageResult<FriendRequest>;
      final friendPage = results[1] as PageResult<FriendContact>;
      state = state.copyWith(
        requests: requestPage.items,
        contacts: friendPage.items,
        isLoading: false,
      );
    } catch (error) {
      state = state.copyWith(isLoading: false, errorMessage: error.toString());
    }
  }

  Future<bool> decide({required String requestId, required bool accept}) async {
    if (state.processingRequestIds.contains(requestId)) return false;
    state = state.copyWith(
      processingRequestIds: {...state.processingRequestIds, requestId},
      clearError: true,
    );

    try {
      final result = await _repository.decide(
        requestId: requestId,
        accept: accept,
      );
      var contacts = state.contacts;
      if (accept) {
        contacts = (await _repository.loadFriends()).items;
      }
      state = state.copyWith(
        requests: [
          for (final request in state.requests)
            if (request.requestId == requestId) result.request else request,
        ],
        contacts: contacts,
        processingRequestIds: {...state.processingRequestIds}
          ..remove(requestId),
      );
      return true;
    } catch (error) {
      state = state.copyWith(
        processingRequestIds: {...state.processingRequestIds}
          ..remove(requestId),
        errorMessage: error.toString(),
      );
      return false;
    }
  }
}

final friendsControllerProvider =
    StateNotifierProvider.autoDispose<FriendsController, FriendsState>(
      (ref) => FriendsController(ref.watch(relationshipRepositoryProvider)),
    );

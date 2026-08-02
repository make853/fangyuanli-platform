import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../conversations/application/conversation_list_controller.dart';
import '../domain/friend_models.dart';
import 'friends_controller.dart';

/// Keeps relationship mutations and their conversation-list projection in sync.
///
/// The relationship API remains the source of truth. Conversation metadata is
/// updated only after the server confirms the mutation, so the UI never needs a
/// manual pull-to-refresh and failed writes do not leave optimistic stale state.
class FriendRelationshipCoordinator {
  FriendRelationshipCoordinator(this._friends, this._conversations);

  final FriendsController _friends;
  final ConversationListController _conversations;

  Future<bool> decide({required String requestId, required bool accept}) async {
    final succeeded = await _friends.decide(
      requestId: requestId,
      accept: accept,
    );
    if (succeeded && accept) {
      await _conversations.load(silent: true);
    }
    return succeeded;
  }

  Future<bool> updateRemark(String friendUserId, String value) async {
    final succeeded = await _friends.updateRemark(friendUserId, value);
    if (succeeded) {
      _syncContact(friendUserId);
    }
    return succeeded;
  }

  Future<bool> updatePostPermission(String friendUserId, bool canViewMyPosts) {
    return _friends.updatePostPermission(friendUserId, canViewMyPosts);
  }

  Future<bool> updatePinned(String friendUserId, bool pinned) async {
    final succeeded = await _friends.updatePinned(friendUserId, pinned);
    if (succeeded) {
      _syncContact(friendUserId);
    }
    return succeeded;
  }

  Future<bool> deleteFriend(FriendContact contact) async {
    final succeeded = await _friends.deleteFriend(contact.userId);
    if (succeeded) {
      _conversations.removeConversation(contact.directConversationId);
    }
    return succeeded;
  }

  Future<bool> blockUser(FriendContact contact) async {
    final succeeded = await _friends.blockUser(contact.userId);
    if (succeeded) {
      _conversations.removeConversation(contact.directConversationId);
    }
    return succeeded;
  }

  Future<bool> unblockUser(String targetUserId) async {
    final succeeded = await _friends.unblockUser(targetUserId);
    if (succeeded) {
      await _conversations.load(silent: true);
    }
    return succeeded;
  }

  void _syncContact(String friendUserId) {
    final updated = _friends.contactForUser(friendUserId);
    if (updated == null || updated.directConversationId.isEmpty) return;
    _conversations.applyFriendProjection(
      conversationId: updated.directConversationId,
      title: updated.visibleName,
      pinned: updated.pinned,
    );
  }
}

final friendRelationshipCoordinatorProvider =
    Provider.autoDispose<FriendRelationshipCoordinator>((ref) {
      return FriendRelationshipCoordinator(
        ref.watch(friendsControllerProvider.notifier),
        ref.watch(conversationListControllerProvider.notifier),
      );
    });

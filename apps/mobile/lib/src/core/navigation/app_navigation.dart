import 'package:flutter/material.dart';

enum AppSection { plaza, places, activities, friends, profile }

enum AppEntryPoint {
  tab,
  messageList,
  contactList,
  systemNotification,
  globalSearch,
  quickCreate,
  channelList,
  channelChat,
  channelDetail,
  profile,
  settings,
  directChat,
}

enum AppRouteId {
  globalSearch('/search'),
  globalSearchCategory('/search/category'),
  postComposer('/posts/compose'),
  activityComposer('/activities/compose'),
  friendScan('/friends/scan'),
  plazaChat('/plazas/chat'),
  plazaInfo('/plazas/info'),
  placeChat('/places/chat'),
  placeDetail('/places/detail'),
  activityChat('/activities/chat'),
  activityDetail('/activities/detail'),
  myProfile('/profile/me'),
  userProfile('/profile/user'),
  profileEdit('/profile/me/edit'),
  friendProfile('/friends/profile'),
  friendProfileSettings('/friends/profile/settings'),
  friendRequests('/friends/requests'),
  systemInbox('/friends/system-inbox'),
  directChat('/friends/direct-chat'),
  directChatSettings('/friends/direct-chat/settings'),
  chatHistorySearch('/friends/direct-chat/search'),
  accountSecurity('/profile/account-security'),
  privacy('/profile/account-security/privacy'),
  blockList('/profile/account-security/block-list');

  const AppRouteId(this.path);

  final String path;
}

@immutable
class AppNavigationSource {
  const AppNavigationSource({
    required this.section,
    required this.entryPoint,
    this.routeId,
    this.entityId,
  });

  final AppSection section;
  final AppEntryPoint entryPoint;
  final AppRouteId? routeId;
  final String? entityId;
}

@immutable
class AppRouteMetadata {
  const AppRouteMetadata({required this.destination, required this.source});

  final AppRouteId destination;
  final AppNavigationSource source;
}

abstract final class AppNavigation {
  static Future<T?> push<T>(
    BuildContext context, {
    required AppRouteId destination,
    required AppNavigationSource source,
    required WidgetBuilder builder,
  }) {
    return Navigator.of(context).push<T>(
      MaterialPageRoute<T>(
        settings: RouteSettings(
          name: destination.path,
          arguments: AppRouteMetadata(destination: destination, source: source),
        ),
        builder: builder,
      ),
    );
  }

  static AppRouteMetadata? metadataOf(BuildContext context) {
    final arguments = ModalRoute.of(context)?.settings.arguments;
    return arguments is AppRouteMetadata ? arguments : null;
  }
}

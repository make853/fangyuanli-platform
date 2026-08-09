import 'package:flutter/material.dart';

import '../../../core/navigation/app_navigation.dart';
import '../../conversations/domain/community_chat_models.dart';
import '../../conversations/presentation/community_chat_screen.dart';
import '../../nearby/presentation/nearby_ui.dart';
import '../data/place_preview_catalog.dart';
import '../domain/place_models.dart';

class PlaceChatScreen extends StatelessWidget {
  const PlaceChatScreen({
    required this.place,
    required this.detailsBuilder,
    super.key,
  });

  final PlaceSummary place;
  final WidgetBuilder detailsBuilder;

  @override
  Widget build(BuildContext context) {
    return CommunityChatScreen(
      channel: CommunityChannelDescriptor(
        id: place.id,
        kind: CommunityChannelKind.place,
        title: place.name,
        subtitle: '地点群 · ${formatNearbyDistance(place.distanceMeters)}',
        emptyMessage: '这个地点群暂时还没有消息',
        announcement: '文明交流，不发布与本地点无关的广告。',
      ),
      sourceSection: AppSection.places,
      detailsRoute: AppRouteId.placeDetail,
      detailsBuilder: detailsBuilder,
      previewMessages: place.conversationId.isEmpty
          ? PlacePreviewCatalog.messages
          : const [],
    );
  }
}

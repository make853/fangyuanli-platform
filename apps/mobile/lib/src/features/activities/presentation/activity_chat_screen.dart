import 'package:flutter/material.dart';

import '../../../core/navigation/app_navigation.dart';
import '../../conversations/domain/community_chat_models.dart';
import '../../conversations/presentation/community_chat_screen.dart';
import '../data/activity_preview_catalog.dart';
import '../domain/activity_models.dart';

class ActivityChatScreen extends StatelessWidget {
  const ActivityChatScreen({
    required this.activity,
    required this.detailsBuilder,
    super.key,
  });

  final ActivitySummary activity;
  final WidgetBuilder detailsBuilder;

  @override
  Widget build(BuildContext context) {
    return CommunityChatScreen(
      channel: CommunityChannelDescriptor(
        id: activity.id,
        kind: CommunityChannelKind.activity,
        title: activity.name,
        subtitle: '活动群 · ${activity.memberLabel}',
        emptyMessage: '这个活动群暂时还没有消息',
        announcement: activity.announcement,
      ),
      sourceSection: AppSection.activities,
      detailsRoute: AppRouteId.activityDetail,
      detailsBuilder: detailsBuilder,
      previewMessages: ActivityPreviewCatalog.messages,
    );
  }
}

import 'package:flutter/foundation.dart';

enum CommunityChannelKind { plaza, place, activity }

@immutable
class CommunityChannelDescriptor {
  const CommunityChannelDescriptor({
    required this.id,
    required this.kind,
    required this.title,
    required this.subtitle,
    required this.emptyMessage,
    this.announcement,
  });

  final String id;
  final CommunityChannelKind kind;
  final String title;
  final String subtitle;
  final String emptyMessage;
  final String? announcement;
}

@immutable
class CommunityMessagePreview {
  const CommunityMessagePreview({
    required this.id,
    required this.senderName,
    required this.text,
    this.isMine = false,
  });

  final String id;
  final String senderName;
  final String text;
  final bool isMine;
}

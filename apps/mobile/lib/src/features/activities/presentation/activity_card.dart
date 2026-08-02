import 'package:flutter/material.dart';

import '../../nearby/presentation/nearby_ui.dart';
import '../domain/activity_models.dart';

class ActivityCard extends StatelessWidget {
  const ActivityCard({
    required this.activity,
    required this.onOpenChat,
    required this.onOpenDetails,
    super.key,
  });

  final ActivitySummary activity;
  final VoidCallback onOpenChat;
  final VoidCallback onOpenDetails;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(19),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        key: ValueKey('activity-card-${activity.id}'),
        onTap: onOpenChat,
        child: Stack(
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  height: 46,
                  color: const Color(0xFF2B745D),
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          activity.statusLabel,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      Text(
                        formatNearbyDistance(activity.distanceMeters),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        activity.name,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        '${activity.timeLabel} · ${activity.locationName}',
                        style: const TextStyle(
                          color: Color(0xFF66736D),
                          fontSize: 12,
                        ),
                      ),
                      const SizedBox(height: 9),
                      Row(
                        children: [
                          const Icon(
                            Icons.people_alt_outlined,
                            size: 17,
                            color: Color(0xFF66736D),
                          ),
                          const SizedBox(width: 5),
                          Expanded(
                            child: Text(
                              activity.memberLabel,
                              style: const TextStyle(
                                color: Color(0xFF66736D),
                                fontSize: 12,
                              ),
                            ),
                          ),
                          TextButton(
                            key: ValueKey('activity-details-${activity.id}'),
                            onPressed: onOpenDetails,
                            child: const Text('活动详情'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
            Positioned(
              right: 8,
              top: 37,
              child: UnreadCountBadge(count: activity.unreadCount),
            ),
          ],
        ),
      ),
    );
  }
}

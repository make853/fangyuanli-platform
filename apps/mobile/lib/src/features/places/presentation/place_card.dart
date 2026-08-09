import 'package:flutter/material.dart';

import '../../nearby/presentation/nearby_ui.dart';
import '../domain/place_models.dart';

class PlaceCard extends StatelessWidget {
  const PlaceCard({required this.place, required this.onTap, super.key});

  final PlaceSummary place;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        key: ValueKey('place-card-${place.id}'),
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: const Color(0xFFF0F3F1),
                  borderRadius: BorderRadius.circular(15),
                ),
                child: Text(place.icon, style: const TextStyle(fontSize: 24)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 6,
                      runSpacing: 5,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(
                          place.name,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        if (place.isVerified)
                          StatusPill(
                            label: place.isManagedByMe ? '已认证 · 我管理' : '已认证',
                          ),
                        _PlaceHeatPill(heat: place.heat),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '${formatNearbyDistance(place.distanceMeters)} · ${place.typeLabel}${place.isVerified ? '' : ' · 未认证'}',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFF66736D),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              UnreadCountBadge(count: place.unreadCount),
            ],
          ),
        ),
      ),
    );
  }
}

class _PlaceHeatPill extends StatelessWidget {
  const _PlaceHeatPill({required this.heat});

  final PlaceHeat heat;

  @override
  Widget build(BuildContext context) {
    final colors = switch (heat) {
      PlaceHeat.quiet => (const Color(0xFF67716C), const Color(0xFFE8ECEA)),
      PlaceHeat.neutral => (const Color(0xFF56645E), const Color(0xFFE3EAE6)),
      PlaceHeat.active => (const Color(0xFF226A83), const Color(0xFFDCEEF4)),
      PlaceHeat.veryActive => (
        const Color(0xFF9B5E12),
        const Color(0xFFFFE9CB),
      ),
      PlaceHeat.hot => (const Color(0xFFB54842), const Color(0xFFFFDEDC)),
    };
    return StatusPill(
      label: heat.label,
      foreground: colors.$1,
      background: colors.$2,
    );
  }
}

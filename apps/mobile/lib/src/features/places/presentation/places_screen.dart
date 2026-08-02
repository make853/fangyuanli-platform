import 'package:flutter/material.dart';

import '../../../core/navigation/app_navigation.dart';
import '../../nearby/presentation/nearby_ui.dart';
import '../data/place_preview_catalog.dart';
import '../domain/place_models.dart';
import 'place_card.dart';
import 'place_chat_screen.dart';
import 'place_detail_screen.dart';

class PlacesScreen extends StatefulWidget {
  const PlacesScreen({this.places = PlacePreviewCatalog.places, super.key});

  final List<PlaceSummary> places;

  @override
  State<PlacesScreen> createState() => _PlacesScreenState();
}

class _PlacesScreenState extends State<PlacesScreen> {
  PlaceCategory _category = PlaceCategory.all;

  List<PlaceSummary> get _visiblePlaces {
    return switch (_category) {
      PlaceCategory.all => [...widget.places],
      PlaceCategory.history =>
        widget.places.where((place) => place.isInHistory).toList(),
      PlaceCategory.nearest => [
        ...widget.places,
      ]..sort((a, b) => a.distanceMeters.compareTo(b.distanceMeters)),
      _ => widget.places.where((place) => place.category == _category).toList(),
    };
  }

  void _pending(String action) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text('$action将在地点纵切接入后启用')));
  }

  @override
  Widget build(BuildContext context) {
    final visiblePlaces = _visiblePlaces;
    return Column(
      children: [
        const NearbyPreviewNotice(text: '地点卡片为交互预览，高德地点服务接入后替换为真实结果'),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Material(
            color: Colors.white,
            borderRadius: BorderRadius.circular(17),
            child: ListTile(
              key: const ValueKey('place-category-picker'),
              leading: const Icon(Icons.tune_rounded, color: Color(0xFF167A5B)),
              title: const Text(
                '地点类型',
                style: TextStyle(color: Color(0xFF78847E), fontSize: 11),
              ),
              subtitle: Text(
                _category.label,
                style: const TextStyle(
                  color: Color(0xFF26332E),
                  fontWeight: FontWeight.w700,
                ),
              ),
              trailing: const Icon(Icons.expand_more_rounded),
              onTap: _selectCategory,
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 2, 8, 6),
          child: Row(
            children: [
              const Expanded(
                child: Text(
                  '附近活跃地点',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                ),
              ),
              TextButton(
                onPressed: () => _pending('地点全部已读'),
                child: const Text('全部已读'),
              ),
            ],
          ),
        ),
        Expanded(
          child: visiblePlaces.isEmpty
              ? const Center(
                  child: Text(
                    '没有符合条件的地点',
                    style: TextStyle(color: Color(0xFF78847E)),
                  ),
                )
              : ListView.separated(
                  key: const PageStorageKey('places-list'),
                  padding: const EdgeInsets.fromLTRB(16, 2, 16, 28),
                  itemCount: visiblePlaces.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 10),
                  itemBuilder: (context, index) {
                    final place = visiblePlaces[index];
                    return PlaceCard(
                      place: place,
                      onTap: () => _openChat(place),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Future<void> _selectCategory() async {
    final value = await showNearbySelectionSheet<PlaceCategory>(
      context,
      title: '选择地点类型',
      selected: _category,
      values: PlaceCategory.values,
      label: (value) => value.label,
    );
    if (value != null && mounted) setState(() => _category = value);
  }

  void _openChat(PlaceSummary place) {
    AppNavigation.push<void>(
      context,
      destination: AppRouteId.placeChat,
      source: AppNavigationSource(
        section: AppSection.places,
        entryPoint: AppEntryPoint.channelList,
        entityId: place.id,
      ),
      builder: (_) => PlaceChatScreen(
        place: place,
        detailsBuilder: (_) => PlaceDetailScreen(place: place),
      ),
    );
  }
}

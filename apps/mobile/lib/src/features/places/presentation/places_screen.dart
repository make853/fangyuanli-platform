import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/navigation/app_navigation.dart';
import '../../nearby/presentation/nearby_ui.dart';
import '../application/place_controller.dart';
import '../domain/place_models.dart';
import 'place_card.dart';
import 'place_chat_screen.dart';
import 'place_detail_screen.dart';

class PlacesScreen extends ConsumerStatefulWidget {
  const PlacesScreen({this.places, super.key});

  /// Explicit data is reserved for isolated visual/widget tests.
  /// Production leaves this null and reads the real place controller.
  final List<PlaceSummary>? places;

  @override
  ConsumerState<PlacesScreen> createState() => _PlacesScreenState();
}

class _PlacesScreenState extends ConsumerState<PlacesScreen> {
  PlaceCategory _category = PlaceCategory.all;

  List<PlaceSummary> _visiblePlaces(List<PlaceSummary> places) {
    if (widget.places == null) return places;
    return switch (_category) {
      PlaceCategory.all => [...places],
      PlaceCategory.history =>
        places.where((place) => place.isInHistory).toList(),
      PlaceCategory.nearest => [
        ...places,
      ]..sort((a, b) => a.distanceMeters.compareTo(b.distanceMeters)),
      _ => places.where((place) => place.category == _category).toList(),
    };
  }

  void _pending(String action) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text('$action将在地点纵切接入后启用')));
  }

  @override
  Widget build(BuildContext context) {
    final liveState = widget.places == null
        ? ref.watch(placeControllerProvider)
        : null;
    final visiblePlaces = _visiblePlaces(widget.places ?? liveState!.items);
    return Column(
      children: [
        if (widget.places != null)
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
        Expanded(child: _placeList(liveState, visiblePlaces)),
      ],
    );
  }

  Widget _placeList(PlaceState? liveState, List<PlaceSummary> visiblePlaces) {
    if (liveState?.isLoading == true && visiblePlaces.isEmpty) {
      return const Center(child: CircularProgressIndicator.adaptive());
    }
    if (visiblePlaces.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                liveState?.errorMessage ?? '没有符合条件的地点',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Color(0xFF78847E)),
              ),
              if (liveState?.errorMessage != null) ...[
                const SizedBox(height: 12),
                OutlinedButton(
                  onPressed: () =>
                      ref.read(placeControllerProvider.notifier).refresh(),
                  child: const Text('重新加载'),
                ),
              ],
            ],
          ),
        ),
      );
    }
    final list = ListView.separated(
      key: const PageStorageKey('places-list'),
      padding: const EdgeInsets.fromLTRB(16, 2, 16, 28),
      itemCount: visiblePlaces.length,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        final place = visiblePlaces[index];
        return PlaceCard(place: place, onTap: () => _openChat(place));
      },
    );
    if (widget.places != null) return list;
    return RefreshIndicator.adaptive(
      onRefresh: () => ref.read(placeControllerProvider.notifier).refresh(),
      child: list,
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
    if (value == null || !mounted) return;
    setState(() => _category = value);
    if (widget.places == null) {
      await ref.read(placeControllerProvider.notifier).selectCategory(value);
    }
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

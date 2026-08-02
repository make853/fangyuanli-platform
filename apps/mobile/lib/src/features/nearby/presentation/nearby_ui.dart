import 'package:flutter/material.dart';

class NearbyPreviewNotice extends StatelessWidget {
  const NearbyPreviewNotice({required this.text, super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: const Color(0xFFFFF5D9),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: const TextStyle(color: Color(0xFF7A6320), fontSize: 11),
      ),
    );
  }
}

class UnreadCountBadge extends StatelessWidget {
  const UnreadCountBadge({required this.count, this.muted = false, super.key});

  final int count;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    if (count <= 0) return const SizedBox.shrink();
    return Container(
      constraints: const BoxConstraints(minWidth: 20, minHeight: 20),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: muted ? const Color(0xFF9AA49F) : const Color(0xFFE24A52),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        count > 99 ? '99+' : '$count',
        textAlign: TextAlign.center,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class StatusPill extends StatelessWidget {
  const StatusPill({
    required this.label,
    this.foreground = const Color(0xFF167A5B),
    this.background = const Color(0xFFDDEEE7),
    super.key,
  });

  final String label;
  final Color foreground;
  final Color background;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: foreground,
          fontSize: 10,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

Future<T?> showNearbySelectionSheet<T>(
  BuildContext context, {
  required String title,
  required T selected,
  required List<T> values,
  required String Function(T value) label,
}) {
  return showModalBottomSheet<T>(
    context: context,
    showDragHandle: true,
    useSafeArea: true,
    builder: (context) => ListView(
      shrinkWrap: true,
      padding: const EdgeInsets.only(bottom: 12),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
          child: Text(title, style: Theme.of(context).textTheme.titleMedium),
        ),
        for (final value in values)
          ListTile(
            title: Text(label(value)),
            trailing: value == selected
                ? const Icon(Icons.check_rounded, color: Color(0xFF167A5B))
                : null,
            onTap: () => Navigator.pop(context, value),
          ),
      ],
    ),
  );
}

String formatNearbyDistance(int meters) {
  if (meters < 1000) return '约$meters米';
  final value = meters / 1000;
  return '约${value == value.roundToDouble() ? value.toInt() : value.toStringAsFixed(1)}公里';
}

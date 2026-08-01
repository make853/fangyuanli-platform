import 'package:flutter/material.dart';

enum FeatureAvailability { available, comingSoon, hidden }

class FeatureEntry {
  const FeatureEntry({
    required this.id,
    required this.title,
    required this.icon,
    this.subtitle,
    this.availability = FeatureAvailability.comingSoon,
  });

  final String id;
  final String title;
  final String? subtitle;
  final IconData icon;
  final FeatureAvailability availability;
}

void showFeatureComingSoon(BuildContext context, String featureName) {
  final messenger = ScaffoldMessenger.of(context);
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        content: Text('$featureName功能开发中'),
        duration: const Duration(seconds: 2),
      ),
    );
}

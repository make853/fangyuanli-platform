import 'package:flutter/material.dart';

class SystemInboxScreen extends StatelessWidget {
  const SystemInboxScreen({
    required this.title,
    required this.emptyMessage,
    super.key,
  });

  final String title;
  final String emptyMessage;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.notifications_none_rounded,
              size: 44,
              color: Color(0xFFA1AAA5),
            ),
            const SizedBox(height: 12),
            Text(
              emptyMessage,
              style: const TextStyle(color: Color(0xFF78847E)),
            ),
          ],
        ),
      ),
    );
  }
}

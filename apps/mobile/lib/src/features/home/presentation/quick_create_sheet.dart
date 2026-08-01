import 'package:flutter/material.dart';

enum QuickCreateAction { post, activity, scan }

Future<QuickCreateAction?> showQuickCreateSheet(BuildContext context) {
  return showModalBottomSheet<QuickCreateAction>(
    context: context,
    showDragHandle: true,
    useSafeArea: true,
    builder: (context) => const _QuickCreateSheet(),
  );
}

class _QuickCreateSheet extends StatelessWidget {
  const _QuickCreateSheet();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 18),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _QuickCreateTile(
            icon: Icons.edit_note_rounded,
            title: '发布动态',
            subtitle: '分享附近正在发生的事',
            onTap: () => Navigator.pop(context, QuickCreateAction.post),
          ),
          const SizedBox(height: 8),
          _QuickCreateTile(
            icon: Icons.event_available_rounded,
            title: '创建活动',
            subtitle: '组织运动、聚会或长期活动',
            onTap: () => Navigator.pop(context, QuickCreateAction.activity),
          ),
          const SizedBox(height: 8),
          _QuickCreateTile(
            icon: Icons.qr_code_scanner_rounded,
            title: '扫一扫',
            subtitle: '扫描二维码申请添加好友',
            onTap: () => Navigator.pop(context, QuickCreateAction.scan),
          ),
        ],
      ),
    );
  }
}

class _QuickCreateTile extends StatelessWidget {
  const _QuickCreateTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFFF5F7F6),
      borderRadius: BorderRadius.circular(17),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(17)),
        onTap: onTap,
        leading: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: const Color(0xFFDDEEE7),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Icon(icon, color: const Color(0xFF167A5B)),
        ),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: Text(subtitle),
        trailing: const Icon(Icons.chevron_right_rounded),
      ),
    );
  }
}

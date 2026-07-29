import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../application/profile_controller.dart';

class PrivacyScreen extends ConsumerWidget {
  const PrivacyScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(profileControllerProvider);
    final privacy = state.privacy;
    return Scaffold(
      appBar: AppBar(title: const Text('隐私')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 28),
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(4, 0, 4, 9),
            child: Text(
              '资料与发现',
              style: TextStyle(
                color: Color(0xFF66736D),
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          if (privacy == null && state.isLoading)
            const Padding(
              padding: EdgeInsets.only(top: 120),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (privacy == null)
            Center(
              child: OutlinedButton(
                onPressed: ref.read(profileControllerProvider.notifier).load,
                child: const Text('重新加载'),
              ),
            )
          else
            Material(
              color: Colors.white,
              borderRadius: BorderRadius.circular(17),
              clipBehavior: Clip.antiAlias,
              child: Column(
                children: [
                  SwitchListTile(
                    title: const Text('陌生人查看资料'),
                    subtitle: const Text('关闭后，陌生人只能看到头像和个人签名'),
                    value: privacy.strangersCanViewProfile,
                    onChanged: state.isSaving
                        ? null
                        : (value) => _update(
                            context,
                            ref,
                            strangersCanViewProfile: value,
                          ),
                  ),
                  const Divider(height: 1, indent: 16, endIndent: 16),
                  SwitchListTile(
                    title: const Text('通过方圆号找到我'),
                    value: privacy.searchableByFangyuanNumber,
                    onChanged: state.isSaving
                        ? null
                        : (value) => _update(
                            context,
                            ref,
                            searchableByFangyuanNumber: value,
                          ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _update(
    BuildContext context,
    WidgetRef ref, {
    bool? strangersCanViewProfile,
    bool? searchableByFangyuanNumber,
  }) async {
    final succeeded = await ref
        .read(profileControllerProvider.notifier)
        .updatePrivacy(
          strangersCanViewProfile: strangersCanViewProfile,
          searchableByFangyuanNumber: searchableByFangyuanNumber,
        );
    if (!context.mounted || succeeded) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          ref.read(profileControllerProvider).errorMessage ?? '设置失败，请稍后重试',
        ),
      ),
    );
  }
}

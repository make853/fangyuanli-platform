import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../application/profile_controller.dart';
import '../domain/profile_models.dart';
import 'profile_edit_screen.dart';

class MyProfileDetailScreen extends ConsumerWidget {
  const MyProfileDetailScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(profileControllerProvider);
    final profile = state.profile;
    return Scaffold(
      appBar: AppBar(
        title: const Text('个人资料'),
        actions: [
          TextButton(
            onPressed: profile == null
                ? null
                : () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => ProfileEditScreen(profile: profile),
                    ),
                  ),
            child: const Text('编辑'),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: ref.read(profileControllerProvider.notifier).load,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 28),
          children: [
            if (profile == null && state.isLoading)
              const Padding(
                padding: EdgeInsets.only(top: 120),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (profile == null)
              _LoadFailure(
                message: state.errorMessage ?? '个人资料加载失败',
                onRetry: ref.read(profileControllerProvider.notifier).load,
              )
            else ...[
              _ProfileHero(profile: profile),
              const SizedBox(height: 14),
              _ProfileFields(profile: profile),
              const SizedBox(height: 14),
              const _ComingSoonCard(),
            ],
          ],
        ),
      ),
    );
  }
}

class _ProfileHero extends StatelessWidget {
  const _ProfileHero({required this.profile});

  final UserProfile profile;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 36,
            backgroundColor: const Color(0xFFDDEEE7),
            child: Text(
              profile.initial,
              style: const TextStyle(
                color: Color(0xFF167A5B),
                fontSize: 25,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  profile.nickname ?? profile.displayName,
                  style: const TextStyle(
                    fontSize: 21,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  '方圆号：${profile.fangyuanNumber ?? '未显示'}',
                  style: const TextStyle(color: Color(0xFF78847E)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ProfileFields extends StatelessWidget {
  const _ProfileFields({required this.profile});

  final UserProfile profile;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          _FieldRow(label: '昵称', value: profile.nickname ?? '未设置'),
          const Divider(height: 1, indent: 16, endIndent: 16),
          _FieldRow(label: '性别', value: profile.gender.label),
          const Divider(height: 1, indent: 16, endIndent: 16),
          _FieldRow(
            label: '个人签名',
            value: profile.signature.isEmpty ? '未设置' : profile.signature,
          ),
        ],
      ),
    );
  }
}

class _FieldRow extends StatelessWidget {
  const _FieldRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 82,
            child: Text(
              label,
              style: const TextStyle(color: Color(0xFF78847E)),
            ),
          ),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }
}

class _ComingSoonCard extends StatelessWidget {
  const _ComingSoonCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFF2F7F4),
        borderRadius: BorderRadius.circular(14),
      ),
      child: const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.image_outlined, color: Color(0xFF167A5B)),
          SizedBox(width: 12),
          Expanded(
            child: Text(
              '头像和背景墙将在安全的图片上传功能完成后开放。',
              style: TextStyle(color: Color(0xFF52615A), height: 1.4),
            ),
          ),
        ],
      ),
    );
  }
}

class _LoadFailure extends StatelessWidget {
  const _LoadFailure({required this.message, required this.onRetry});

  final String message;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 100),
      child: Column(
        children: [
          const Icon(
            Icons.cloud_off_outlined,
            size: 42,
            color: Color(0xFFA1AAA5),
          ),
          const SizedBox(height: 12),
          Text(message, textAlign: TextAlign.center),
          const SizedBox(height: 12),
          OutlinedButton(onPressed: onRetry, child: const Text('重新加载')),
        ],
      ),
    );
  }
}

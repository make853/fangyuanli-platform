import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/presentation/feature_entry.dart';
import '../application/profile_controller.dart';
import '../domain/profile_models.dart';
import 'profile_edit_screen.dart';
import 'profile_media_widgets.dart';

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
          padding: const EdgeInsets.only(bottom: 28),
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
              _ProfileCover(
                profile: profile,
                onAvatarTap: () => _showMediaPreview(
                  context,
                  profile.avatar?.url ?? profile.avatar?.thumbnailUrl,
                ),
                onCoverTap: () => _showMediaPreview(
                  context,
                  profile.background?.url ?? profile.background?.thumbnailUrl,
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: _ProfileSummary(profile: profile),
              ),
              const Padding(
                padding: EdgeInsets.fromLTRB(20, 22, 20, 9),
                child: Text(
                  '动态',
                  style: TextStyle(
                    color: Color(0xFF66736D),
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: _PostsPlaceholder(
                  onTap: () => showFeatureComingSoon(context, '个人动态'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ProfileCover extends StatelessWidget {
  const _ProfileCover({
    required this.profile,
    required this.onAvatarTap,
    required this.onCoverTap,
  });

  final UserProfile profile;
  final VoidCallback onAvatarTap;
  final VoidCallback onCoverTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 192,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(
            bottom: 38,
            child: Material(
              color: const Color(0xFFD6E7DF),
              child: InkWell(
                onTap: onCoverTap,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    ProfileBackgroundImage(media: profile.background),
                    const Align(
                      alignment: Alignment.topRight,
                      child: Padding(
                        padding: EdgeInsets.all(14),
                        child: Icon(
                          Icons.wallpaper_rounded,
                          color: Color(0x993A5C4D),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            left: 20,
            bottom: 0,
            child: Material(
              color: Colors.white,
              borderRadius: BorderRadius.circular(29),
              child: InkWell(
                key: const ValueKey('profile-avatar'),
                borderRadius: BorderRadius.circular(29),
                onTap: onAvatarTap,
                child: Padding(
                  padding: const EdgeInsets.all(4),
                  child: ProfileAvatarImage(
                    media: profile.avatar,
                    initial: profile.initial,
                    size: 92,
                    borderRadius: 26,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

Future<void> _showMediaPreview(BuildContext context, Uri? url) async {
  if (url == null) return;
  await showDialog<void>(
    context: context,
    barrierColor: Colors.black87,
    builder: (context) => Dialog.fullscreen(
      backgroundColor: Colors.black,
      child: Stack(
        children: [
          Positioned.fill(
            child: InteractiveViewer(
              minScale: 0.8,
              maxScale: 4,
              child: Center(
                child: Image.network(
                  url.toString(),
                  fit: BoxFit.contain,
                  errorBuilder: (_, _, _) => const Text(
                    '图片加载失败',
                    style: TextStyle(color: Colors.white70),
                  ),
                ),
              ),
            ),
          ),
          SafeArea(
            child: IconButton(
              onPressed: () => Navigator.pop(context),
              icon: const Icon(Icons.close_rounded, color: Colors.white),
            ),
          ),
        ],
      ),
    ),
  );
}

class _ProfileSummary extends StatelessWidget {
  const _ProfileSummary({required this.profile});

  final UserProfile profile;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            profile.nickname ?? profile.displayName,
            style: const TextStyle(fontSize: 23, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 5),
          Row(
            children: [
              Flexible(
                child: Text(
                  '方圆号：${profile.fangyuanNumber ?? '未显示'}',
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFF78847E),
                    fontSize: 13,
                  ),
                ),
              ),
              const SizedBox(width: 9),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0xFFF0F4F2),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  profile.gender.label,
                  style: const TextStyle(
                    color: Color(0xFF66736D),
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            profile.signature.isEmpty ? '还没有填写个人签名' : profile.signature,
            style: TextStyle(
              color: profile.signature.isEmpty
                  ? const Color(0xFFA1AAA5)
                  : const Color(0xFF3A4942),
              height: 1.45,
            ),
          ),
          const SizedBox(height: 14),
          const Divider(height: 1),
          _FieldRow(label: '昵称', value: profile.nickname ?? '未设置'),
        ],
      ),
    );
  }
}

class _PostsPlaceholder extends StatelessWidget {
  const _PostsPlaceholder({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(17),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: const Padding(
          padding: EdgeInsets.all(18),
          child: Row(
            children: [
              Icon(Icons.dynamic_feed_outlined, color: Color(0xFF167A5B)),
              SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('个人动态', style: TextStyle(fontWeight: FontWeight.w600)),
                    SizedBox(height: 4),
                    Text(
                      '功能开发中，完成后将在这里显示历史动态',
                      style: TextStyle(color: Color(0xFF78847E), fontSize: 12),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: Color(0xFFA1AAA5)),
            ],
          ),
        ),
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

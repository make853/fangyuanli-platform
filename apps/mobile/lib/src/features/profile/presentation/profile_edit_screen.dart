import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/presentation/feature_entry.dart';
import '../application/profile_controller.dart';
import '../domain/profile_models.dart';

class ProfileEditScreen extends ConsumerStatefulWidget {
  const ProfileEditScreen({required this.profile, super.key});

  final UserProfile profile;

  @override
  ConsumerState<ProfileEditScreen> createState() => _ProfileEditScreenState();
}

class _ProfileEditScreenState extends ConsumerState<ProfileEditScreen> {
  late final TextEditingController _nickname;
  late final TextEditingController _signature;
  late ProfileGender _gender;

  @override
  void initState() {
    super.initState();
    _nickname = TextEditingController(
      text: widget.profile.nickname ?? widget.profile.displayName,
    );
    _signature = TextEditingController(text: widget.profile.signature);
    _gender = switch (widget.profile.gender) {
      ProfileGender.male => ProfileGender.male,
      ProfileGender.female => ProfileGender.female,
      _ => ProfileGender.unspecified,
    };
  }

  @override
  void dispose() {
    _nickname.dispose();
    _signature.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(profileControllerProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('编辑资料'),
        actions: [
          TextButton(
            onPressed: state.isSaving ? null : _save,
            child: state.isSaving
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('保存'),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 28),
        children: [
          Material(
            color: Colors.white,
            borderRadius: BorderRadius.circular(17),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: () => showFeatureComingSoon(context, '更换头像'),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Container(
                      width: 58,
                      height: 58,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: const Color(0xFFDDEEE7),
                        borderRadius: BorderRadius.circular(19),
                      ),
                      child: Text(
                        widget.profile.initial,
                        style: const TextStyle(
                          color: Color(0xFF167A5B),
                          fontSize: 22,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const SizedBox(width: 14),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '头像',
                            style: TextStyle(fontWeight: FontWeight.w600),
                          ),
                          SizedBox(height: 4),
                          Text(
                            '图片上传功能开发中',
                            style: TextStyle(
                              color: Color(0xFF78847E),
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Icon(
                      Icons.chevron_right_rounded,
                      color: Color(0xFFA1AAA5),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 14),
          _EditorCard(
            children: [
              TextField(
                controller: _nickname,
                maxLength: 64,
                decoration: const InputDecoration(
                  labelText: '昵称',
                  border: InputBorder.none,
                  contentPadding: EdgeInsets.all(16),
                ),
              ),
              const Divider(height: 1, indent: 16, endIndent: 16),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
                child: Text(
                  '性别',
                  style: Theme.of(context).textTheme.labelLarge,
                ),
              ),
              RadioGroup<ProfileGender>(
                groupValue: _gender,
                onChanged: (value) {
                  if (value != null) setState(() => _gender = value);
                },
                child: const Column(
                  children: [
                    RadioListTile(
                      value: ProfileGender.unspecified,
                      title: Text('保密'),
                    ),
                    RadioListTile(value: ProfileGender.male, title: Text('男')),
                    RadioListTile(
                      value: ProfileGender.female,
                      title: Text('女'),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1, indent: 16, endIndent: 16),
              TextField(
                controller: _signature,
                maxLength: 160,
                minLines: 2,
                maxLines: 4,
                decoration: const InputDecoration(
                  labelText: '个人签名',
                  hintText: '介绍一下自己',
                  border: InputBorder.none,
                  contentPadding: EdgeInsets.all(16),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _save() async {
    final nickname = _nickname.text.trim();
    if (nickname.isEmpty) {
      _message('昵称不能为空');
      return;
    }
    final succeeded = await ref
        .read(profileControllerProvider.notifier)
        .updateProfile(
          nickname: nickname,
          gender: _gender,
          signature: _signature.text.trim(),
        );
    if (!mounted) return;
    if (succeeded) {
      Navigator.pop(context);
      _message('资料已保存');
    } else {
      _message(
        ref.read(profileControllerProvider).errorMessage ?? '保存失败，请稍后重试',
      );
    }
  }

  void _message(String value) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(value)));
  }
}

class _EditorCard extends StatelessWidget {
  const _EditorCard({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: Column(children: children),
    );
  }
}

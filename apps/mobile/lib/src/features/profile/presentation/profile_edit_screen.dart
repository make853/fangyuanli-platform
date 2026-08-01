import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../media/data/image_pipeline.dart';
import '../application/profile_controller.dart';
import '../domain/profile_models.dart';
import 'profile_media_widgets.dart';

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
    final profile = state.profile ?? widget.profile;
    final mediaBusy = state.isUpdatingMedia;
    return Scaffold(
      appBar: AppBar(
        title: const Text('编辑资料'),
        actions: [
          TextButton(
            onPressed: state.isSaving || mediaBusy ? null : _save,
            child: state.isSaving || mediaBusy
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
          _EditorCard(
            children: [
              _ProfileMediaRow(
                label: '头像',
                description: '用于聊天、动态和个人资料',
                enabled: !mediaBusy,
                preview: ProfileAvatarImage(
                  media: profile.avatar,
                  initial: profile.initial,
                  size: 58,
                  borderRadius: 19,
                ),
                onTap: () => _chooseMedia(
                  slot: ProfileMediaSlot.avatar,
                  hasMedia: profile.avatar != null,
                ),
              ),
              const Divider(height: 1, indent: 16, endIndent: 16),
              _ProfileMediaRow(
                label: '背景墙',
                description: '展示在完整个人资料顶部',
                enabled: !mediaBusy,
                preview: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: SizedBox(
                    width: 78,
                    height: 52,
                    child: ProfileBackgroundImage(media: profile.background),
                  ),
                ),
                onTap: () => _chooseMedia(
                  slot: ProfileMediaSlot.background,
                  hasMedia: profile.background != null,
                ),
              ),
              if (mediaBusy) ...[
                const LinearProgressIndicator(minHeight: 2),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
                  child: Text(
                    state.mediaStatusMessage ?? '正在更新图片…',
                    style: const TextStyle(
                      color: Color(0xFF66736D),
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 14),
          _EditorCard(
            children: [
              _LabeledTextField(
                label: '昵称',
                controller: _nickname,
                maxLength: 64,
                hintText: '请输入昵称',
              ),
              const Divider(height: 1, indent: 16, endIndent: 16),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '性别',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 12),
                    _GenderSelector(
                      value: _gender,
                      onChanged: (value) => setState(() => _gender = value),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1, indent: 16, endIndent: 16),
              _LabeledTextField(
                label: '个人签名',
                controller: _signature,
                maxLength: 160,
                minLines: 2,
                maxLines: 4,
                hintText: '介绍一下自己',
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

  Future<void> _chooseMedia({
    required ProfileMediaSlot slot,
    required bool hasMedia,
  }) async {
    final choice = await showModalBottomSheet<_MediaChoice>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('从相册选择'),
              onTap: () => Navigator.pop(context, _MediaChoice.gallery),
            ),
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('拍摄'),
              onTap: () => Navigator.pop(context, _MediaChoice.camera),
            ),
            if (hasMedia)
              ListTile(
                leading: const Icon(
                  Icons.delete_outline_rounded,
                  color: Color(0xFFC84B45),
                ),
                title: const Text(
                  '移除当前图片',
                  style: TextStyle(color: Color(0xFFC84B45)),
                ),
                onTap: () => Navigator.pop(context, _MediaChoice.remove),
              ),
          ],
        ),
      ),
    );
    if (!mounted || choice == null) return;

    final controller = ref.read(profileControllerProvider.notifier);
    if (choice == _MediaChoice.remove) {
      final succeeded = await controller.removeMedia(slot);
      if (!mounted) return;
      _message(succeeded ? '${_slotName(slot)}已移除' : _mediaFailureMessage());
      return;
    }

    final result = await controller.pickAndBindMedia(
      slot: slot,
      source: choice == _MediaChoice.camera
          ? MediaImageSource.camera
          : MediaImageSource.gallery,
    );
    if (!mounted || result == ProfileMediaAction.cancelled) return;
    _message(
      result == ProfileMediaAction.updated
          ? '${_slotName(slot)}已更新'
          : _mediaFailureMessage(),
    );
  }

  String _slotName(ProfileMediaSlot slot) =>
      slot == ProfileMediaSlot.avatar ? '头像' : '背景墙';

  String _mediaFailureMessage() =>
      ref.read(profileControllerProvider).errorMessage ?? '图片更新失败，请稍后重试';

  void _message(String value) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(value)));
  }
}

enum _MediaChoice { gallery, camera, remove }

class _ProfileMediaRow extends StatelessWidget {
  const _ProfileMediaRow({
    required this.label,
    required this.description,
    required this.preview,
    required this.enabled,
    required this.onTap,
  });

  final String label;
  final String description;
  final Widget preview;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: enabled ? onTap : null,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            preview,
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    description,
                    style: const TextStyle(
                      color: Color(0xFF78847E),
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded, color: Color(0xFFA1AAA5)),
          ],
        ),
      ),
    );
  }
}

class _LabeledTextField extends StatelessWidget {
  const _LabeledTextField({
    required this.label,
    required this.controller,
    required this.maxLength,
    required this.hintText,
    this.minLines = 1,
    this.maxLines = 1,
  });

  final String label;
  final TextEditingController controller;
  final int maxLength;
  final String hintText;
  final int minLines;
  final int maxLines;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: controller,
            maxLength: maxLength,
            minLines: minLines,
            maxLines: maxLines,
            decoration: InputDecoration(
              hintText: hintText,
              counterText: '',
              filled: true,
              fillColor: const Color(0xFFF5F7F4),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 14,
                vertical: 13,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(13),
                borderSide: BorderSide.none,
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(13),
                borderSide: const BorderSide(color: Color(0xFFE1E7E3)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(13),
                borderSide: const BorderSide(
                  color: Color(0xFF167A5B),
                  width: 1.5,
                ),
              ),
            ),
          ),
          const SizedBox(height: 6),
          Align(
            alignment: Alignment.centerRight,
            child: ValueListenableBuilder<TextEditingValue>(
              valueListenable: controller,
              builder: (context, value, child) => Text(
                '${value.text.characters.length}/$maxLength',
                style: const TextStyle(color: Color(0xFF8B9690), fontSize: 12),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _GenderSelector extends StatelessWidget {
  const _GenderSelector({required this.value, required this.onChanged});

  final ProfileGender value;
  final ValueChanged<ProfileGender> onChanged;

  @override
  Widget build(BuildContext context) {
    const options = [
      (ProfileGender.unspecified, '保密'),
      (ProfileGender.male, '男'),
      (ProfileGender.female, '女'),
    ];
    return Row(
      children: [
        for (var index = 0; index < options.length; index++) ...[
          Expanded(
            child: _GenderOption(
              label: options[index].$2,
              selected: value == options[index].$1,
              onTap: () => onChanged(options[index].$1),
            ),
          ),
          if (index != options.length - 1) const SizedBox(width: 9),
        ],
      ],
    );
  }
}

class _GenderOption extends StatelessWidget {
  const _GenderOption({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? const Color(0xFFDDEEE7) : const Color(0xFFF5F7F4),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Container(
          height: 44,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected
                  ? const Color(0xFF167A5B)
                  : const Color(0xFFE1E7E3),
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: selected
                  ? const Color(0xFF167A5B)
                  : const Color(0xFF3A4942),
              fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
            ),
          ),
        ),
      ),
    );
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

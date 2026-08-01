import 'package:flutter/material.dart';

class ActivityComposerScreen extends StatefulWidget {
  const ActivityComposerScreen({super.key});

  @override
  State<ActivityComposerScreen> createState() => _ActivityComposerScreenState();
}

class _ActivityComposerScreenState extends State<ActivityComposerScreen> {
  final _nameController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _customTypeController = TextEditingController();
  final _capacityController = TextEditingController();
  String _activityType = '运动';
  bool _limitedCapacity = false;
  bool _noFixedEnd = false;
  int _visibilityRadius = 1000;
  String _joinPolicy = '需要管理员批准';
  String _speakPolicy = '只有已加入成员可以聊天';
  DateTime? _startsAt;
  DateTime? _endsAt;

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    _customTypeController.dispose();
    _capacityController.dispose();
    super.dispose();
  }

  Future<void> _chooseDate({required bool start}) async {
    final now = DateTime.now();
    final initial = start ? _startsAt ?? now : _endsAt ?? _startsAt ?? now;
    final date = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: now.subtract(const Duration(days: 1)),
      lastDate: DateTime(now.year + 3),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(initial),
    );
    if (time == null || !mounted) return;
    final value = DateTime(
      date.year,
      date.month,
      date.day,
      time.hour,
      time.minute,
    );
    setState(() {
      if (start) {
        _startsAt = value;
        if (_endsAt != null && !_endsAt!.isAfter(value)) _endsAt = null;
      } else {
        _endsAt = value;
      }
    });
  }

  void _showPending(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  void _syncSpeakPolicy() {
    if (_joinPolicy == '需要管理员批准' && _speakPolicy == '附近所有人都可以聊天') {
      _speakPolicy = '只有已加入成员可以聊天';
    }
  }

  @override
  Widget build(BuildContext context) {
    final speakPolicies = _joinPolicy == '需要管理员批准'
        ? const ['只有已加入成员可以聊天', '只有管理员可以发言']
        : const ['附近所有人都可以聊天', '只有已加入成员可以聊天', '只有管理员可以发言'];
    return Scaffold(
      appBar: AppBar(
        title: const Text('创建活动'),
        actions: [
          TextButton(
            onPressed: () => _showPending('活动服务接入后即可创建'),
            child: const Text('创建'),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 30),
        children: [
          _ActivityCard(
            children: [
              TextField(
                key: const ValueKey('activity-name-field'),
                controller: _nameController,
                maxLength: 120,
                decoration: const InputDecoration(labelText: '活动名称'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _descriptionController,
                minLines: 3,
                maxLines: 6,
                maxLength: 5000,
                decoration: const InputDecoration(labelText: '活动介绍'),
              ),
            ],
          ),
          const SizedBox(height: 14),
          _ActivityCard(
            children: [
              _DropdownRow<String>(
                title: '活动类型',
                value: _activityType,
                values: const ['运动', '聚会', '演出', '学习', '公益', '其他'],
                onChanged: (value) => setState(() => _activityType = value),
              ),
              if (_activityType == '其他') ...[
                const Divider(height: 1, indent: 16, endIndent: 16),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
                  child: TextField(
                    controller: _customTypeController,
                    maxLength: 64,
                    decoration: const InputDecoration(labelText: '具体活动类型'),
                  ),
                ),
              ],
              const Divider(height: 1, indent: 16, endIndent: 16),
              ListTile(
                leading: const Icon(Icons.place_outlined),
                title: const Text('活动位置'),
                subtitle: const Text('创建时必须从地图选择'),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => _showPending('高德地图选点能力接入后可选择位置'),
              ),
              const Divider(height: 1, indent: 16, endIndent: 16),
              ListTile(
                title: const Text('开始时间'),
                subtitle: Text(_formatDate(_startsAt)),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => _chooseDate(start: true),
              ),
              const Divider(height: 1, indent: 16, endIndent: 16),
              SwitchListTile(
                title: const Text('活动长期进行'),
                subtitle: const Text('开启后不设置固定结束时间'),
                value: _noFixedEnd,
                onChanged: (value) => setState(() => _noFixedEnd = value),
              ),
              if (!_noFixedEnd) ...[
                const Divider(height: 1, indent: 16, endIndent: 16),
                ListTile(
                  title: const Text('结束时间'),
                  subtitle: Text(_formatDate(_endsAt)),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => _chooseDate(start: false),
                ),
              ],
            ],
          ),
          const SizedBox(height: 14),
          _ActivityCard(
            children: [
              SwitchListTile(
                title: const Text('限制人数'),
                value: _limitedCapacity,
                onChanged: (value) => setState(() => _limitedCapacity = value),
              ),
              if (_limitedCapacity) ...[
                const Divider(height: 1, indent: 16, endIndent: 16),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
                  child: TextField(
                    controller: _capacityController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: '人数上限'),
                  ),
                ),
              ],
              const Divider(height: 1, indent: 16, endIndent: 16),
              _DropdownRow<int>(
                title: '附近可见范围',
                value: _visibilityRadius,
                values: const [500, 1000, 2000, 5000, 10000, 30000],
                label: (value) =>
                    value < 1000 ? '$value米' : '${value ~/ 1000}公里',
                onChanged: (value) => setState(() => _visibilityRadius = value),
              ),
              const Divider(height: 1, indent: 16, endIndent: 16),
              _DropdownRow<String>(
                key: const ValueKey('activity-join-policy'),
                title: '加入方式',
                value: _joinPolicy,
                values: const ['直接加入', '需要管理员批准'],
                onChanged: (value) => setState(() {
                  _joinPolicy = value;
                  _syncSpeakPolicy();
                }),
              ),
              const Divider(height: 1, indent: 16, endIndent: 16),
              _DropdownRow<String>(
                title: '谁可以聊天',
                value: _speakPolicy,
                values: speakPolicies,
                onChanged: (value) => setState(() => _speakPolicy = value),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _formatDate(DateTime? value) {
    if (value == null) return '请选择年月日与时间';
    String two(int number) => number.toString().padLeft(2, '0');
    return '${value.year}年${value.month}月${value.day}日 ${two(value.hour)}:${two(value.minute)}';
  }
}

class _ActivityCard extends StatelessWidget {
  const _ActivityCard({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(18),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Column(children: children),
      ),
    );
  }
}

class _DropdownRow<T> extends StatelessWidget {
  const _DropdownRow({
    super.key,
    required this.title,
    required this.value,
    required this.values,
    required this.onChanged,
    this.label,
  });

  final String title;
  final T value;
  final List<T> values;
  final ValueChanged<T> onChanged;
  final String Function(T value)? label;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      title: Text(title),
      trailing: DropdownButton<T>(
        value: value,
        underline: const SizedBox.shrink(),
        items: [
          for (final item in values)
            DropdownMenuItem<T>(
              value: item,
              child: Text(label?.call(item) ?? '$item'),
            ),
        ],
        onChanged: (value) {
          if (value != null) onChanged(value);
        },
      ),
    );
  }
}

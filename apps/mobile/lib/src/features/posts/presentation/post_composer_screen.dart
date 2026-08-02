import 'package:flutter/material.dart';

class PostComposerScreen extends StatefulWidget {
  const PostComposerScreen({super.key});

  @override
  State<PostComposerScreen> createState() => _PostComposerScreenState();
}

class _PostComposerScreenState extends State<PostComposerScreen> {
  final _bodyController = TextEditingController();
  int _radiusMeters = 1000;
  bool _showPlaceName = true;

  bool get _hasContent => _bodyController.text.trim().isNotEmpty;

  @override
  void dispose() {
    _bodyController.dispose();
    super.dispose();
  }

  Future<void> _close() async {
    if (!_hasContent) {
      Navigator.pop(context);
      return;
    }
    final leave = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('保留这次编辑？'),
        content: const Text('动态草稿持久化将在动态模块接入时启用；现在离开不会发布内容。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('继续编辑'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('离开'),
          ),
        ],
      ),
    );
    if (leave == true && mounted) Navigator.pop(context);
  }

  void _showPending(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_hasContent,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _close();
      },
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(
            tooltip: '取消',
            onPressed: _close,
            icon: const Icon(Icons.close_rounded),
          ),
          title: const Text('发布动态'),
          actions: [
            TextButton(
              onPressed: () => _showPending('动态发布服务接入后即可发布'),
              child: const Text('发布'),
            ),
          ],
        ),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 30),
          children: [
            TextField(
              key: const ValueKey('post-body-field'),
              controller: _bodyController,
              autofocus: true,
              minLines: 5,
              maxLines: 10,
              maxLength: 5000,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                hintText: '分享附近正在发生的事…',
                alignLabelWithHint: true,
              ),
            ),
            const SizedBox(height: 14),
            Material(
              color: Colors.white,
              borderRadius: BorderRadius.circular(18),
              child: InkWell(
                key: const ValueKey('post-add-media'),
                borderRadius: BorderRadius.circular(18),
                onTap: () => _showPending('照片与20秒视频选择将在动态媒体链路中接入'),
                child: const SizedBox(
                  height: 132,
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.add_rounded,
                          size: 42,
                          color: Color(0xFF167A5B),
                        ),
                        SizedBox(height: 5),
                        Text(
                          '照片 / 20秒视频',
                          style: TextStyle(color: Color(0xFF66736D)),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 14),
            _ComposerCard(
              children: [
                ListTile(
                  title: const Text('可见范围'),
                  trailing: DropdownButton<int>(
                    value: _radiusMeters,
                    underline: const SizedBox.shrink(),
                    items: const [
                      DropdownMenuItem(value: 1000, child: Text('1公里')),
                      DropdownMenuItem(value: 3000, child: Text('3公里')),
                      DropdownMenuItem(value: 5000, child: Text('5公里')),
                      DropdownMenuItem(value: 10000, child: Text('10公里')),
                      DropdownMenuItem(value: 30000, child: Text('30公里')),
                    ],
                    onChanged: (value) =>
                        setState(() => _radiusMeters = value!),
                  ),
                ),
                const Divider(height: 1, indent: 16, endIndent: 16),
                SwitchListTile(
                  title: const Text('显示地点名称'),
                  subtitle: const Text('不会展示你的实时位置或与其他用户的距离'),
                  value: _showPlaceName,
                  onChanged: (value) => setState(() => _showPlaceName = value),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ComposerCard extends StatelessWidget {
  const _ComposerCard({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(18),
      clipBehavior: Clip.antiAlias,
      child: Column(children: children),
    );
  }
}

import 'package:flutter/material.dart';

enum ChatComposerPanel { none, emoji, more }

enum ChatAttachmentAction { photo, camera, location, liveLocation }

class ChatComposerController extends ChangeNotifier {
  bool _voiceMode = false;
  ChatComposerPanel _panel = ChatComposerPanel.none;

  bool get voiceMode => _voiceMode;
  ChatComposerPanel get panel => _panel;

  void toggleVoice(FocusNode focusNode) {
    _voiceMode = !_voiceMode;
    _panel = ChatComposerPanel.none;
    if (_voiceMode) {
      focusNode.unfocus();
    } else {
      focusNode.requestFocus();
    }
    notifyListeners();
  }

  void togglePanel(ChatComposerPanel panel, FocusNode focusNode) {
    _voiceMode = false;
    _panel = _panel == panel ? ChatComposerPanel.none : panel;
    focusNode.unfocus();
    notifyListeners();
  }

  void showKeyboard() {
    if (_voiceMode || _panel != ChatComposerPanel.none) {
      _voiceMode = false;
      _panel = ChatComposerPanel.none;
      notifyListeners();
    }
  }

  void dismiss(FocusNode focusNode) {
    focusNode.unfocus();
    if (_panel != ChatComposerPanel.none) {
      _panel = ChatComposerPanel.none;
      notifyListeners();
    }
  }
}

class ChatComposer extends StatefulWidget {
  const ChatComposer({
    required this.controller,
    required this.textController,
    required this.focusNode,
    required this.isSending,
    required this.onSend,
    required this.onUnavailableAction,
    super.key,
  });

  final ChatComposerController controller;
  final TextEditingController textController;
  final FocusNode focusNode;
  final bool isSending;
  final Future<void> Function() onSend;
  final ValueChanged<String> onUnavailableAction;

  @override
  State<ChatComposer> createState() => _ChatComposerState();
}

class _ChatComposerState extends State<ChatComposer> {
  static const _emojis = ['😊', '😂', '👍', '❤️', '🎉', '☕️', '🏸', '👀'];

  @override
  void initState() {
    super.initState();
    widget.textController.addListener(_onTextChanged);
  }

  @override
  void didUpdateWidget(covariant ChatComposer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.textController != widget.textController) {
      oldWidget.textController.removeListener(_onTextChanged);
      widget.textController.addListener(_onTextChanged);
    }
  }

  @override
  void dispose() {
    widget.textController.removeListener(_onTextChanged);
    super.dispose();
  }

  void _onTextChanged() => setState(() {});

  void _insertEmoji(String emoji) {
    final value = widget.textController.value;
    final selection = value.selection;
    final start = selection.isValid ? selection.start : value.text.length;
    final end = selection.isValid ? selection.end : value.text.length;
    final text = value.text.replaceRange(start, end, emoji);
    widget.textController.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: start + emoji.length),
    );
  }

  Future<void> _showLocationChoices() async {
    final action = await showModalBottomSheet<ChatAttachmentAction>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.location_on_outlined),
              title: const Text('发送位置'),
              subtitle: const Text('从地图选择一个固定位置'),
              onTap: () =>
                  Navigator.pop(context, ChatAttachmentAction.location),
            ),
            ListTile(
              leading: const Icon(Icons.my_location_rounded),
              title: const Text('共享实时位置'),
              subtitle: const Text('持续向当前聊天成员共享位置'),
              onTap: () =>
                  Navigator.pop(context, ChatAttachmentAction.liveLocation),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (!mounted || action == null) return;
    widget.onUnavailableAction(
      action == ChatAttachmentAction.location ? '发送位置' : '共享实时位置',
    );
  }

  @override
  Widget build(BuildContext context) {
    final hasText = widget.textController.text.trim().isNotEmpty;
    return SafeArea(
      top: false,
      child: Material(
        color: const Color(0xFFF5F7F6),
        child: AnimatedBuilder(
          animation: widget.controller,
          builder: (context, _) => Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 7, 8, 7),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    _ComposerIconButton(
                      tooltip: widget.controller.voiceMode ? '切换文字' : '语音',
                      icon: widget.controller.voiceMode
                          ? Icons.keyboard_alt_outlined
                          : Icons.mic_none_rounded,
                      onPressed: () =>
                          widget.controller.toggleVoice(widget.focusNode),
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: widget.controller.voiceMode
                          ? _VoiceHoldButton(
                              onLongPress: () =>
                                  widget.onUnavailableAction('语音消息'),
                            )
                          : TextField(
                              controller: widget.textController,
                              focusNode: widget.focusNode,
                              minLines: 1,
                              maxLines: 4,
                              textInputAction: TextInputAction.send,
                              onTap: widget.controller.showKeyboard,
                              onSubmitted: widget.isSending || !hasText
                                  ? null
                                  : (_) => widget.onSend(),
                              decoration: const InputDecoration(
                                hintText: '输入消息',
                                filled: true,
                                fillColor: Colors.white,
                                contentPadding: EdgeInsets.symmetric(
                                  horizontal: 13,
                                  vertical: 10,
                                ),
                              ),
                            ),
                    ),
                    const SizedBox(width: 4),
                    _ComposerIconButton(
                      tooltip: '表情',
                      icon: Icons.sentiment_satisfied_alt_rounded,
                      selected:
                          widget.controller.panel == ChatComposerPanel.emoji,
                      onPressed: () => widget.controller.togglePanel(
                        ChatComposerPanel.emoji,
                        widget.focusNode,
                      ),
                    ),
                    const SizedBox(width: 2),
                    if (hasText && !widget.controller.voiceMode)
                      _ComposerIconButton(
                        tooltip: '发送',
                        icon: Icons.send_rounded,
                        onPressed: widget.isSending ? null : widget.onSend,
                        loading: widget.isSending,
                      )
                    else
                      _ComposerIconButton(
                        tooltip: '更多',
                        icon: Icons.add_circle_outline_rounded,
                        selected:
                            widget.controller.panel == ChatComposerPanel.more,
                        onPressed: () => widget.controller.togglePanel(
                          ChatComposerPanel.more,
                          widget.focusNode,
                        ),
                      ),
                  ],
                ),
              ),
              if (widget.controller.panel == ChatComposerPanel.emoji)
                _EmojiPanel(emojis: _emojis, onSelected: _insertEmoji),
              if (widget.controller.panel == ChatComposerPanel.more)
                _MorePanel(
                  onPhoto: () => widget.onUnavailableAction('发送照片'),
                  onCamera: () => widget.onUnavailableAction('拍摄'),
                  onLocation: _showLocationChoices,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ComposerIconButton extends StatelessWidget {
  const _ComposerIconButton({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
    this.selected = false,
    this.loading = false,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback? onPressed;
  final bool selected;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: tooltip,
      onPressed: onPressed,
      style: IconButton.styleFrom(
        backgroundColor: selected ? const Color(0xFFDDEEE7) : null,
      ),
      icon: loading
          ? const SizedBox.square(
              dimension: 19,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : Icon(icon, color: const Color(0xFF35433D)),
    );
  }
}

class _VoiceHoldButton extends StatelessWidget {
  const _VoiceHoldButton({required this.onLongPress});

  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 46,
      child: Material(
        color: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: const BorderSide(color: Color(0xFFE1E7E3)),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onLongPress: onLongPress,
          child: const Center(
            child: Text(
              '按住  说话',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
        ),
      ),
    );
  }
}

class _EmojiPanel extends StatelessWidget {
  const _EmojiPanel({required this.emojis, required this.onSelected});

  final List<String> emojis;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const ValueKey('chat-emoji-panel'),
      height: 176,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 18),
      decoration: const BoxDecoration(
        color: Color(0xFFF0F3F1),
        border: Border(top: BorderSide(color: Color(0xFFE1E7E3))),
      ),
      child: GridView.builder(
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 8,
          mainAxisSpacing: 8,
          crossAxisSpacing: 8,
        ),
        itemCount: emojis.length,
        itemBuilder: (context, index) => InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: () => onSelected(emojis[index]),
          child: Center(
            child: Text(emojis[index], style: const TextStyle(fontSize: 25)),
          ),
        ),
      ),
    );
  }
}

class _MorePanel extends StatelessWidget {
  const _MorePanel({
    required this.onPhoto,
    required this.onCamera,
    required this.onLocation,
  });

  final VoidCallback onPhoto;
  final VoidCallback onCamera;
  final VoidCallback onLocation;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const ValueKey('chat-more-panel'),
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 24),
      decoration: const BoxDecoration(
        color: Color(0xFFF0F3F1),
        border: Border(top: BorderSide(color: Color(0xFFE1E7E3))),
      ),
      child: Row(
        children: [
          _MoreAction(
            label: '照片',
            icon: Icons.photo_library_outlined,
            onTap: onPhoto,
          ),
          const SizedBox(width: 22),
          _MoreAction(
            label: '拍摄',
            icon: Icons.camera_alt_outlined,
            onTap: onCamera,
          ),
          const SizedBox(width: 22),
          _MoreAction(
            label: '位置',
            icon: Icons.location_on_outlined,
            onTap: onLocation,
          ),
        ],
      ),
    );
  }
}

class _MoreAction extends StatelessWidget {
  const _MoreAction({
    required this.label,
    required this.icon,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: SizedBox(
        width: 64,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 54,
              height: 54,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Icon(icon, color: const Color(0xFF35433D)),
            ),
            const SizedBox(height: 7),
            Text(label, style: const TextStyle(fontSize: 12)),
          ],
        ),
      ),
    );
  }
}

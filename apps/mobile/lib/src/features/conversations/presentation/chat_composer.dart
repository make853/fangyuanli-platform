import 'package:flutter/material.dart';

enum ChatComposerPanel { none, emoji, more }

enum ChatComposerSurface { closed, keyboard, emoji, more, voice }

enum ChatAttachmentAction { photo, camera, location, liveLocation }

class ChatComposerController extends ChangeNotifier {
  ChatComposerSurface _surface = ChatComposerSurface.closed;

  ChatComposerSurface get surface => _surface;
  bool get voiceMode => _surface == ChatComposerSurface.voice;
  ChatComposerPanel get panel => switch (_surface) {
    ChatComposerSurface.emoji => ChatComposerPanel.emoji,
    ChatComposerSurface.more => ChatComposerPanel.more,
    _ => ChatComposerPanel.none,
  };

  void toggleVoice(FocusNode focusNode) {
    if (_surface == ChatComposerSurface.voice) {
      _setSurface(ChatComposerSurface.keyboard);
      focusNode.requestFocus();
    } else {
      _setSurface(ChatComposerSurface.voice);
      focusNode.unfocus();
    }
  }

  void showPanel(ChatComposerPanel panel, FocusNode focusNode) {
    final surface = switch (panel) {
      ChatComposerPanel.emoji => ChatComposerSurface.emoji,
      ChatComposerPanel.more => ChatComposerSurface.more,
      ChatComposerPanel.none => ChatComposerSurface.closed,
    };
    _setSurface(surface);
    focusNode.unfocus();
  }

  void showKeyboard(FocusNode focusNode) {
    _setSurface(ChatComposerSurface.keyboard);
    focusNode.requestFocus();
  }

  void dismiss(FocusNode focusNode) {
    focusNode.unfocus();
    _setSurface(ChatComposerSurface.closed);
  }

  void _setSurface(ChatComposerSurface next) {
    if (_surface == next) return;
    _surface = next;
    notifyListeners();
  }
}

class ChatComposer extends StatefulWidget {
  const ChatComposer({
    required this.controller,
    required this.textController,
    required this.focusNode,
    required this.onSend,
    required this.onUnavailableAction,
    this.bottomChromeHeight = 0,
    super.key,
  });

  final ChatComposerController controller;
  final TextEditingController textController;
  final FocusNode focusNode;
  final Future<void> Function() onSend;
  final ValueChanged<String> onUnavailableAction;

  /// Space already occupied below this chat body, such as HomeShell's bottom
  /// navigation bar. The platform keyboard covers that chrome, while a custom
  /// panel is laid out above it, so both surfaces must subtract the same value
  /// to keep the composer at one visual position.
  final double bottomChromeHeight;

  @override
  State<ChatComposer> createState() => _ChatComposerState();
}

class _ChatComposerState extends State<ChatComposer>
    with SingleTickerProviderStateMixin {
  static const _emojis = ['😊', '😂', '👍', '❤️', '🎉', '☕️', '🏸', '👀'];
  static const _fallbackInputSurfaceHeight = 300.0;
  static const _keyboardSettledTolerance = 0.5;
  static const _panelOpenDuration = Duration(milliseconds: 250);
  static const _panelCloseDuration = Duration(milliseconds: 220);
  bool _submissionInFlight = false;
  ChatComposerSurface _previousSurface = ChatComposerSurface.closed;
  ChatComposerPanel _renderedPanel = ChatComposerPanel.none;
  double _reservedInputSurfaceHeight = _fallbackInputSurfaceHeight;
  double _keyboardInset = 0;
  double _lastKeyboardHeight = 0;
  bool _transitioningToKeyboard = false;
  bool _panelAnimationOwnsExtent = false;
  late final AnimationController _panelAnimationController;
  late final Animation<double> _panelAnimation;

  @override
  void initState() {
    super.initState();
    _panelAnimationController = AnimationController(
      vsync: this,
      duration: _panelOpenDuration,
      reverseDuration: _panelCloseDuration,
    );
    _panelAnimation = CurvedAnimation(
      parent: _panelAnimationController,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );
    _panelAnimationController.addStatusListener(_onPanelAnimationStatusChanged);
    _previousSurface = widget.controller.surface;
    widget.controller.addListener(_onSurfaceChanged);
    widget.textController.addListener(_onTextChanged);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _applyKeyboardInset(
      _effectiveKeyboardInset(MediaQuery.viewInsetsOf(context).bottom),
    );
  }

  @override
  void didUpdateWidget(covariant ChatComposer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onSurfaceChanged);
      _previousSurface = widget.controller.surface;
      widget.controller.addListener(_onSurfaceChanged);
    }
    if (oldWidget.textController != widget.textController) {
      oldWidget.textController.removeListener(_onTextChanged);
      widget.textController.addListener(_onTextChanged);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onSurfaceChanged);
    widget.textController.removeListener(_onTextChanged);
    _panelAnimationController.removeStatusListener(
      _onPanelAnimationStatusChanged,
    );
    _panelAnimationController.dispose();
    super.dispose();
  }

  double _readKeyboardInset() {
    if (!mounted) return 0;
    return _effectiveKeyboardInset(MediaQuery.viewInsetsOf(context).bottom);
  }

  double _effectiveKeyboardInset(double rawInset) =>
      (rawInset - widget.bottomChromeHeight).clamp(0, double.infinity);

  void _applyKeyboardInset(double nextInset) {
    if ((nextInset - _keyboardInset).abs() < 0.5) return;
    _keyboardInset = nextInset;
    if (nextInset > 0 &&
        widget.controller.surface == ChatComposerSurface.keyboard) {
      _lastKeyboardHeight = nextInset;
    }
    if (_transitioningToKeyboard &&
        nextInset >= _reservedInputSurfaceHeight - _keyboardSettledTolerance) {
      _renderedPanel = ChatComposerPanel.none;
      _transitioningToKeyboard = false;
    }
  }

  void _onSurfaceChanged() {
    if (!mounted) return;
    final nextSurface = widget.controller.surface;
    final previous = _previousSurface;
    _previousSurface = nextSurface;
    final nextPanel = _panelForSurface(nextSurface);
    final previousPanel = _panelForSurface(previous);
    final currentInset = _readKeyboardInset();
    var expandPanelImmediately = false;
    var animatePanelOpen = false;
    var animatePanelClosed = false;

    setState(() {
      _keyboardInset = currentInset;
      if (currentInset > 0) {
        _lastKeyboardHeight = currentInset;
      }

      if (nextPanel != ChatComposerPanel.none) {
        _reservedInputSurfaceHeight = currentInset > 0
            ? currentInset
            : (_lastKeyboardHeight > 0
                  ? _lastKeyboardHeight
                  : _fallbackInputSurfaceHeight);
        _renderedPanel = nextPanel;
        _transitioningToKeyboard = false;
        if (currentInset > 0) {
          _panelAnimationOwnsExtent = false;
          expandPanelImmediately = true;
        } else if (previousPanel == ChatComposerPanel.none) {
          _panelAnimationOwnsExtent = true;
          animatePanelOpen = true;
        }
        return;
      }

      if (nextSurface == ChatComposerSurface.keyboard &&
          previousPanel != ChatComposerPanel.none) {
        if (_panelAnimationOwnsExtent) {
          _reservedInputSurfaceHeight =
              _reservedInputSurfaceHeight * _panelAnimation.value;
        }
        _renderedPanel = previousPanel;
        _transitioningToKeyboard = true;
        _panelAnimationOwnsExtent = false;
        expandPanelImmediately = true;
        return;
      }

      if (previousPanel != ChatComposerPanel.none && currentInset <= 0.5) {
        _transitioningToKeyboard = false;
        _panelAnimationOwnsExtent = true;
        animatePanelClosed = true;
        return;
      }

      _renderedPanel = ChatComposerPanel.none;
      _transitioningToKeyboard = false;
      _panelAnimationOwnsExtent = false;
    });

    if (expandPanelImmediately) {
      _panelAnimationController.value = 1;
    } else if (animatePanelOpen) {
      _panelAnimationController.forward();
    } else if (animatePanelClosed) {
      _panelAnimationController.reverse();
    }
  }

  void _onPanelAnimationStatusChanged(AnimationStatus status) {
    if (!mounted ||
        status != AnimationStatus.dismissed ||
        widget.controller.panel != ChatComposerPanel.none ||
        _transitioningToKeyboard ||
        _renderedPanel == ChatComposerPanel.none) {
      return;
    }
    setState(() {
      _renderedPanel = ChatComposerPanel.none;
      _panelAnimationOwnsExtent = false;
    });
  }

  ChatComposerPanel _panelForSurface(ChatComposerSurface surface) =>
      switch (surface) {
        ChatComposerSurface.emoji => ChatComposerPanel.emoji,
        ChatComposerSurface.more => ChatComposerPanel.more,
        _ => ChatComposerPanel.none,
      };

  double _visiblePanelHeight(double currentKeyboardInset) {
    if (_renderedPanel == ChatComposerPanel.none) return 0;
    final complement = (_reservedInputSurfaceHeight - currentKeyboardInset)
        .clamp(0, _reservedInputSurfaceHeight)
        .toDouble();
    return _panelAnimationOwnsExtent
        ? complement * _panelAnimation.value
        : complement;
  }

  double _occupiedSurfaceHeight({
    required double currentKeyboardInset,
    required double restingBottomInset,
  }) {
    if (_renderedPanel != ChatComposerPanel.none) {
      if (_panelAnimationOwnsExtent) {
        final collapsedExtent = currentKeyboardInset > restingBottomInset
            ? currentKeyboardInset
            : restingBottomInset;
        final expandedExtent = _reservedInputSurfaceHeight > collapsedExtent
            ? _reservedInputSurfaceHeight
            : collapsedExtent;
        return collapsedExtent +
            (expandedExtent - collapsedExtent) * _panelAnimation.value;
      }
      return _reservedInputSurfaceHeight > currentKeyboardInset
          ? _reservedInputSurfaceHeight
          : currentKeyboardInset;
    }
    if (currentKeyboardInset > 0) return currentKeyboardInset;
    return restingBottomInset;
  }

  void _onTextChanged() => setState(() {});

  Future<void> _submit() async {
    if (_submissionInFlight || widget.textController.text.trim().isEmpty) {
      return;
    }
    setState(() => _submissionInFlight = true);
    try {
      await widget.onSend();
    } finally {
      if (mounted) {
        setState(() => _submissionInFlight = false);
      }
    }
  }

  void _insertText(String insertion) {
    final value = widget.textController.value;
    final selection = value.selection;
    final start = selection.isValid ? selection.start : value.text.length;
    final end = selection.isValid ? selection.end : value.text.length;
    final text = value.text.replaceRange(start, end, insertion);
    widget.textController.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: start + insertion.length),
    );
  }

  void _insertEmoji(String emoji) => _insertText(emoji);

  Widget _buildTextContextMenu(
    BuildContext context,
    EditableTextState editableTextState,
  ) {
    void insertNewline() {
      editableTextState.hideToolbar();
      _insertText('\n');
      widget.focusNode.requestFocus();
    }

    if (SystemContextMenu.isSupportedByField(editableTextState)) {
      final items = SystemContextMenu.getDefaultItems(editableTextState)
          .where(
            (item) =>
                item is IOSSystemContextMenuItemCut ||
                item is IOSSystemContextMenuItemCopy ||
                item is IOSSystemContextMenuItemPaste ||
                item is IOSSystemContextMenuItemSelectAll,
          )
          .toList();
      if (!items.any((item) => item is IOSSystemContextMenuItemPaste)) {
        items.add(const IOSSystemContextMenuItemPaste());
      }
      items.add(
        IOSSystemContextMenuItemCustom(title: '换行', onPressed: insertNewline),
      );
      return SystemContextMenu.editableText(
        editableTextState: editableTextState,
        items: items,
      );
    }

    const editingTypes = {
      ContextMenuButtonType.cut,
      ContextMenuButtonType.copy,
      ContextMenuButtonType.paste,
      ContextMenuButtonType.selectAll,
    };
    final nativeItems = editableTextState.contextMenuButtonItems
        .where((item) => editingTypes.contains(item.type))
        .toList();
    final buttonItems = <ContextMenuButtonItem>[
      ...nativeItems,
      if (!nativeItems.any((item) => item.type == ContextMenuButtonType.paste))
        ContextMenuButtonItem(
          type: ContextMenuButtonType.paste,
          onPressed: () =>
              editableTextState.pasteText(SelectionChangedCause.toolbar),
        ),
      ContextMenuButtonItem(label: '换行', onPressed: insertNewline),
    ];
    return AdaptiveTextSelectionToolbar.buttonItems(
      anchors: editableTextState.contextMenuAnchors,
      buttonItems: buttonItems,
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
    final currentKeyboardInset = _effectiveKeyboardInset(
      MediaQuery.viewInsetsOf(context).bottom,
    );
    final restingBottomInset = widget.bottomChromeHeight > 0
        ? 0.0
        : MediaQuery.viewPaddingOf(context).bottom;
    final hasText = widget.textController.text.trim().isNotEmpty;
    final isSending = _submissionInFlight;
    final emojiSelected =
        widget.controller.surface == ChatComposerSurface.emoji;
    final moreSelected = widget.controller.surface == ChatComposerSurface.more;
    return Material(
      color: const Color(0xFFF5F7F6),
      child: AnimatedBuilder(
        animation: _panelAnimation,
        builder: (context, _) {
          final visiblePanelHeight = _visiblePanelHeight(currentKeyboardInset);
          final occupiedSurfaceHeight = _occupiedSurfaceHeight(
            currentKeyboardInset: currentKeyboardInset,
            restingBottomInset: restingBottomInset,
          );
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                key: const ValueKey('chat-composer-toolbar'),
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
                              contextMenuBuilder: _buildTextContextMenu,
                              onTap: () => widget.controller.showKeyboard(
                                widget.focusNode,
                              ),
                              // Keep iOS' native keyboard visible after the
                              // send action. Both send entry points share the
                              // same guarded submission path below.
                              onEditingComplete: () {},
                              onSubmitted: (_) => _submit(),
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
                      tooltip: emojiSelected ? '切换键盘' : '表情',
                      icon: emojiSelected
                          ? Icons.keyboard_alt_outlined
                          : Icons.sentiment_satisfied_alt_rounded,
                      selected: emojiSelected,
                      onPressed: () => emojiSelected
                          ? widget.controller.showKeyboard(widget.focusNode)
                          : widget.controller.showPanel(
                              ChatComposerPanel.emoji,
                              widget.focusNode,
                            ),
                    ),
                    const SizedBox(width: 2),
                    if (hasText && !widget.controller.voiceMode)
                      _ComposerIconButton(
                        tooltip: '发送',
                        icon: Icons.send_rounded,
                        onPressed: isSending ? null : _submit,
                      )
                    else
                      _ComposerIconButton(
                        tooltip: '更多',
                        icon: Icons.add_circle_outline_rounded,
                        selected: moreSelected,
                        onPressed: () => moreSelected
                            ? widget.controller.showKeyboard(widget.focusNode)
                            : widget.controller.showPanel(
                                ChatComposerPanel.more,
                                widget.focusNode,
                              ),
                      ),
                  ],
                ),
              ),
              _InputPanelViewport(
                height: occupiedSurfaceHeight,
                panelHeight: visiblePanelHeight,
                child: switch (_renderedPanel) {
                  ChatComposerPanel.emoji => _EmojiPanel(
                    emojis: _emojis,
                    onSelected: _insertEmoji,
                  ),
                  ChatComposerPanel.more => _MorePanel(
                    onPhoto: () => widget.onUnavailableAction('发送照片'),
                    onCamera: () => widget.onUnavailableAction('拍摄'),
                    onLocation: _showLocationChoices,
                  ),
                  ChatComposerPanel.none => const SizedBox.shrink(),
                },
              ),
            ],
          );
        },
      ),
    );
  }
}

class _InputPanelViewport extends StatelessWidget {
  const _InputPanelViewport({
    required this.height,
    required this.panelHeight,
    required this.child,
  });

  final double height;
  final double panelHeight;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (height <= 0) return const SizedBox.shrink();
    return SizedBox(
      key: const ValueKey('chat-input-reserved-surface'),
      width: double.infinity,
      height: height,
      child: Align(
        alignment: Alignment.topCenter,
        child: panelHeight <= 0
            ? const SizedBox.shrink()
            : ClipRect(
                child: SizedBox(
                  key: const ValueKey('chat-input-surface'),
                  width: double.infinity,
                  height: panelHeight,
                  child: child,
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
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback? onPressed;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: tooltip,
      onPressed: onPressed,
      style: IconButton.styleFrom(
        backgroundColor: selected ? const Color(0xFFDDEEE7) : null,
      ),
      icon: Icon(icon, color: const Color(0xFF35433D)),
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
    return NotificationListener<ScrollNotification>(
      onNotification: (_) => true,
      child: Container(
        key: const ValueKey('chat-emoji-panel'),
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 18),
        decoration: const BoxDecoration(
          color: Color(0xFFF0F3F1),
          border: Border(top: BorderSide(color: Color(0xFFE1E7E3))),
        ),
        child: GridView.builder(
          primary: false,
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

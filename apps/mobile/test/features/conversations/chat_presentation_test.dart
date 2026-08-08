import 'dart:async';

import 'package:fangyuanli_mobile/src/core/theme/app_theme.dart';
import 'package:fangyuanli_mobile/src/features/conversations/application/conversation_sync_controller.dart';
import 'package:fangyuanli_mobile/src/features/conversations/domain/community_chat_models.dart';
import 'package:fangyuanli_mobile/src/features/conversations/domain/conversation_message.dart';
import 'package:fangyuanli_mobile/src/features/conversations/presentation/chat_composer.dart';
import 'package:fangyuanli_mobile/src/features/conversations/presentation/chat_message_bubble.dart';
import 'package:fangyuanli_mobile/src/features/conversations/presentation/chat_message_timeline.dart';
import 'package:fangyuanli_mobile/src/features/conversations/presentation/chat_time.dart';
import 'package:fangyuanli_mobile/src/features/conversations/presentation/community_chat_screen.dart';
import 'package:fangyuanli_mobile/src/features/conversations/presentation/direct_chat_settings_screen.dart';
import 'package:fangyuanli_mobile/src/features/friends/application/friends_controller.dart';
import 'package:fangyuanli_mobile/src/features/friends/data/relationship_repository.dart';
import 'package:fangyuanli_mobile/src/features/friends/domain/friend_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('顶栏不会因聊天列表滚动状态改变颜色', () {
    final appBarTheme = AppTheme.light().appBarTheme;

    expect(appBarTheme.scrolledUnderElevation, 0);
    expect(appBarTheme.surfaceTintColor, Colors.transparent);
  });

  testWidgets('本人消息显示右侧头像且不额外显示“我”', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh', 'CN'),
        supportedLocales: const [Locale('zh', 'CN')],
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
        ],
        home: Scaffold(
          body: ChatMessageBubble(
            text: '收到',
            deliveryState: 'sent',
            isMine: true,
            avatarInitial: '桃',
            onAvatarTap: () {},
          ),
        ),
      ),
    );

    final bubble = tester.getCenter(
      find.byKey(const ValueKey('message-bubble')),
    );
    final avatar = tester.getCenter(
      find.byKey(const ValueKey('message-avatar-mine')),
    );
    expect(avatar.dx, greaterThan(bubble.dx));
    expect(find.text('收到'), findsOneWidget);
    expect(find.text('我'), findsNothing);
  });

  testWidgets('聊天气泡按需显示居中的时间分隔', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: ChatMessageBubble(
            text: '五分钟后再发一条',
            deliveryState: 'sent',
            isMine: false,
            avatarInitial: '桃',
            timestampLabel: '10:35',
          ),
        ),
      ),
    );

    expect(find.byKey(const ValueKey('message-time-divider')), findsOneWidget);
    expect(find.text('10:35'), findsOneWidget);
  });

  testWidgets('发送失败只显示红色重试入口且点击后重新发送', (tester) async {
    var retryCount = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ChatMessageBubble(
            text: '离线消息',
            deliveryState: 'failed',
            isMine: true,
            avatarInitial: '我',
            onRetry: () => retryCount += 1,
          ),
        ),
      ),
    );

    expect(find.text('发送失败'), findsNothing);
    expect(find.byKey(const ValueKey('message-retry-button')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('message-retry-button')));
    expect(retryCount, 1);
  });

  test('聊天时间五分钟分段，并按日期显示', () {
    final previous = DateTime(2026, 8, 2, 10, 0);
    expect(
      ChatTimePresentation.shouldShowDivider(
        DateTime(2026, 8, 2, 10, 4),
        previous,
      ),
      isFalse,
    );
    expect(
      ChatTimePresentation.shouldShowDivider(
        DateTime(2026, 8, 2, 10, 5),
        previous,
      ),
      isTrue,
    );
    expect(
      ChatTimePresentation.format(
        DateTime(2026, 8, 1, 9, 8),
        now: DateTime(2026, 8, 2, 12),
      ),
      '昨天 09:08',
    );
  });

  testWidgets('输入栏可切换语音、连续选择表情并打开更多面板', (tester) async {
    final composerController = ChatComposerController();
    final textController = TextEditingController();
    final focusNode = FocusNode();
    final unavailable = <String>[];

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh', 'CN'),
        supportedLocales: const [Locale('zh', 'CN')],
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
        ],
        home: Scaffold(
          resizeToAvoidBottomInset: false,
          body: Align(
            alignment: Alignment.bottomCenter,
            child: ChatComposer(
              controller: composerController,
              textController: textController,
              focusNode: focusNode,
              onSend: () async {},
              onUnavailableAction: unavailable.add,
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.byTooltip('语音'));
    await tester.pump();
    expect(find.text('按住  说话'), findsOneWidget);

    await tester.tap(find.byTooltip('切换文字'));
    await tester.tap(find.byTooltip('表情'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('chat-emoji-panel')), findsOneWidget);

    await tester.tap(find.text('😊'));
    await tester.tap(find.text('😂'));
    await tester.pump();
    expect(textController.text, '😊😂');
    expect(find.byKey(const ValueKey('chat-emoji-panel')), findsOneWidget);

    textController.clear();
    await tester.pump();
    await tester.tap(find.byTooltip('更多'));
    await tester.pump();
    expect(find.byKey(const ValueKey('chat-more-panel')), findsOneWidget);
    await tester.tap(find.text('照片'));
    expect(unavailable, contains('发送照片'));

    composerController.dispose();
    textController.dispose();
    focusNode.dispose();
  });

  testWidgets('输入框长按菜单可在光标位置插入换行', (tester) async {
    final composerController = ChatComposerController();
    final textController = TextEditingController(text: '第一行');
    textController.selection = TextSelection.collapsed(
      offset: textController.text.length,
    );
    final focusNode = FocusNode();

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh', 'CN'),
        supportedLocales: const [Locale('zh', 'CN')],
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
        ],
        home: Scaffold(
          body: Align(
            alignment: Alignment.bottomCenter,
            child: ChatComposer(
              controller: composerController,
              textController: textController,
              focusNode: focusNode,
              onSend: () async {},
              onUnavailableAction: (_) {},
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.byType(TextField));
    final editableTextState = tester.state<EditableTextState>(
      find.byType(EditableText),
    );
    editableTextState.showToolbar();
    await tester.pumpAndSettle();

    expect(find.text('粘贴'), findsOneWidget);
    expect(find.text('换行'), findsOneWidget);
    await tester.tap(find.text('换行'));
    await tester.pump();
    expect(textController.text, '第一行\n');
    expect(textController.selection.baseOffset, textController.text.length);

    await tester.pumpWidget(const SizedBox.shrink());
    composerController.dispose();
    textController.dispose();
    focusNode.dispose();
  });

  testWidgets('输入框选中文字时保留剪切复制粘贴功能', (tester) async {
    final composerController = ChatComposerController();
    final textController = TextEditingController(text: '可复制文字');
    final focusNode = FocusNode();

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh', 'CN'),
        supportedLocales: const [Locale('zh', 'CN')],
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
        ],
        home: Scaffold(
          body: ChatComposer(
            controller: composerController,
            textController: textController,
            focusNode: focusNode,
            onSend: () async {},
            onUnavailableAction: (_) {},
          ),
        ),
      ),
    );

    await tester.tap(find.byType(TextField));
    textController.selection = TextSelection(
      baseOffset: 0,
      extentOffset: textController.text.length,
    );
    await tester.pump();
    final editableTextState = tester.state<EditableTextState>(
      find.byType(EditableText),
    );
    editableTextState.showToolbar();
    await tester.pumpAndSettle();

    expect(find.text('剪切'), findsOneWidget);
    expect(find.text('复制'), findsOneWidget);
    expect(find.text('粘贴'), findsOneWidget);
    expect(find.text('换行'), findsOneWidget);
    expect(find.textContaining('查询'), findsNothing);
    expect(find.textContaining('搜索'), findsNothing);
    expect(find.textContaining('共享'), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
    composerController.dispose();
    textController.dispose();
    focusNode.dispose();
  });

  testWidgets('从表情面板发送后保持面板且不重新弹出系统键盘', (tester) async {
    String? sentValue;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CommunityChatBody(
            channel: const CommunityChannelDescriptor(
              id: 'plaza-emoji',
              kind: CommunityChannelKind.plaza,
              title: '测试广场',
              subtitle: '主广场',
              emptyMessage: '暂无消息',
            ),
            showPreviewNotice: false,
            liveState: const ConversationChatState(),
            currentUserId: 'user-a',
            onSend: (value) async {
              sentValue = value;
              return true;
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byType(TextField));
    await tester.pump();
    expect(tester.testTextInput.isVisible, isTrue);

    await tester.tap(find.byTooltip('表情'));
    await tester.pumpAndSettle();
    expect(tester.testTextInput.isVisible, isFalse);

    await tester.tap(find.text('❤️'));
    await tester.pump();
    await tester.tap(find.byTooltip('发送'));
    await tester.pumpAndSettle();

    expect(sentValue, '❤️');
    expect(find.byKey(const ValueKey('chat-emoji-panel')), findsOneWidget);
    expect(tester.testTextInput.isVisible, isFalse);
  });

  testWidgets('表情面板从统一输入底座平滑打开和关闭', (tester) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final composerController = ChatComposerController();
    final textController = TextEditingController();
    final focusNode = FocusNode();
    addTearDown(composerController.dispose);
    addTearDown(textController.dispose);
    addTearDown(focusNode.dispose);

    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(viewPadding: EdgeInsets.only(bottom: 34)),
        child: MaterialApp(
          home: Scaffold(
            resizeToAvoidBottomInset: false,
            body: Align(
              alignment: Alignment.bottomCenter,
              child: ChatComposer(
                controller: composerController,
                textController: textController,
                focusNode: focusNode,
                onSend: () async {},
                onUnavailableAction: (_) {},
              ),
            ),
          ),
        ),
      ),
    );

    double reservedHeight() => tester
        .getSize(find.byKey(const ValueKey('chat-input-reserved-surface')))
        .height;

    expect(reservedHeight(), 34);

    composerController.showPanel(ChatComposerPanel.emoji, focusNode);
    await tester.pump();
    expect(reservedHeight(), 34);

    await tester.pump(const Duration(milliseconds: 125));
    expect(reservedHeight(), greaterThan(34));
    expect(reservedHeight(), lessThan(300));

    await tester.pumpAndSettle();
    expect(reservedHeight(), 300);
    expect(find.byKey(const ValueKey('chat-emoji-panel')), findsOneWidget);

    composerController.dismiss(focusNode);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 110));
    expect(reservedHeight(), greaterThan(34));
    expect(reservedHeight(), lessThan(300));

    await tester.pumpAndSettle();
    expect(reservedHeight(), 34);
    expect(find.byKey(const ValueKey('chat-emoji-panel')), findsNothing);
  });

  testWidgets('键盘切换历史不会让表情或更多面板跳过打开动画', (tester) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final composerController = ChatComposerController();
    final textController = TextEditingController();
    final focusNode = FocusNode();
    final keyboardInset = ValueNotifier(0.0);
    addTearDown(composerController.dispose);
    addTearDown(textController.dispose);
    addTearDown(focusNode.dispose);
    addTearDown(keyboardInset.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: ValueListenableBuilder<double>(
          valueListenable: keyboardInset,
          builder: (context, inset, _) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              viewPadding: const EdgeInsets.only(bottom: 34),
              viewInsets: EdgeInsets.only(bottom: inset),
            ),
            child: Scaffold(
              resizeToAvoidBottomInset: false,
              body: Align(
                alignment: Alignment.bottomCenter,
                child: ChatComposer(
                  controller: composerController,
                  textController: textController,
                  focusNode: focusNode,
                  onSend: () async {},
                  onUnavailableAction: (_) {},
                ),
              ),
            ),
          ),
        ),
      ),
    );

    double reservedHeight() => tester
        .getSize(find.byKey(const ValueKey('chat-input-reserved-surface')))
        .height;

    for (final target in <ChatComposerPanel>[
      ChatComposerPanel.emoji,
      ChatComposerPanel.more,
    ]) {
      final seed = target == ChatComposerPanel.emoji
          ? ChatComposerPanel.more
          : ChatComposerPanel.emoji;
      if (composerController.surface != ChatComposerSurface.closed) {
        composerController.dismiss(focusNode);
        await tester.pumpAndSettle();
      }

      // A completed custom panel -> keyboard handoff used to leave the shared
      // animation controller at 1. Closing that keyboard and opening another
      // panel then either jumped instantly or appeared to ignore the request.
      composerController.showPanel(seed, focusNode);
      await tester.pumpAndSettle();
      composerController.showKeyboard(focusNode);
      await tester.pump();
      keyboardInset.value = 300;
      await tester.pump();
      composerController.dismiss(focusNode);
      await tester.pump();
      keyboardInset.value = 0;
      await tester.pump();

      expect(reservedHeight(), 34);
      composerController.showPanel(target, focusNode);
      await tester.pump();
      expect(reservedHeight(), 34);

      await tester.pump(const Duration(milliseconds: 125));
      expect(
        find.byKey(
          ValueKey(
            target == ChatComposerPanel.emoji
                ? 'chat-emoji-panel'
                : 'chat-more-panel',
          ),
        ),
        findsOneWidget,
      );
      expect(reservedHeight(), greaterThan(34));
      expect(reservedHeight(), lessThan(300));

      await tester.pumpAndSettle();
      expect(reservedHeight(), 300);
      expect(
        find.byKey(
          ValueKey(
            target == ChatComposerPanel.emoji
                ? 'chat-emoji-panel'
                : 'chat-more-panel',
          ),
        ),
        findsOneWidget,
      );
    }
  });

  testWidgets('面板收起过程中新的表情或更多指令不会被旧动画吞掉', (tester) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final composerController = ChatComposerController();
    final textController = TextEditingController();
    final focusNode = FocusNode();
    addTearDown(composerController.dispose);
    addTearDown(textController.dispose);
    addTearDown(focusNode.dispose);

    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(viewPadding: EdgeInsets.only(bottom: 34)),
        child: MaterialApp(
          home: Scaffold(
            resizeToAvoidBottomInset: false,
            body: Align(
              alignment: Alignment.bottomCenter,
              child: ChatComposer(
                controller: composerController,
                textController: textController,
                focusNode: focusNode,
                onSend: () async {},
                onUnavailableAction: (_) {},
              ),
            ),
          ),
        ),
      ),
    );

    double reservedHeight() => tester
        .getSize(find.byKey(const ValueKey('chat-input-reserved-surface')))
        .height;

    for (final target in <ChatComposerPanel>[
      ChatComposerPanel.emoji,
      ChatComposerPanel.more,
      ChatComposerPanel.emoji,
      ChatComposerPanel.more,
    ]) {
      composerController.showPanel(target, focusNode);
      await tester.pump(const Duration(milliseconds: 90));
      composerController.dismiss(focusNode);
      await tester.pump(const Duration(milliseconds: 70));
      final heightBeforeReopen = reservedHeight();
      composerController.showPanel(target, focusNode);
      await tester.pump();
      expect(reservedHeight(), closeTo(heightBeforeReopen, 0.5));
      await tester.pumpAndSettle();

      expect(
        find.byKey(
          ValueKey(
            target == ChatComposerPanel.emoji
                ? 'chat-emoji-panel'
                : 'chat-more-panel',
          ),
        ),
        findsOneWidget,
      );

      composerController.dismiss(focusNode);
      await tester.pumpAndSettle();
    }
  });

  testWidgets('键盘退场尾帧不会把表情或更多面板压成零高度', (tester) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final composerController = ChatComposerController();
    final textController = TextEditingController();
    final focusNode = FocusNode();
    final keyboardInset = ValueNotifier(0.0);
    addTearDown(composerController.dispose);
    addTearDown(textController.dispose);
    addTearDown(focusNode.dispose);
    addTearDown(keyboardInset.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: ValueListenableBuilder<double>(
          valueListenable: keyboardInset,
          builder: (context, inset, _) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              viewPadding: const EdgeInsets.only(bottom: 34),
              viewInsets: EdgeInsets.only(bottom: inset),
            ),
            child: Scaffold(
              resizeToAvoidBottomInset: false,
              body: Align(
                alignment: Alignment.bottomCenter,
                child: ChatComposer(
                  controller: composerController,
                  textController: textController,
                  focusNode: focusNode,
                  onSend: () async {},
                  onUnavailableAction: (_) {},
                ),
              ),
            ),
          ),
        ),
      ),
    );

    double reservedHeight() => tester
        .getSize(find.byKey(const ValueKey('chat-input-reserved-surface')))
        .height;

    for (final target in <ChatComposerPanel>[
      ChatComposerPanel.emoji,
      ChatComposerPanel.more,
    ]) {
      composerController.showKeyboard(focusNode);
      await tester.pump();
      keyboardInset.value = 300;
      await tester.pump();
      expect(focusNode.hasFocus, isTrue);

      composerController.dismiss(focusNode);
      await tester.pump();
      keyboardInset.value = 12;
      await tester.pump();
      expect(focusNode.hasFocus, isFalse);
      expect(composerController.surface, ChatComposerSurface.closed);

      composerController.showPanel(target, focusNode);
      await tester.pump();
      expect(composerController.panel, target);
      expect(reservedHeight(), 34);

      await tester.pump(const Duration(milliseconds: 125));
      expect(
        find.byKey(
          ValueKey(
            target == ChatComposerPanel.emoji
                ? 'chat-emoji-panel'
                : 'chat-more-panel',
          ),
        ),
        findsOneWidget,
      );
      expect(reservedHeight(), greaterThan(34));
      expect(reservedHeight(), lessThan(300));

      keyboardInset.value = 0;
      await tester.pumpAndSettle();
      expect(reservedHeight(), 300);
      expect(
        find.byKey(
          ValueKey(
            target == ChatComposerPanel.emoji
                ? 'chat-emoji-panel'
                : 'chat-more-panel',
          ),
        ),
        findsOneWidget,
      );

      composerController.dismiss(focusNode);
      await tester.pumpAndSettle();
    }
  });

  testWidgets('键盘和表情面板交接时总占位保持稳定', (tester) async {
    final composerController = ChatComposerController();
    final textController = TextEditingController();
    final focusNode = FocusNode();
    final keyboardInset = ValueNotifier(300.0);
    addTearDown(composerController.dispose);
    addTearDown(textController.dispose);
    addTearDown(focusNode.dispose);
    addTearDown(keyboardInset.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ValueListenableBuilder<double>(
            valueListenable: keyboardInset,
            builder: (context, inset, _) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(viewInsets: EdgeInsets.only(bottom: inset)),
              child: Align(
                alignment: Alignment.bottomCenter,
                child: ChatComposer(
                  controller: composerController,
                  textController: textController,
                  focusNode: focusNode,
                  onSend: () async {},
                  onUnavailableAction: (_) {},
                ),
              ),
            ),
          ),
        ),
      ),
    );

    composerController.showKeyboard(focusNode);
    await tester.pump();
    composerController.showPanel(ChatComposerPanel.emoji, focusNode);
    await tester.pump();
    expect(find.byKey(const ValueKey('chat-input-surface')), findsNothing);

    keyboardInset.value = 150;
    await tester.pump();
    expect(
      tester.getSize(find.byKey(const ValueKey('chat-input-surface'))).height,
      150,
    );

    keyboardInset.value = 0;
    await tester.pump();
    expect(
      tester.getSize(find.byKey(const ValueKey('chat-input-surface'))).height,
      300,
    );
    expect(find.byKey(const ValueKey('chat-emoji-panel')), findsOneWidget);
    expect(find.byTooltip('切换键盘'), findsOneWidget);

    composerController.showKeyboard(focusNode);
    await tester.pump();
    keyboardInset.value = 150;
    await tester.pump();
    expect(
      tester.getSize(find.byKey(const ValueKey('chat-input-surface'))).height,
      150,
    );

    keyboardInset.value = 300;
    await tester.pump();
    expect(find.byKey(const ValueKey('chat-input-surface')), findsNothing);
    expect(find.byKey(const ValueKey('chat-emoji-panel')), findsNothing);
  });

  testWidgets('键盘高度变化与同帧 MediaQuery 布局保持同步', (tester) async {
    final composerController = ChatComposerController();
    final textController = TextEditingController();
    final focusNode = FocusNode();
    final keyboardInset = ValueNotifier(300.0);
    addTearDown(composerController.dispose);
    addTearDown(textController.dispose);
    addTearDown(focusNode.dispose);
    addTearDown(keyboardInset.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ValueListenableBuilder<double>(
            valueListenable: keyboardInset,
            builder: (context, inset, _) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(viewInsets: EdgeInsets.only(bottom: inset)),
              child: Align(
                alignment: Alignment.bottomCenter,
                child: ChatComposer(
                  controller: composerController,
                  textController: textController,
                  focusNode: focusNode,
                  onSend: () async {},
                  onUnavailableAction: (_) {},
                ),
              ),
            ),
          ),
        ),
      ),
    );

    composerController.showKeyboard(focusNode);
    await tester.pump();
    composerController.showPanel(ChatComposerPanel.emoji, focusNode);
    await tester.pump();

    for (final inset in <double>[240, 180, 120, 60, 0]) {
      keyboardInset.value = inset;
      await tester.pump();
      final expectedPanelHeight = 300 - inset;
      if (expectedPanelHeight == 0) {
        expect(find.byKey(const ValueKey('chat-input-surface')), findsNothing);
      } else {
        expect(
          tester
              .getSize(find.byKey(const ValueKey('chat-input-surface')))
              .height,
          expectedPanelHeight,
        );
      }
    }
  });

  testWidgets('键盘与表情交接期间输入栏位置保持稳定', (tester) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final composerController = ChatComposerController();
    final textController = TextEditingController();
    final focusNode = FocusNode();
    final keyboardInset = ValueNotifier(300.0);
    addTearDown(composerController.dispose);
    addTearDown(textController.dispose);
    addTearDown(focusNode.dispose);
    addTearDown(keyboardInset.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: ValueListenableBuilder<double>(
          valueListenable: keyboardInset,
          builder: (context, inset, _) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              padding: EdgeInsets.only(bottom: inset > 0 ? 0 : 34),
              viewPadding: const EdgeInsets.only(bottom: 34),
              viewInsets: EdgeInsets.only(bottom: inset),
            ),
            child: Scaffold(
              resizeToAvoidBottomInset: false,
              body: Align(
                alignment: Alignment.bottomCenter,
                child: ChatComposer(
                  controller: composerController,
                  textController: textController,
                  focusNode: focusNode,
                  onSend: () async {},
                  onUnavailableAction: (_) {},
                ),
              ),
            ),
          ),
        ),
      ),
    );

    composerController.showKeyboard(focusNode);
    await tester.pump();
    final keyboardToolbarTop = tester
        .getTopLeft(find.byKey(const ValueKey('chat-composer-toolbar')))
        .dy;

    composerController.showPanel(ChatComposerPanel.emoji, focusNode);
    await tester.pump();
    for (final inset in <double>[240, 180, 120, 60, 0]) {
      keyboardInset.value = inset;
      await tester.pump();
      expect(
        tester
            .getTopLeft(find.byKey(const ValueKey('chat-composer-toolbar')))
            .dy,
        closeTo(keyboardToolbarTop, 0.5),
      );
    }

    composerController.showKeyboard(focusNode);
    await tester.pump();
    for (final inset in <double>[
      60,
      120,
      180,
      240,
      280,
      291,
      296,
      299.4,
      300,
    ]) {
      keyboardInset.value = inset;
      await tester.pump();
      expect(
        tester
            .getTopLeft(find.byKey(const ValueKey('chat-composer-toolbar')))
            .dy,
        closeTo(keyboardToolbarTop, 0.5),
      );
    }
  });

  testWidgets('无底部导航聊天收起系统键盘时停在安全区且不回弹', (tester) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final composerController = ChatComposerController();
    final textController = TextEditingController();
    final focusNode = FocusNode();
    final keyboardInset = ValueNotifier(300.0);
    addTearDown(composerController.dispose);
    addTearDown(textController.dispose);
    addTearDown(focusNode.dispose);
    addTearDown(keyboardInset.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: ValueListenableBuilder<double>(
          valueListenable: keyboardInset,
          builder: (context, inset, _) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              viewPadding: const EdgeInsets.only(bottom: 34),
              viewInsets: EdgeInsets.only(bottom: inset),
            ),
            child: Scaffold(
              resizeToAvoidBottomInset: false,
              body: Align(
                alignment: Alignment.bottomCenter,
                child: ChatComposer(
                  controller: composerController,
                  textController: textController,
                  focusNode: focusNode,
                  onSend: () async {},
                  onUnavailableAction: (_) {},
                ),
              ),
            ),
          ),
        ),
      ),
    );

    composerController.showKeyboard(focusNode);
    await tester.pump();

    final toolbarTops = <double>[];
    for (final inset in <double>[300, 180, 60, 34, 20, 0]) {
      keyboardInset.value = inset;
      await tester.pump();
      toolbarTops.add(
        tester
            .getTopLeft(find.byKey(const ValueKey('chat-composer-toolbar')))
            .dy,
      );
      expect(
        tester
            .getSize(find.byKey(const ValueKey('chat-input-reserved-surface')))
            .height,
        inset > 34 ? inset : 34,
      );
    }

    for (var index = 1; index < toolbarTops.length; index += 1) {
      expect(toolbarTops[index], greaterThanOrEqualTo(toolbarTops[index - 1]));
    }
    expect(toolbarTops.last, closeTo(toolbarTops[toolbarTops.length - 2], 0.5));
  });

  testWidgets('带底部导航的广场聊天切换输入表面时位置保持稳定', (tester) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final composerController = ChatComposerController();
    final textController = TextEditingController();
    final focusNode = FocusNode();
    final keyboardInset = ValueNotifier(300.0);
    addTearDown(composerController.dispose);
    addTearDown(textController.dispose);
    addTearDown(focusNode.dispose);
    addTearDown(keyboardInset.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: ValueListenableBuilder<double>(
          valueListenable: keyboardInset,
          builder: (context, inset, _) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              viewPadding: const EdgeInsets.only(bottom: 34),
              viewInsets: EdgeInsets.only(bottom: inset),
            ),
            child: Scaffold(
              resizeToAvoidBottomInset: false,
              body: Align(
                alignment: Alignment.bottomCenter,
                child: ChatComposer(
                  controller: composerController,
                  textController: textController,
                  focusNode: focusNode,
                  onSend: () async {},
                  onUnavailableAction: (_) {},
                  bottomChromeHeight: 100,
                ),
              ),
              bottomNavigationBar: const SizedBox(height: 100),
            ),
          ),
        ),
      ),
    );

    composerController.showKeyboard(focusNode);
    await tester.pump();
    final keyboardToolbarTop = tester
        .getTopLeft(find.byKey(const ValueKey('chat-composer-toolbar')))
        .dy;

    composerController.showPanel(ChatComposerPanel.emoji, focusNode);
    await tester.pump();
    for (final inset in <double>[240, 180, 120, 60, 0]) {
      keyboardInset.value = inset;
      await tester.pump();
      expect(
        tester
            .getTopLeft(find.byKey(const ValueKey('chat-composer-toolbar')))
            .dy,
        closeTo(keyboardToolbarTop, 0.5),
      );
    }
  });

  testWidgets('原生键盘发送保持焦点且发送中不会重复提交', (tester) async {
    final composerController = ChatComposerController();
    final textController = TextEditingController();
    final focusNode = FocusNode();
    final sendCompleter = Completer<void>();
    var sendCount = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.bottomCenter,
            child: ChatComposer(
              controller: composerController,
              textController: textController,
              focusNode: focusNode,
              onSend: () {
                sendCount += 1;
                return sendCompleter.future;
              },
              onUnavailableAction: (_) {},
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.byType(TextField));
    await tester.enterText(find.byType(TextField), '测试发送');
    await tester.testTextInput.receiveAction(TextInputAction.send);
    await tester.pump();

    expect(sendCount, 1);
    expect(focusNode.hasFocus, isTrue);

    await tester.testTextInput.receiveAction(TextInputAction.send);
    await tester.pump();
    expect(sendCount, 1);

    sendCompleter.complete();
    await tester.pump();
    expect(focusNode.hasFocus, isTrue);

    await tester.pumpWidget(const SizedBox.shrink());
    composerController.dispose();
    textController.dispose();
    focusNode.dispose();
  });

  testWidgets('短聊天从顶部开始并保持时间顺序', (tester) async {
    final scrollController = ScrollController();
    final messages = [
      _message(sequence: 1, text: '第一条'),
      _message(sequence: 2, text: '第二条'),
    ];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ChatMessageTimeline(
            messages: messages,
            controller: scrollController,
            itemBuilder: (context, message, previous) => ChatMessageBubble(
              text: message.previewText,
              deliveryState: message.deliveryState,
              isMine: true,
              avatarInitial: '我',
            ),
          ),
        ),
      ),
    );

    final firstTop = tester.getTopLeft(find.text('第一条')).dy;
    final secondTop = tester.getTopLeft(find.text('第二条')).dy;
    expect(firstTop, lessThan(100));
    expect(secondTop, greaterThan(firstTop));

    await tester.pumpWidget(const SizedBox.shrink());
    scrollController.dispose();
  });

  testWidgets('已有长聊天首次打开时定位到最新消息', (tester) async {
    final messages = [
      for (var index = 1; index <= 30; index += 1)
        _message(sequence: index, text: '消息 $index'),
    ];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CommunityChatBody(
            channel: const CommunityChannelDescriptor(
              id: 'plaza-1',
              kind: CommunityChannelKind.plaza,
              title: '测试广场',
              subtitle: '主广场',
              emptyMessage: '暂无消息',
            ),
            showPreviewNotice: false,
            liveState: ConversationChatState(messages: messages),
            currentUserId: 'user-a',
          ),
        ),
      ),
    );
    final initialGate = tester.widget<Opacity>(
      find.byKey(const ValueKey('chat-timeline-initial-position-gate')),
    );
    expect(initialGate.opacity, 0);
    await tester.pumpAndSettle();

    final revealedGate = tester.widget<Opacity>(
      find.byKey(const ValueKey('chat-timeline-initial-position-gate')),
    );
    expect(revealedGate.opacity, 1);
    expect(find.text('消息 30'), findsOneWidget);
    expect(find.text('消息 1'), findsNothing);
  });

  testWidgets('新消息提示点击后定位首条未读并在当前页面消失', (tester) async {
    final messages = [
      for (var index = 1; index <= 30; index += 1)
        _message(sequence: index, text: '未读消息 $index'),
    ];
    int? locatedSequence;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CommunityChatBody(
            channel: const CommunityChannelDescriptor(
              id: 'plaza-unread',
              kind: CommunityChannelKind.plaza,
              title: '未读测试广场',
              subtitle: '主广场',
              emptyMessage: '暂无消息',
            ),
            showPreviewNotice: false,
            liveState: ConversationChatState(messages: messages),
            currentUserId: 'user-a',
            initialUnreadCount: 5,
            initialFirstUnreadSequence: 10,
            onLocateSequence: (sequence) async {
              locatedSequence = sequence;
              return true;
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('5条新消息'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('chat-unread-jump')));
    await tester.pumpAndSettle();

    expect(locatedSequence, 10);
    expect(find.text('5条新消息'), findsNothing);
    expect(find.text('未读消息 10'), findsOneWidget);
    expect(tester.getTopLeft(find.text('未读消息 10')).dy, lessThan(100));
  });

  testWidgets('可变高度长聊天首次打开时稳定停在最底部', (tester) async {
    final timelineController = ChatTimelineViewportController();
    addTearDown(timelineController.dispose);
    final messages = [
      for (var index = 1; index <= 40; index += 1)
        _message(
          sequence: index,
          text: index.isEven
              ? '这是一条用于验证可变高度布局的较长聊天消息 $index，它会在较窄屏幕上换行。'
              : '短消息 $index',
        ),
    ];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 320,
            height: 420,
            child: ChatMessageTimeline(
              messages: messages,
              controller: timelineController.scrollController,
              itemBuilder: (context, message, previous) => ChatMessageBubble(
                text: message.previewText,
                deliveryState: message.deliveryState,
                isMine: true,
                avatarInitial: '我',
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final position = timelineController.scrollController.position;
    expect(position.pixels, closeTo(position.maxScrollExtent, 0.5));
    expect(find.text('这是一条用于验证可变高度布局的较长聊天消息 40，它会在较窄屏幕上换行。'), findsOneWidget);
    expect(find.text('短消息 1'), findsNothing);
  });

  testWidgets('向上加载更早消息后保持原首条消息的屏幕位置', (tester) async {
    final timelineController = ChatTimelineViewportController();
    addTearDown(timelineController.dispose);
    final loadStarted = Completer<void>();
    final releaseLoad = Completer<void>();
    var messages = [
      for (var index = 51; index <= 100; index += 1)
        _message(sequence: index, text: '分页消息 $index'),
    ];
    late StateSetter update;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) {
              update = setState;
              return ChatMessageTimeline(
                messages: messages,
                controller: timelineController.scrollController,
                hasEarlier: true,
                onLoadEarlier: () async {
                  if (!loadStarted.isCompleted) loadStarted.complete();
                  await releaseLoad.future;
                  update(() {
                    messages = [
                      for (var index = 1; index <= 100; index += 1)
                        _message(sequence: index, text: '分页消息 $index'),
                    ];
                  });
                  return true;
                },
                itemBuilder: (context, message, previous) => ChatMessageBubble(
                  text: message.previewText,
                  deliveryState: message.deliveryState,
                  isMine: true,
                  avatarInitial: '我',
                ),
              );
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.drag(find.byType(ListView), const Offset(0, 10000));
    await tester.pump();
    await loadStarted.future;
    final before = tester.getTopLeft(find.text('分页消息 51')).dy;

    releaseLoad.complete();
    await tester.pumpAndSettle();

    expect(find.text('分页消息 1'), findsNothing);
    expect(tester.getTopLeft(find.text('分页消息 51')).dy, closeTo(before, 1));
  });

  testWidgets('复用时间线切换会话后重新定位到最底部', (tester) async {
    final timelineController = ChatTimelineViewportController();
    addTearDown(timelineController.dispose);
    final messages = [
      for (var index = 1; index <= 30; index += 1)
        _message(sequence: index, text: '切换消息 $index'),
    ];

    Widget app(Key conversationKey) => MaterialApp(
      home: Scaffold(
        body: ChatMessageTimeline(
          timelineKey: conversationKey,
          messages: messages,
          controller: timelineController.scrollController,
          itemBuilder: (context, message, previous) => ChatMessageBubble(
            text: message.previewText,
            deliveryState: message.deliveryState,
            isMine: true,
            avatarInitial: '我',
          ),
        ),
      ),
    );

    await tester.pumpWidget(app(const ValueKey('conversation-a')));
    await tester.pumpAndSettle();
    timelineController.scrollController.jumpTo(0);
    await tester.pump();
    expect(timelineController.scrollController.position.pixels, 0);

    await tester.pumpWidget(app(const ValueKey('conversation-b')));
    await tester.pumpAndSettle();

    final position = timelineController.scrollController.position;
    expect(position.pixels, closeTo(position.maxScrollExtent, 0.5));
    expect(find.text('切换消息 30'), findsOneWidget);
    expect(find.text('切换消息 1'), findsNothing);
  });

  testWidgets('处于最新位置时视口高度变化后仍保持最后一条完整可见', (tester) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final timelineController = ChatTimelineViewportController();
    final messages = [
      for (var index = 1; index <= 30; index += 1)
        _message(sequence: index, text: '键盘消息 $index'),
    ];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ChatMessageTimeline(
            messages: messages,
            controller: timelineController.scrollController,
            itemBuilder: (context, message, previous) => ChatMessageBubble(
              text: message.previewText,
              deliveryState: message.deliveryState,
              isMine: true,
              avatarInitial: '我',
            ),
          ),
        ),
      ),
    );
    timelineController.scrollToLatest(jump: true);
    await tester.pumpAndSettle();

    tester.view.physicalSize = const Size(400, 560);
    await tester.pumpAndSettle();

    final position = timelineController.scrollController.position;
    expect(position.pixels, position.maxScrollExtent);
    expect(find.text('键盘消息 30'), findsOneWidget);

    tester.view.physicalSize = const Size(400, 800);
    await tester.pumpAndSettle();

    final closedPosition = timelineController.scrollController.position;
    expect(closedPosition.pixels, closedPosition.maxScrollExtent);
    expect(tester.getBottomRight(find.text('键盘消息 30')).dy, lessThan(800));

    await tester.pumpWidget(const SizedBox.shrink());
    timelineController.dispose();
  });

  test('时间线在键盘尺寸变化的布局帧内保持贴近最新消息', () {
    const physics = ChatTimelineScrollPhysics();
    final oldPosition = FixedScrollMetrics(
      minScrollExtent: 0,
      maxScrollExtent: 900,
      pixels: 900,
      viewportDimension: 400,
      axisDirection: AxisDirection.down,
      devicePixelRatio: 1,
    );
    final keyboardOpened = FixedScrollMetrics(
      minScrollExtent: 0,
      maxScrollExtent: 1180,
      pixels: 900,
      viewportDimension: 120,
      axisDirection: AxisDirection.down,
      devicePixelRatio: 1,
    );
    final keyboardClosed = FixedScrollMetrics(
      minScrollExtent: 0,
      maxScrollExtent: 900,
      pixels: 1180,
      viewportDimension: 400,
      axisDirection: AxisDirection.down,
      devicePixelRatio: 1,
    );

    expect(
      physics.adjustPositionForNewDimensions(
        oldPosition: oldPosition,
        newPosition: keyboardOpened,
        isScrolling: false,
        velocity: 0,
      ),
      keyboardOpened.maxScrollExtent,
    );
    expect(
      physics.adjustPositionForNewDimensions(
        oldPosition: keyboardOpened.copyWith(pixels: 1180),
        newPosition: keyboardClosed,
        isScrolling: false,
        velocity: 0,
      ),
      keyboardClosed.maxScrollExtent,
    );
  });

  testWidgets('同一条乐观消息确认后不会把正在阅读的时间线拉到底部', (tester) async {
    final messages = [
      for (var index = 1; index <= 30; index += 1)
        _message(sequence: index, text: '历史消息 $index'),
      _message(
        sequence: 0,
        text: '乐观消息',
        messageId: 'local:client-1',
        clientMessageId: 'client-1',
        deliveryState: 'sending',
      ),
    ];

    Widget build(List<ConversationMessage> value) => MaterialApp(
      home: Scaffold(
        body: CommunityChatBody(
          channel: const CommunityChannelDescriptor(
            id: 'plaza-1',
            kind: CommunityChannelKind.plaza,
            title: '测试广场',
            subtitle: '主广场',
            emptyMessage: '暂无消息',
          ),
          showPreviewNotice: false,
          liveState: ConversationChatState(messages: value),
          currentUserId: 'user-a',
        ),
      ),
    );

    await tester.pumpWidget(build(messages));
    await tester.pumpAndSettle();
    final list = tester.widget<ListView>(find.byType(ListView));
    list.controller!.jumpTo(200);
    await tester.pump();
    final beforeAck = list.controller!.offset;

    final acknowledged = [
      ...messages.take(messages.length - 1),
      _message(
        sequence: 31,
        text: '乐观消息',
        messageId: 'server-31',
        clientMessageId: 'client-1',
        deliveryState: 'sent',
      ),
    ];
    await tester.pumpWidget(build(acknowledged));
    await tester.pumpAndSettle();

    expect(list.controller!.offset, beforeAck);
  });

  testWidgets('查找聊天记录后返回选中的消息序号', (tester) async {
    int? selectedSequence;

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                selectedSequence = await Navigator.of(context).push<int>(
                  MaterialPageRoute<int>(
                    builder: (_) => ChatHistorySearchScreen(
                      conversationTitle: '小桃子',
                      messages: [
                        _message(sequence: 1, text: '今天喝咖啡吗'),
                        _message(sequence: 2, text: '周六一起打羽毛球'),
                      ],
                    ),
                  ),
                );
              },
              child: const Text('打开查找'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('打开查找'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '羽毛球');
    await tester.pump();

    expect(find.text('周六一起打羽毛球'), findsOneWidget);
    expect(find.text('今天喝咖啡吗'), findsNothing);

    await tester.tap(find.text('周六一起打羽毛球'));
    await tester.pumpAndSettle();
    expect(selectedSequence, 2);
  });

  testWidgets('聊天设置卡片使用 Material 承载点击反馈', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          friendsControllerProvider.overrideWith(
            (ref) => FriendsController(_EmptyRelationshipRepository()),
          ),
        ],
        child: const MaterialApp(
          home: DirectChatSettingsScreen(
            conversationId: 'conversation-1',
            title: '小桃子',
            messages: [],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('查找聊天记录'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

class _EmptyRelationshipRepository implements RelationshipRepository {
  @override
  Future<PageResult<FriendRequest>> loadReceivedRequests() async {
    return const PageResult(items: <FriendRequest>[], hasMore: false);
  }

  @override
  Future<PageResult<FriendContact>> loadFriends() async {
    return const PageResult(items: <FriendContact>[], hasMore: false);
  }

  @override
  Future<PageResult<BlockedUser>> loadBlocks() async {
    return const PageResult(items: <BlockedUser>[], hasMore: false);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

ConversationMessage _message({
  String senderUserId = 'user-a',
  required String text,
  int sequence = 1,
  String? messageId,
  String? clientMessageId,
  String deliveryState = 'sent',
}) {
  return ConversationMessage(
    messageId: messageId ?? 'message-$sequence',
    clientMessageId: clientMessageId,
    conversationId: 'conversation-1',
    sequence: sequence,
    senderUserId: senderUserId,
    senderName: '小桃子',
    text: text,
    createdAt: DateTime.utc(2026, 8, 2),
    deliveryState: deliveryState,
  );
}

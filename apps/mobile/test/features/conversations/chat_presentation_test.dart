import 'dart:async';

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
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('本人消息显示右侧头像且不额外显示“我”', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
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
        home: Scaffold(
          body: Align(
            alignment: Alignment.bottomCenter,
            child: ChatComposer(
              controller: composerController,
              textController: textController,
              focusNode: focusNode,
              isSending: false,
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
    await tester.pump();
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
              isSending: false,
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
    await tester.pumpAndSettle();

    expect(find.text('消息 30'), findsOneWidget);
    expect(find.text('消息 1'), findsNothing);
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

    await tester.pumpWidget(const SizedBox.shrink());
    timelineController.dispose();
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
}) {
  return ConversationMessage(
    messageId: 'message-$sequence',
    conversationId: 'conversation-1',
    sequence: sequence,
    senderUserId: senderUserId,
    senderName: '小桃子',
    text: text,
    createdAt: DateTime.utc(2026, 8, 2),
    deliveryState: 'sent',
  );
}

import 'package:fangyuanli_mobile/src/features/conversations/domain/direct_message.dart';
import 'package:fangyuanli_mobile/src/features/conversations/presentation/chat_composer.dart';
import 'package:fangyuanli_mobile/src/features/conversations/presentation/chat_message_bubble.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('本人消息显示右侧头像且不额外显示“我”', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ChatMessageBubble(
            message: _message(senderUserId: 'user-a', text: '收到'),
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
}

DirectMessage _message({required String senderUserId, required String text}) {
  return DirectMessage(
    messageId: 'message-1',
    conversationId: 'conversation-1',
    sequence: 1,
    senderUserId: senderUserId,
    senderName: '小桃子',
    text: text,
    createdAt: DateTime.utc(2026, 8, 2),
    deliveryState: 'sent',
  );
}

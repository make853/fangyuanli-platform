import 'package:fangyuanli_mobile/src/features/activities/presentation/activity_composer_screen.dart';
import 'package:fangyuanli_mobile/src/features/posts/presentation/post_composer_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('动态编辑有媒体入口并在有内容离开时二次确认', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: PostComposerScreen()));

    expect(find.byKey(const ValueKey('post-add-media')), findsOneWidget);
    await tester.enterText(
      find.byKey(const ValueKey('post-body-field')),
      '附近新开了一家咖啡店',
    );
    await tester.tap(find.byTooltip('取消'));
    await tester.pumpAndSettle();
    expect(find.text('保留这次编辑？'), findsOneWidget);
  });

  testWidgets('活动加入审批开启时不提供附近所有人聊天选项', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: ActivityComposerScreen()));
    await tester.pumpAndSettle();

    await tester.drag(find.byType(ListView), const Offset(0, -500));
    await tester.pumpAndSettle();
    expect(find.text('需要管理员批准'), findsOneWidget);
    expect(find.text('附近所有人都可以聊天'), findsNothing);
    expect(find.text('活动长期进行'), findsOneWidget);
  });
}

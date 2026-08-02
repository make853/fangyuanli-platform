import 'package:fangyuanli_mobile/src/features/home/presentation/quick_create_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('顶部加号面板包含三类入口并返回所选动作', (tester) async {
    QuickCreateAction? selected;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                selected = await showQuickCreateSheet(context);
              },
              child: const Text('打开'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();
    expect(find.text('发布动态'), findsOneWidget);
    expect(find.text('创建活动'), findsOneWidget);
    expect(find.text('扫一扫'), findsOneWidget);

    await tester.tap(find.text('创建活动'));
    await tester.pumpAndSettle();
    expect(selected, QuickCreateAction.activity);
  });
}

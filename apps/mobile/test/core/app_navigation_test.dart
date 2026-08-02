import 'package:fangyuanli_mobile/src/core/navigation/app_navigation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('嵌套页面记录来源并按原导航栈逐层返回', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: _OriginPage()));

    await tester.tap(find.text('打开账号与安全'));
    await tester.pumpAndSettle();
    expect(find.text('账号来源：tab'), findsOneWidget);

    await tester.tap(find.text('打开隐私'));
    await tester.pumpAndSettle();
    expect(find.text('隐私来源：accountSecurity'), findsOneWidget);

    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('账号来源：tab'), findsOneWidget);

    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('我的首页'), findsOneWidget);
  });
}

class _OriginPage extends StatelessWidget {
  const _OriginPage();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          const Text('我的首页'),
          TextButton(
            onPressed: () => AppNavigation.push<void>(
              context,
              destination: AppRouteId.accountSecurity,
              source: const AppNavigationSource(
                section: AppSection.profile,
                entryPoint: AppEntryPoint.tab,
              ),
              builder: (_) => const _AccountSecurityPage(),
            ),
            child: const Text('打开账号与安全'),
          ),
        ],
      ),
    );
  }
}

class _AccountSecurityPage extends StatelessWidget {
  const _AccountSecurityPage();

  @override
  Widget build(BuildContext context) {
    final metadata = AppNavigation.metadataOf(context)!;
    return Scaffold(
      appBar: AppBar(),
      body: Column(
        children: [
          Text('账号来源：${metadata.source.entryPoint.name}'),
          TextButton(
            onPressed: () => AppNavigation.push<void>(
              context,
              destination: AppRouteId.privacy,
              source: const AppNavigationSource(
                section: AppSection.profile,
                entryPoint: AppEntryPoint.settings,
                routeId: AppRouteId.accountSecurity,
              ),
              builder: (_) => const _PrivacyPage(),
            ),
            child: const Text('打开隐私'),
          ),
        ],
      ),
    );
  }
}

class _PrivacyPage extends StatelessWidget {
  const _PrivacyPage();

  @override
  Widget build(BuildContext context) {
    final metadata = AppNavigation.metadataOf(context)!;
    return Scaffold(
      appBar: AppBar(),
      body: Text('隐私来源：${metadata.source.routeId?.name}'),
    );
  }
}

import 'package:fangyuanli_mobile/src/app.dart';
import 'package:fangyuanli_mobile/src/core/config/app_environment.dart';
import 'package:fangyuanli_mobile/src/core/config/app_environment_provider.dart';
import 'package:fangyuanli_mobile/src/core/storage/session_store.dart';
import 'package:fangyuanli_mobile/src/features/auth/application/auth_controller.dart';
import 'package:fangyuanli_mobile/src/features/auth/domain/auth_session.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _EmptySessionStore implements SessionStore {
  @override
  Future<void> clear() async {}

  @override
  Future<AuthSession?> read() async => null;

  @override
  Future<void> write(AuthSession session) async {}
}

void main() {
  testWidgets('未登录时展示手机号登录页', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appEnvironmentProvider.overrideWithValue(
            const AppEnvironment(
              flavor: AppFlavor.local,
              apiBaseUrl: 'http://127.0.0.1:3000',
              realtimeUrl: 'ws://127.0.0.1:3000/ws/v1',
            ),
          ),
          sessionStoreProvider.overrideWithValue(_EmptySessionStore()),
        ],
        child: const FangyuanliApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('手机号登录'), findsOneWidget);
    expect(find.text('登录 / 注册'), findsOneWidget);
    expect(find.text('邮箱登录'), findsNothing);
  });
}

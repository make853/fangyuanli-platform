import 'package:fangyuanli_mobile/src/core/config/app_environment.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('默认环境指向本地 API 和实时服务', () {
    final environment = AppEnvironment.fromDefines();

    expect(environment.flavor, AppFlavor.local);
    expect(environment.apiBaseUrl, 'http://127.0.0.1:3000');
    expect(environment.realtimeUrl, 'ws://127.0.0.1:3000/ws/v1');
    expect(environment.visibleBuildLabel, 'local · local-dev');
  });

  test('staging quick login requires a complete isolated test account set', () {
    const complete = AppEnvironment(
      flavor: AppFlavor.staging,
      apiBaseUrl: 'https://staging.example.com',
      realtimeUrl: 'wss://staging.example.com/ws/v1',
      stagingTestPhoneA: '13800000001',
      stagingTestPhoneB: '13800000002',
      stagingTestCode: '123456',
      buildIdentity: '79e67be-dirty.abc12345',
      testClientRole: 'A',
    );
    const production = AppEnvironment(
      flavor: AppFlavor.production,
      apiBaseUrl: 'https://example.com',
      realtimeUrl: 'wss://example.com/ws/v1',
      stagingTestPhoneA: '13800000001',
      stagingTestPhoneB: '13800000002',
      stagingTestCode: '123456',
    );

    expect(complete.hasStagingTestAccounts, isTrue);
    expect(complete.visibleBuildLabel, 'staging · A · 79e67be-dirty.abc12345');
    expect(production.hasStagingTestAccounts, isFalse);
  });
}

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory temporaryDirectory;
  late File fakeFlutter;
  late File capturedArguments;

  setUp(() async {
    temporaryDirectory = await Directory.systemTemp.createTemp(
      'fangyuanli-staging-tooling-',
    );
    capturedArguments = File('${temporaryDirectory.path}/arguments.txt');
    fakeFlutter = File('${temporaryDirectory.path}/flutter');
    await fakeFlutter.writeAsString('''#!/bin/zsh
if [[ "\$1" == "devices" ]]; then
  print -r -- '[{"name":"真实 iPhone","id":"physical-a","emulator":false},{"name":"iPhone 16e","id":"simulator-b","emulator":true}]'
  exit 0
fi
print -r -- "\$@" > '${capturedArguments.path}'
''');
    await Process.run('chmod', ['+x', fakeFlutter.path]);
  });

  tearDown(() async {
    if (await temporaryDirectory.exists()) {
      await temporaryDirectory.delete(recursive: true);
    }
  });

  test('staging launcher pins an exact physical A build identity', () async {
    final result = await _runLauncher(
      fakeFlutter: fakeFlutter,
      deviceId: 'physical-a',
      role: 'A',
    );

    expect(result.exitCode, 0, reason: result.stderr.toString());
    expect(result.stdout, contains('A = 真实 iPhone [physical-a]'));
    expect(result.stdout, contains('staging · A · source-1234'));
    final arguments = await capturedArguments.readAsString();
    expect(arguments, contains('-d physical-a'));
    expect(arguments, contains('--dart-define=BUILD_IDENTITY=source-1234'));
    expect(arguments, contains('--dart-define=TEST_CLIENT_ROLE=A'));
  });

  test('staging launcher refuses to use the physical device as B', () async {
    final result = await _runLauncher(
      fakeFlutter: fakeFlutter,
      deviceId: 'physical-a',
      role: 'B',
    );

    expect(result.exitCode, isNot(0));
    expect(result.stderr, contains('测试端 B 必须是模拟器'));
    expect(await capturedArguments.exists(), isFalse);
  });
}

Future<ProcessResult> _runLauncher({
  required File fakeFlutter,
  required String deviceId,
  required String role,
}) {
  return Process.run(
    'zsh',
    ['scripts/run-ios-staging-app.sh'],
    environment: {
      ...Platform.environment,
      'FLUTTER_BIN': fakeFlutter.path,
      'IOS_STAGING_DEVICE_ID': deviceId,
      'TEST_CLIENT_ROLE': role,
      'IOS_STAGING_MODE': 'debug',
      'BUILD_IDENTITY': 'source-1234',
      'API_BASE_URL': 'http://127.0.0.1:3000',
      'REALTIME_URL': 'ws://127.0.0.1:3000/ws/v1',
      'STAGING_TEST_PHONE_A': '13800000001',
      'STAGING_TEST_PHONE_B': '13800000002',
      'STAGING_TEST_CODE': '123456',
    },
    stdoutEncoding: utf8,
    stderrEncoding: utf8,
  );
}

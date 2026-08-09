import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final macOsOnly = Platform.isMacOS
      ? false
      : 'requires macOS zsh and iOS device tooling';
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
  }, skip: macOsOnly);

  test('staging launcher refuses to use the physical device as B', () async {
    final result = await _runLauncher(
      fakeFlutter: fakeFlutter,
      deviceId: 'physical-a',
      role: 'B',
    );

    expect(result.exitCode, isNot(0));
    expect(result.stderr, contains('测试端 B 必须是模拟器'));
    expect(await capturedArguments.exists(), isFalse);
  }, skip: macOsOnly);

  test('physical A installs only a newly built fallback artifact', () async {
    final buildRoot = Directory('${temporaryDirectory.path}/ios-build');
    final fallbackApp = Directory(
      '${buildRoot.path}/Profile-iphoneos/Runner.app',
    );
    final deviceCtlArguments = File(
      '${temporaryDirectory.path}/devicectl-arguments.txt',
    );
    final fakeDeviceCtl = File('${temporaryDirectory.path}/xcrun');
    await fakeDeviceCtl.writeAsString('''#!/bin/zsh
print -r -- "\$@" >> '${deviceCtlArguments.path}'
''');
    await Process.run('chmod', ['+x', fakeDeviceCtl.path]);
    await fakeFlutter.writeAsString('''#!/bin/zsh
if [[ "\$1" == "devices" ]]; then
  print -r -- '[{"name":"真实 iPhone","id":"physical-a","emulator":false}]'
  exit 0
fi
mkdir -p '${fallbackApp.path}'
touch '${fallbackApp.path}'
exit 1
''');

    final result = await _runLauncher(
      fakeFlutter: fakeFlutter,
      deviceId: 'physical-a',
      role: 'A',
      mode: 'profile',
      extraEnvironment: {
        'IOS_STAGING_BUILD_ROOT': buildRoot.path,
        'IOS_STAGING_APP_BUNDLE_ID': 'com.example.fallback',
        'DEVICECTL_BIN': fakeDeviceCtl.path,
      },
    );

    expect(result.exitCode, 0, reason: result.stderr.toString());
    expect(result.stdout, contains('备用通道安装并启动'));
    final arguments = await deviceCtlArguments.readAsLines();
    expect(arguments, hasLength(2));
    expect(arguments.first, contains('device install app'));
    expect(arguments.first, contains(fallbackApp.path));
    expect(arguments.last, contains('device process launch'));
    expect(arguments.last, contains('com.example.fallback'));
  }, skip: macOsOnly);

  test('fallback refuses a stale physical artifact', () async {
    final buildRoot = Directory('${temporaryDirectory.path}/ios-build');
    final fallbackApp = Directory(
      '${buildRoot.path}/Profile-iphoneos/Runner.app',
    );
    await fallbackApp.create(recursive: true);
    await fakeFlutter.writeAsString('''#!/bin/zsh
if [[ "\$1" == "devices" ]]; then
  print -r -- '[{"name":"真实 iPhone","id":"physical-a","emulator":false}]'
  exit 0
fi
exit 1
''');

    final result = await _runLauncher(
      fakeFlutter: fakeFlutter,
      deviceId: 'physical-a',
      role: 'A',
      mode: 'profile',
      extraEnvironment: {'IOS_STAGING_BUILD_ROOT': buildRoot.path},
    );

    expect(result.exitCode, isNot(0));
    expect(result.stderr, contains('拒绝安装旧产物'));
  }, skip: macOsOnly);

  test('field launcher discovers one physical iPhone and pins HTTPS', () async {
    final privateWrapper = File(
      '${temporaryDirectory.path}/run-ios-media-acceptance.sh',
    );
    await privateWrapper.writeAsString('''
flutter_bin="${fakeFlutter.path}"
ssh_key="${temporaryDirectory.path}/private-key.pem"
remote_host="staging@example.invalid"
''');
    final fakeSsh = File('${temporaryDirectory.path}/ssh');
    await fakeSsh.writeAsString(r'''#!/bin/zsh
case "$*" in
  *STAGING_PUBLIC_HOST*) print -r -- 'staging.example.com' ;;
  *STAGING_TEST_PHONE_A*) print -r -- '13800000001' ;;
  *STAGING_TEST_PHONE_B*) print -r -- '13800000002' ;;
  *STAGING_SMS_TEST_CODE*) print -r -- '123456' ;;
  *) exit 1 ;;
esac
''');
    await Process.run('chmod', ['+x', fakeSsh.path]);
    await fakeFlutter.writeAsString('''#!/bin/zsh
if [[ "\$1" == "devices" ]]; then
  print -r -- '[{"name":"真实 iPhone","id":"physical-field","emulator":false,"targetPlatform":"ios"}]'
  exit 0
fi
print -r -- "\$@" > '${capturedArguments.path}'
''');

    final result = await Process.run(
      'zsh',
      ['scripts/run-ios-field-staging-app.sh'],
      environment: {
        ...Platform.environment,
        'STAGING_ACCEPTANCE_WRAPPER': privateWrapper.path,
        'SSH_BIN': fakeSsh.path,
        'BUILD_IDENTITY': 'field-source-1234',
      },
      stdoutEncoding: utf8,
      stderrEncoding: utf8,
    );

    expect(result.exitCode, 0, reason: result.stderr.toString());
    expect(result.stdout, contains('A = 真实 iPhone [physical-field]'));
    final arguments = await capturedArguments.readAsString();
    expect(arguments, contains('-d physical-field'));
    expect(
      arguments,
      contains('--dart-define=API_BASE_URL=https://staging.example.com'),
    );
    expect(
      arguments,
      contains(
        '--dart-define=REALTIME_URL=wss://staging.example.com/ws/v1',
      ),
    );
  }, skip: macOsOnly);
}

Future<ProcessResult> _runLauncher({
  required File fakeFlutter,
  required String deviceId,
  required String role,
  String mode = 'debug',
  Map<String, String> extraEnvironment = const {},
}) {
  return Process.run(
    'zsh',
    ['scripts/run-ios-staging-app.sh'],
    environment: {
      ...Platform.environment,
      'FLUTTER_BIN': fakeFlutter.path,
      'IOS_STAGING_DEVICE_ID': deviceId,
      'TEST_CLIENT_ROLE': role,
      'IOS_STAGING_MODE': mode,
      'BUILD_IDENTITY': 'source-1234',
      'API_BASE_URL': 'http://127.0.0.1:3000',
      'REALTIME_URL': 'ws://127.0.0.1:3000/ws/v1',
      'STAGING_TEST_PHONE_A': '13800000001',
      'STAGING_TEST_PHONE_B': '13800000002',
      'STAGING_TEST_CODE': '123456',
      ...extraEnvironment,
    },
    stdoutEncoding: utf8,
    stderrEncoding: utf8,
  );
}

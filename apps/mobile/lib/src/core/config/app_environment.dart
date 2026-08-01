enum AppFlavor { local, staging, production }

class AppEnvironment {
  const AppEnvironment({
    required this.flavor,
    required this.apiBaseUrl,
    required this.realtimeUrl,
    this.stagingTestPhoneA = '',
    this.stagingTestPhoneB = '',
    this.stagingTestCode = '',
  });

  factory AppEnvironment.fromDefines() {
    const flavorValue = String.fromEnvironment(
      'APP_FLAVOR',
      defaultValue: 'local',
    );
    const apiBaseUrl = String.fromEnvironment(
      'API_BASE_URL',
      defaultValue: 'http://127.0.0.1:3000',
    );
    const realtimeUrl = String.fromEnvironment(
      'REALTIME_URL',
      defaultValue: 'ws://127.0.0.1:3000/ws/v1',
    );
    const stagingTestPhoneA = String.fromEnvironment('STAGING_TEST_PHONE_A');
    const stagingTestPhoneB = String.fromEnvironment('STAGING_TEST_PHONE_B');
    const stagingTestCode = String.fromEnvironment('STAGING_TEST_CODE');

    return AppEnvironment(
      flavor: AppFlavor.values.firstWhere(
        (value) => value.name == flavorValue,
        orElse: () => AppFlavor.local,
      ),
      apiBaseUrl: _normalizedHttpUrl(apiBaseUrl),
      realtimeUrl: _normalizedRealtimeUrl(realtimeUrl),
      stagingTestPhoneA: stagingTestPhoneA,
      stagingTestPhoneB: stagingTestPhoneB,
      stagingTestCode: stagingTestCode,
    );
  }

  final AppFlavor flavor;
  final String apiBaseUrl;
  final String realtimeUrl;
  final String stagingTestPhoneA;
  final String stagingTestPhoneB;
  final String stagingTestCode;

  bool get hasStagingTestAccounts =>
      flavor == AppFlavor.staging &&
      RegExp(r'^1[3-9]\d{9}$').hasMatch(stagingTestPhoneA) &&
      RegExp(r'^1[3-9]\d{9}$').hasMatch(stagingTestPhoneB) &&
      RegExp(r'^\d{6}$').hasMatch(stagingTestCode);

  static String _normalizedHttpUrl(String value) {
    final uri = Uri.tryParse(value);
    if (uri == null || !uri.hasScheme || !uri.hasAuthority) {
      throw const FormatException('API_BASE_URL 必须是完整的 http(s) 地址');
    }
    if (uri.scheme != 'http' && uri.scheme != 'https') {
      throw const FormatException('API_BASE_URL 只支持 http 或 https');
    }
    return value.endsWith('/') ? value.substring(0, value.length - 1) : value;
  }

  static String _normalizedRealtimeUrl(String value) {
    final uri = Uri.tryParse(value);
    if (uri == null ||
        !uri.hasScheme ||
        !uri.hasAuthority ||
        (uri.scheme != 'ws' && uri.scheme != 'wss')) {
      throw const FormatException('REALTIME_URL 必须是完整的 ws(s) 地址');
    }
    return value;
  }
}

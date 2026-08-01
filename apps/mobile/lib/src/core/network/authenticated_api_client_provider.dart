import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/app_environment_provider.dart';
import 'authenticated_api_client.dart';

/// Composition token implemented by the auth feature at the application root.
///
/// Core networking and feature repositories depend on this stable function
/// instead of importing the auth controller directly.
final authenticatedSessionLoaderProvider = Provider<SessionLoader>(
  (_) => _signedOutSessionLoader,
);

Future<Never?> _signedOutSessionLoader({bool forceRefresh = false}) async =>
    null;

final authenticatedApiClientProvider = Provider<AuthenticatedApiClient>((ref) {
  final client = AuthenticatedApiClient(
    environment: ref.watch(appEnvironmentProvider),
    loadSession: ref.watch(authenticatedSessionLoaderProvider),
  );
  ref.onDispose(client.close);
  return client;
});

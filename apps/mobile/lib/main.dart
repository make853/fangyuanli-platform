import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'src/app.dart';
import 'src/core/network/authenticated_api_client_provider.dart';
import 'src/features/auth/application/auth_controller.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    ProviderScope(
      overrides: [
        authenticatedSessionLoaderProvider.overrideWith(
          (ref) => ref.read(authControllerProvider.notifier).validSession,
        ),
      ],
      child: const FangyuanliApp(),
    ),
  );
}

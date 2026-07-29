import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/theme/app_theme.dart';
import 'features/auth/application/auth_controller.dart';
import 'features/auth/presentation/login_screen.dart';
import 'features/home/presentation/home_shell.dart';

class FangyuanliApp extends ConsumerWidget {
  const FangyuanliApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authControllerProvider);

    return MaterialApp(
      title: '方圆里',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      home: switch (authState.status) {
        AuthStatus.bootstrapping => const _LaunchScreen(),
        AuthStatus.signedOut => const LoginScreen(),
        AuthStatus.signedIn => const HomeShell(),
      },
    );
  }
}

class _LaunchScreen extends StatelessWidget {
  const _LaunchScreen();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _BrandMark(),
            SizedBox(height: 18),
            Text(
              '方圆里',
              style: TextStyle(fontSize: 26, fontWeight: FontWeight.w700),
            ),
            SizedBox(height: 28),
            SizedBox.square(
              dimension: 22,
              child: CircularProgressIndicator(strokeWidth: 2.4),
            ),
          ],
        ),
      ),
    );
  }
}

class _BrandMark extends StatelessWidget {
  const _BrandMark();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primary,
        borderRadius: BorderRadius.circular(22),
      ),
      child: const SizedBox.square(
        dimension: 68,
        child: Icon(Icons.forum_rounded, color: Colors.white, size: 34),
      ),
    );
  }
}

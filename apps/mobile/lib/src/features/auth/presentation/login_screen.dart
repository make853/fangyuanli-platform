import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../application/auth_controller.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _phoneController = TextEditingController();
  final _codeController = TextEditingController();
  final _phoneFocus = FocusNode();
  final _codeFocus = FocusNode();
  Timer? _timer;
  int _countdown = 0;
  bool _agreed = false;

  @override
  void dispose() {
    _timer?.cancel();
    _phoneController.dispose();
    _codeController.dispose();
    _phoneFocus.dispose();
    _codeFocus.dispose();
    super.dispose();
  }

  void _startCountdown(int seconds) {
    _timer?.cancel();
    setState(() => _countdown = seconds);
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted || _countdown <= 1) {
        timer.cancel();
        if (mounted) setState(() => _countdown = 0);
        return;
      }
      setState(() => _countdown -= 1);
    });
  }

  Future<void> _sendCode() async {
    final phone = _phoneController.text.trim();
    if (!RegExp(r'^1[3-9]\d{9}$').hasMatch(phone)) {
      _showMessage('请输入有效的中国大陆手机号');
      return;
    }
    if (!_agreed) {
      _showMessage('请先同意用户协议和隐私政策');
      return;
    }
    final controller = ref.read(authControllerProvider.notifier);
    if (await controller.sendCode(phone)) {
      final challenge = ref.read(authControllerProvider).challenge;
      _startCountdown(challenge?.resendAfterSeconds ?? 60);
      _codeFocus.requestFocus();
    }
  }

  Future<void> _login() async {
    if (!_agreed) {
      _showMessage('请先同意用户协议和隐私政策');
      return;
    }
    if (_codeController.text.length != 6) {
      _showMessage('请输入6位验证码');
      return;
    }
    await ref
        .read(authControllerProvider.notifier)
        .verifyCode(_codeController.text);
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(authControllerProvider, (previous, next) {
      if (next.message != null && next.message != previous?.message) {
        _showMessage(next.message!);
      }
    });
    final state = ref.watch(authControllerProvider);

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(28, 36, 28, 28),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: AutofillGroup(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Align(
                      alignment: Alignment.centerLeft,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.primary,
                          borderRadius: BorderRadius.circular(18),
                        ),
                        child: const SizedBox.square(
                          dimension: 58,
                          child: Icon(
                            Icons.forum_rounded,
                            color: Colors.white,
                            size: 30,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 30),
                    Text(
                      '手机号登录',
                      style: Theme.of(context).textTheme.headlineMedium,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '一个手机号对应一个方圆里账号',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 30),
                    TextField(
                      controller: _phoneController,
                      focusNode: _phoneFocus,
                      keyboardType: TextInputType.phone,
                      autofillHints: const [AutofillHints.telephoneNumber],
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                        LengthLimitingTextInputFormatter(11),
                      ],
                      decoration: const InputDecoration(
                        prefixText: '+86  ',
                        labelText: '手机号',
                        hintText: '请输入手机号',
                      ),
                    ),
                    const SizedBox(height: 14),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _codeController,
                            focusNode: _codeFocus,
                            keyboardType: TextInputType.number,
                            autofillHints: const [AutofillHints.oneTimeCode],
                            inputFormatters: [
                              FilteringTextInputFormatter.digitsOnly,
                              LengthLimitingTextInputFormatter(6),
                            ],
                            decoration: const InputDecoration(
                              labelText: '验证码',
                              hintText: '6位验证码',
                            ),
                            onSubmitted: (_) => _login(),
                          ),
                        ),
                        const SizedBox(width: 10),
                        SizedBox(
                          width: 112,
                          height: 56,
                          child: OutlinedButton(
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                              ),
                              textStyle: const TextStyle(fontSize: 14),
                            ),
                            onPressed: state.isBusy || _countdown > 0
                                ? null
                                : _sendCode,
                            child: Text(
                              _countdown > 0 ? '${_countdown}s' : '获取验证码',
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 22),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Checkbox(
                          value: _agreed,
                          visualDensity: VisualDensity.compact,
                          onChanged: (value) {
                            setState(() => _agreed = value ?? false);
                          },
                        ),
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.only(top: 10),
                            child: Text.rich(
                              TextSpan(
                                style: Theme.of(context).textTheme.bodySmall,
                                children: const [
                                  TextSpan(text: '我已阅读并同意'),
                                  TextSpan(
                                    text: '《用户协议》',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  TextSpan(text: '和'),
                                  TextSpan(
                                    text: '《隐私政策》',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    FilledButton(
                      onPressed: state.isBusy ? null : _login,
                      child: state.isBusy
                          ? const SizedBox.square(
                              dimension: 20,
                              child: CircularProgressIndicator(
                                color: Colors.white,
                                strokeWidth: 2,
                              ),
                            )
                          : const Text('登录 / 注册'),
                    ),
                    const SizedBox(height: 18),
                    const Text(
                      '首次验证手机号将自动创建账号。暂不支持仅使用邮箱注册。',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 12, color: Color(0xFF78847E)),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/app_environment.dart';
import '../../../core/storage/session_store.dart';
import '../data/auth_api.dart';
import '../data/auth_repository.dart';
import '../domain/auth_session.dart';

enum AuthStatus { bootstrapping, signedOut, signedIn }

class AuthState {
  const AuthState({
    required this.status,
    this.session,
    this.challenge,
    this.isBusy = false,
    this.message,
  });

  const AuthState.bootstrapping() : this(status: AuthStatus.bootstrapping);

  final AuthStatus status;
  final AuthSession? session;
  final SmsChallenge? challenge;
  final bool isBusy;
  final String? message;

  AuthState copyWith({
    AuthStatus? status,
    AuthSession? session,
    SmsChallenge? challenge,
    bool? isBusy,
    String? message,
    bool clearMessage = false,
  }) {
    return AuthState(
      status: status ?? this.status,
      session: session ?? this.session,
      challenge: challenge ?? this.challenge,
      isBusy: isBusy ?? this.isBusy,
      message: clearMessage ? null : message ?? this.message,
    );
  }
}

class AuthController extends StateNotifier<AuthState> {
  AuthController(this._repository) : super(const AuthState.bootstrapping()) {
    restore();
  }

  final AuthRepository _repository;

  Future<void> restore() async {
    try {
      final session = await _repository.restore();
      state = AuthState(
        status: session == null ? AuthStatus.signedOut : AuthStatus.signedIn,
        session: session,
      );
    } catch (_) {
      state = const AuthState(status: AuthStatus.signedOut);
    }
  }

  Future<bool> sendCode(String phoneNumber) async {
    state = state.copyWith(isBusy: true, clearMessage: true);
    try {
      final challenge = await _repository.sendLoginCode(phoneNumber);
      state = state.copyWith(
        challenge: challenge,
        isBusy: false,
        message: '验证码已发送',
      );
      return true;
    } catch (error) {
      state = state.copyWith(isBusy: false, message: error.toString());
      return false;
    }
  }

  Future<bool> verifyCode(String code) async {
    final challenge = state.challenge;
    if (challenge == null) {
      state = state.copyWith(message: '请先获取验证码');
      return false;
    }
    state = state.copyWith(isBusy: true, clearMessage: true);
    try {
      final session = await _repository.verifyLoginCode(
        challenge: challenge,
        code: code,
      );
      state = AuthState(status: AuthStatus.signedIn, session: session);
      return true;
    } catch (error) {
      state = state.copyWith(isBusy: false, message: error.toString());
      return false;
    }
  }

  Future<void> logout() async {
    final session = state.session;
    if (session == null) return;
    state = state.copyWith(isBusy: true, clearMessage: true);
    String? message;
    try {
      await _repository.logout(session);
    } catch (_) {
      message = '已退出本机登录；服务器会话稍后自动失效';
    }
    state = AuthState(status: AuthStatus.signedOut, message: message);
  }
}

final appEnvironmentProvider = Provider<AppEnvironment>(
  (_) => AppEnvironment.fromDefines(),
);

final authApiProvider = Provider<AuthApi>(
  (ref) => AuthApi(environment: ref.watch(appEnvironmentProvider)),
);

final sessionStoreProvider = Provider<SessionStore>(
  (_) => SecureSessionStore(),
);

final authRepositoryProvider = Provider<AuthRepository>(
  (ref) => AuthRepository(
    api: ref.watch(authApiProvider),
    sessionStore: ref.watch(sessionStoreProvider),
  ),
);

final authControllerProvider = StateNotifierProvider<AuthController, AuthState>(
  (ref) => AuthController(ref.watch(authRepositoryProvider)),
);

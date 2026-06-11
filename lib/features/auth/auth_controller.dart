import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/api_service.dart';

class AuthState {
  final bool isLoggedIn;
  final bool isLoading;
  final String? error;
  final int? userId;
  final String? email;
  final String? nickname;

  const AuthState({
    this.isLoggedIn = false,
    this.isLoading = false,
    this.error,
    this.userId,
    this.email,
    this.nickname,
  });

  AuthState copyWith({
    bool? isLoggedIn,
    bool? isLoading,
    String? error,
    int? userId,
    String? email,
    String? nickname,
  }) => AuthState(
    isLoggedIn: isLoggedIn ?? this.isLoggedIn,
    isLoading: isLoading ?? this.isLoading,
    error: error,
    userId: userId ?? this.userId,
    email: email ?? this.email,
    nickname: nickname ?? this.nickname,
  );
}

final authProvider = StateNotifierProvider<AuthController, AuthState>(
  (ref) => AuthController(),
);

class AuthController extends StateNotifier<AuthState> {
  AuthController() : super(const AuthState()) {
    _checkLogin();
  }

  Future<void> _checkLogin() async {
    final user = await ApiService.getUser();
    final token = await ApiService.getToken();
    if (user != null && token != null) {
      state = state.copyWith(
        isLoggedIn: true,
        userId: user['id'],
        email: user['email'],
        nickname: user['nickname'],
      );
    }
  }

  Future<bool> login(String email, String password) async {
    state = state.copyWith(isLoading: true);
    final res = await ApiService.login(email, password);
    if (res['status'] == 'ok') {
      final data = res['data'];
      await ApiService.saveToken(data['token']);
      await ApiService.saveUser(data['id'], data['email'], data['nickname']);
      state = state.copyWith(
        isLoggedIn: true,
        isLoading: false,
        userId: data['id'],
        email: data['email'],
        nickname: data['nickname'],
      );
      return true;
    } else {
      state = state.copyWith(isLoading: false, error: res['message']);
      return false;
    }
  }

  Future<bool> register(String email, String password, String nickname) async {
    state = state.copyWith(isLoading: true);
    final res = await ApiService.register(email, password, nickname);
    if (res['status'] == 'ok') {
      final data = res['data'];
      await ApiService.saveToken(data['token']);
      await ApiService.saveUser(data['id'], data['email'], nickname);
      state = state.copyWith(
        isLoggedIn: true,
        isLoading: false,
        userId: data['id'],
        email: data['email'],
        nickname: nickname,
      );
      return true;
    } else {
      state = state.copyWith(isLoading: false, error: res['message']);
      return false;
    }
  }

  Future<void> logout() async {
    await ApiService.clearAuth();
    state = const AuthState();
  }
}

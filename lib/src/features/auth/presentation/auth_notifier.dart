import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/auth_repository.dart';
import '../../../core/network/token_storage.dart';

// Auth state
enum AuthStatus { unknown, authenticated, unauthenticated }

class AuthState {
  final AuthStatus status;
  final String? userId;
  final String? error;
  final bool isLoading;

  const AuthState({
    this.status = AuthStatus.unknown,
    this.userId,
    this.error,
    this.isLoading = false,
  });

  AuthState copyWith({
    AuthStatus? status,
    String? userId,
    String? error,
    bool? isLoading,
  }) {
    return AuthState(
      status: status ?? this.status,
      userId: userId ?? this.userId,
      error: error,
      isLoading: isLoading ?? this.isLoading,
    );
  }
}

class AuthNotifier extends AsyncNotifier<AuthState> {
  @override
  Future<AuthState> build() async {
    final token = await TokenStorage.getToken();
    final userId = await TokenStorage.getUserId();
    if (token != null && userId != null) {
      return AuthState(status: AuthStatus.authenticated, userId: userId);
    }
    return const AuthState(status: AuthStatus.unauthenticated);
  }

  Future<void> signUp({
    required String email,
    required String password,
    required String fullName,
    required String termsSignature,
  }) async {
    state = const AsyncLoading();
    try {
      final repo = ref.read(authRepositoryProvider);
      final data = await repo.signUp(
        email: email,
        password: password,
        fullName: fullName,
        termsSignature: termsSignature,
      );
      state = AsyncData(
        AuthState(status: AuthStatus.authenticated, userId: data['user_id']),
      );
    } catch (e) {
      state = AsyncData(
        AuthState(status: AuthStatus.unauthenticated, error: _parseError(e)),
      );
    }
  }

  Future<void> login({required String email, required String password}) async {
    state = const AsyncLoading();
    try {
      final repo = ref.read(authRepositoryProvider);
      final data = await repo.login(email: email, password: password);
      state = AsyncData(
        AuthState(status: AuthStatus.authenticated, userId: data['user_id']),
      );
    } catch (e) {
      state = AsyncData(
        AuthState(status: AuthStatus.unauthenticated, error: _parseError(e)),
      );
    }
  }

  Future<void> logout() async {
    final repo = ref.read(authRepositoryProvider);
    await repo.logout();
    state = const AsyncData(AuthState(status: AuthStatus.unauthenticated));
  }

  String _parseError(Object e) {
    if (e is Exception) {
      final msg = e.toString();
      if (msg.contains('409')) return 'Email already registered.';
      if (msg.contains('401')) return 'Invalid email or password.';
      if (msg.contains('SocketException') || msg.contains('Connection')) {
        return 'Cannot connect to server. Check your connection.';
      }
      return 'Something went wrong. Please try again.';
    }
    return 'An unexpected error occurred.';
  }
}

final authNotifierProvider =
    AsyncNotifierProvider<AuthNotifier, AuthState>(AuthNotifier.new);

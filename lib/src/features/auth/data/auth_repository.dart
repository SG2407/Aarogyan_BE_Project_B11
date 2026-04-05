import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/network/dio_client.dart';
import '../../../core/network/token_storage.dart';

class AuthRepository {
  final Dio _dio;
  AuthRepository(this._dio);

  Future<Map<String, dynamic>> signUp({
    required String email,
    required String password,
    required String fullName,
    required String termsSignature,
  }) async {
    final response = await _dio.post('/auth/signup', data: {
      'email': email,
      'password': password,
      'full_name': fullName,
      'terms_signature': termsSignature,
    });
    final data = response.data as Map<String, dynamic>;
    await TokenStorage.saveToken(data['access_token'], data['user_id']);
    return data;
  }

  Future<Map<String, dynamic>> login({
    required String email,
    required String password,
  }) async {
    final response = await _dio.post('/auth/login', data: {
      'email': email,
      'password': password,
    });
    final data = response.data as Map<String, dynamic>;
    await TokenStorage.saveToken(data['access_token'], data['user_id']);
    return data;
  }

  Future<void> logout() => TokenStorage.clear();
}

final authRepositoryProvider = Provider<AuthRepository>(
  (ref) => AuthRepository(ref.watch(dioProvider)),
);

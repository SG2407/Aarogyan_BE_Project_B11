import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/network/dio_client.dart';

class ProfileRepository {
  final Dio _dio;
  ProfileRepository(this._dio);

  Future<Map<String, dynamic>> getProfile() async {
    final resp = await _dio.get('/profile/me');
    return resp.data as Map<String, dynamic>? ?? {};
  }

  Future<Map<String, dynamic>> upsertProfile(Map<String, dynamic> data) async {
    final resp = await _dio.put('/profile/me', data: data);
    return resp.data as Map<String, dynamic>;
  }

  /// Alias for upsertProfile used by profile screens.
  Future<Map<String, dynamic>> updateProfile(Map<String, dynamic> data) =>
      upsertProfile(data);
}

final profileRepositoryProvider = Provider<ProfileRepository>(
  (ref) => ProfileRepository(ref.watch(dioProvider)),
);

final profileProvider = FutureProvider<Map<String, dynamic>>((ref) async {
  return ref.read(profileRepositoryProvider).getProfile();
});

/// Lightweight derived provider — returns just the preferred language string.
/// All screens should watch this instead of reading profileProvider directly.
final preferredLanguageProvider = Provider<String>((ref) {
  final profileAsync = ref.watch(profileProvider);
  return profileAsync.valueOrNull?['preferred_language'] as String? ??
      'English';
});

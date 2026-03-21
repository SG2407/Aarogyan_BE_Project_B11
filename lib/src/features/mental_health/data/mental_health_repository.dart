import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/network/dio_client.dart';

class MentalHealthRepository {
  final Dio _dio;
  MentalHealthRepository(this._dio);

  /// Fetches aggregated mood dashboard data.
  Future<Map<String, dynamic>> getDashboard() async {
    final resp = await _dio.get('/mental-health/dashboard');
    return resp.data as Map<String, dynamic>;
  }
}

final mentalHealthRepositoryProvider = Provider<MentalHealthRepository>(
  (ref) => MentalHealthRepository(ref.watch(dioProvider)),
);

final mentalHealthDashboardProvider =
    FutureProvider<Map<String, dynamic>>((ref) async {
  return ref.read(mentalHealthRepositoryProvider).getDashboard();
});

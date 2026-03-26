import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/network/dio_client.dart';

class MentalHealthRepository {
  final Dio _dio;
  MentalHealthRepository(this._dio);

  /// Fetches aggregated mood dashboard data.
  /// [days] = 0 means all-time; 7, 30, 90 for filtered views.
  Future<Map<String, dynamic>> getDashboard({int days = 30}) async {
    final resp = await _dio.get(
      '/mental-health/dashboard',
      queryParameters: {'days': days},
    );
    return resp.data as Map<String, dynamic>;
  }
}

final mentalHealthRepositoryProvider = Provider<MentalHealthRepository>(
  (ref) => MentalHealthRepository(ref.watch(dioProvider)),
);

// Selected time filter (days): 7, 30, 90, 0 = all time
final dashboardFilterProvider = StateProvider<int>((ref) => 30);

final mentalHealthDashboardProvider =
    FutureProvider<Map<String, dynamic>>((ref) async {
  final days = ref.watch(dashboardFilterProvider);
  return ref.read(mentalHealthRepositoryProvider).getDashboard(days: days);
});

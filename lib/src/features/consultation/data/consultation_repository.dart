import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/network/dio_client.dart';

class ConsultationRepository {
  final Dio _dio;
  ConsultationRepository(this._dio);

  Future<List<dynamic>> listConsultations() async {
    final resp = await _dio.get('/consultations/');
    return resp.data as List;
  }

  Future<Map<String, dynamic>> createConsultation({
    required String name,
    String? startDate,
  }) async {
    final resp = await _dio.post('/consultations/', data: {
      'name': name,
      if (startDate != null) 'start_date': startDate,
    });
    return resp.data as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> getConsultation(String id) async {
    final resp = await _dio.get('/consultations/$id');
    return resp.data as Map<String, dynamic>;
  }

  Future<void> deleteConsultation(String id) async {
    await _dio.delete('/consultations/$id');
  }

  // Sessions
  Future<List<dynamic>> listSessions(String consultationId) async {
    final resp = await _dio.get('/consultations/$consultationId/sessions/');
    return resp.data as List;
  }

  Future<Map<String, dynamic>> createSession(
      String consultationId, Map<String, dynamic> data) async {
    final resp =
        await _dio.post('/consultations/$consultationId/sessions/', data: data);
    return resp.data as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> getSession(
      String consultationId, String sessionId) async {
    final resp =
        await _dio.get('/consultations/$consultationId/sessions/$sessionId');
    return resp.data as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> updateSession(String consultationId,
      String sessionId, Map<String, dynamic> data) async {
    final resp = await _dio.patch(
        '/consultations/$consultationId/sessions/$sessionId',
        data: data);
    return resp.data as Map<String, dynamic>;
  }

  Future<void> deleteSession(String consultationId, String sessionId) async {
    await _dio.delete('/consultations/$consultationId/sessions/$sessionId');
  }

  Future<Map<String, dynamic>> uploadDocument(
      String consultationId,
      String sessionId,
      String filePath,
      String fileName,
      String contentType) async {
    final formData = FormData.fromMap({
      'file': await MultipartFile.fromFile(filePath, filename: fileName),
    });
    final resp = await _dio.post(
      '/consultations/$consultationId/sessions/$sessionId/documents',
      data: formData,
    );
    return resp.data as Map<String, dynamic>;
  }

  Future<void> deleteDocument(
      String consultationId, String sessionId, String docId) async {
    await _dio.delete(
        '/consultations/$consultationId/sessions/$sessionId/documents/$docId');
  }

  Future<String> exportPdf(String consultationId) async {
    // Returns download URL — handled via StreamingResponse on backend
    return '/export/consultation/$consultationId/pdf';
  }
}

final consultationRepositoryProvider = Provider<ConsultationRepository>(
  (ref) => ConsultationRepository(ref.watch(dioProvider)),
);

final consultationsListProvider = FutureProvider<List<dynamic>>((ref) async {
  return ref.read(consultationRepositoryProvider).listConsultations();
});

final consultationDetailProvider =
    FutureProvider.family<Map<String, dynamic>, String>((ref, id) async {
  return ref.read(consultationRepositoryProvider).getConsultation(id);
});

final sessionsProvider =
    FutureProvider.family<List<dynamic>, String>((ref, consultationId) async {
  return ref.read(consultationRepositoryProvider).listSessions(consultationId);
});

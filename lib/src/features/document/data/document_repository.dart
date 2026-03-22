import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http_parser/http_parser.dart';
import '../../../core/network/dio_client.dart';

class DocumentRepository {
  final Dio _dio;
  DocumentRepository(this._dio);

  /// Upload a document and get an AI-generated structured summary.
  Future<Map<String, dynamic>> summariseDocument(
      String filePath, String fileName, String contentType) async {
    final formData = FormData.fromMap({
      'file': await MultipartFile.fromFile(
        filePath,
        filename: fileName,
        contentType: MediaType.parse(contentType),
      ),
    });
    final resp = await _dio.post(
      '/documents/summarise',
      data: formData,
      options: Options(
        // OCR on large PDFs on CPU can take several minutes
        receiveTimeout: const Duration(minutes: 5),
        sendTimeout: const Duration(minutes: 2),
      ),
    );
    return resp.data as Map<String, dynamic>;
  }
}

final documentRepositoryProvider = Provider<DocumentRepository>(
  (ref) => DocumentRepository(ref.watch(dioProvider)),
);

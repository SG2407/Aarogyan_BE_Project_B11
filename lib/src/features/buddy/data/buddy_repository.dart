import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/network/dio_client.dart';

class BuddyRepository {
  final Dio _dio;
  BuddyRepository(this._dio);

  /// Send audio file to /buddy/voice, returns {reply, mood_score, audio_base64}.
  Future<Map<String, dynamic>> sendVoice(String audioFilePath) async {
    final formData = FormData.fromMap({
      'file':
          await MultipartFile.fromFile(audioFilePath, filename: 'voice.m4a'),
    });
    final resp = await _dio.post('/buddy/voice', data: formData);
    return resp.data as Map<String, dynamic>;
  }
}

final buddyRepositoryProvider = Provider<BuddyRepository>(
  (ref) => BuddyRepository(ref.watch(dioProvider)),
);

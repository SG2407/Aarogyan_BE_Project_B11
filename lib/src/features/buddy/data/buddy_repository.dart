import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:http_parser/http_parser.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/network/dio_client.dart';

class BuddyRepository {
  final Dio _dio;
  BuddyRepository(this._dio);

  /// Send audio file to /buddy/voice with conversation history.
  /// Returns {user_text, buddy_text, mood_score, emotion, audio_base64}.
  Future<Map<String, dynamic>> sendVoice(
    String audioFilePath,
    List<Map<String, String>> history,
  ) async {
    final formData = FormData.fromMap({
      'audio': await MultipartFile.fromFile(
        audioFilePath,
        filename: 'voice.m4a',
        contentType: MediaType('audio', 'mp4'),
      ),
      if (history.isNotEmpty) 'history_json': jsonEncode(history),
    });
    final resp = await _dio.post(
      '/buddy/voice',
      data: formData,
      options: Options(
        receiveTimeout: const Duration(minutes: 5),
        sendTimeout: const Duration(minutes: 2),
      ),
    );
    return resp.data as Map<String, dynamic>;
  }
}

final buddyRepositoryProvider = Provider<BuddyRepository>(
  (ref) => BuddyRepository(ref.watch(dioProvider)),
);

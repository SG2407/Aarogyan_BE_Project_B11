import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:http_parser/http_parser.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/network/dio_client.dart';

class BuddyRepository {
  final Dio _dio;
  BuddyRepository(this._dio);

  /// Primary autonomous path — sends transcribed text, receives AI reply + audio.
  /// Latency is considerably lower than sendVoice because audio upload and
  /// server-side STT are eliminated entirely.
  Future<Map<String, dynamic>> sendText(
    String text,
    List<Map<String, String>> history, {
    String preferredLanguage = 'English',
  }) async {
    final resp = await _dio.post(
      '/buddy/chat',
      data: {
        'text': text,
        'history': history,
        'preferred_language': preferredLanguage,
      },
      options: Options(
        receiveTimeout: const Duration(minutes: 3),
        sendTimeout: const Duration(seconds: 10),
      ),
    );
    return resp.data as Map<String, dynamic>;
  }

  /// Legacy audio path — kept for future use or fallback.
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

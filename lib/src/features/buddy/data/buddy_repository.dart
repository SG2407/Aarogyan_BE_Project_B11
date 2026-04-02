import 'dart:async';
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
    String? sessionGroupId,
  }) async {
    final resp = await _dio.post(
      '/buddy/chat',
      data: {
        'text': text,
        'history': history,
        'preferred_language': preferredLanguage,
        if (sessionGroupId != null) 'session_group_id': sessionGroupId,
      },
      options: Options(
        receiveTimeout: const Duration(minutes: 3),
        sendTimeout: const Duration(seconds: 10),
      ),
    );
    return resp.data as Map<String, dynamic>;
  }

  /// Streaming path — sends recorded audio, receives NDJSON stream of events:
  ///   transcript → sentence text → sentence audio (base64 WAV) → done
  Stream<Map<String, dynamic>> streamChat(
    String audioFilePath,
    List<Map<String, String>> history, {
    String preferredLanguage = 'English',
    String? sessionGroupId,
  }) async* {
    final formData = FormData.fromMap({
      'audio': await MultipartFile.fromFile(
        audioFilePath,
        filename: 'voice.wav',
        contentType: MediaType('audio', 'wav'),
      ),
      if (history.isNotEmpty) 'history_json': jsonEncode(history),
      'preferred_language': preferredLanguage,
      if (sessionGroupId != null) 'session_group_id': sessionGroupId,
    });

    final resp = await _dio.post(
      '/buddy/chat-stream',
      data: formData,
      options: Options(
        responseType: ResponseType.stream,
        receiveTimeout: const Duration(minutes: 5),
        sendTimeout: const Duration(minutes: 2),
      ),
    );

    final stream = (resp.data as ResponseBody).stream;
    String buffer = '';

    await for (final chunk in stream) {
      buffer += utf8.decode(chunk);
      while (buffer.contains('\n')) {
        final idx = buffer.indexOf('\n');
        final line = buffer.substring(0, idx).trim();
        buffer = buffer.substring(idx + 1);
        if (line.isNotEmpty) {
          yield jsonDecode(line) as Map<String, dynamic>;
        }
      }
    }
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

  /// Sends recorded audio (+ optional transcribed text) to the backend for
  /// voice-based emotion analysis.  This does NOT participate in the
  /// conversation flow — it is a fire-and-forget side-channel.
  Future<Map<String, dynamic>> analyzeVoiceEmotion(
    String audioFilePath, {
    String? text,
    String? sessionId,
  }) async {
    final formData = FormData.fromMap({
      'audio': await MultipartFile.fromFile(
        audioFilePath,
        filename: 'voice.wav',
        contentType: MediaType('audio', 'wav'),
      ),
      if (text != null) 'text': text,
      if (sessionId != null) 'session_id': sessionId,
    });
    final resp = await _dio.post(
      '/buddy/analyze-voice',
      data: formData,
      options: Options(
        receiveTimeout: const Duration(minutes: 2),
        sendTimeout: const Duration(minutes: 1),
      ),
    );
    return resp.data as Map<String, dynamic>;
  }

  /// Fetches session-level emotion analytics for a conversation group.
  Future<Map<String, dynamic>> getSessionAnalytics(
      String sessionGroupId) async {
    final resp = await _dio.get(
      '/buddy/session-analytics/$sessionGroupId',
    );
    return resp.data as Map<String, dynamic>;
  }
}

final buddyRepositoryProvider = Provider<BuddyRepository>(
  (ref) => BuddyRepository(ref.watch(dioProvider)),
);

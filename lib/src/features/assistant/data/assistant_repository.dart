import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/network/dio_client.dart';

class AssistantRepository {
  final Dio _dio;
  AssistantRepository(this._dio);

  Future<List<dynamic>> listConversations() async {
    final resp = await _dio.get('/assistant/conversations');
    return resp.data as List;
  }

  Future<Map<String, dynamic>> createConversation({String? title}) async {
    final resp = await _dio.post('/assistant/conversations', data: {
      if (title != null) 'title': title,
    });
    return resp.data as Map<String, dynamic>;
  }

  Future<List<dynamic>> getMessages(String conversationId) async {
    final resp = await _dio.get('/assistant/conversations/$conversationId');
    final data = resp.data as Map<String, dynamic>;
    return (data['messages'] as List?) ?? [];
  }

  Future<Map<String, dynamic>> sendMessage({
    required String? conversationId,
    required String message,
  }) async {
    final resp = await _dio.post('/assistant/chat', data: {
      if (conversationId != null) 'conversation_id': conversationId,
      'message': message,
    });
    return resp.data as Map<String, dynamic>;
  }

  Future<void> deleteConversation(String conversationId) async {
    await _dio.delete('/assistant/conversations/$conversationId');
  }
}

final assistantRepositoryProvider = Provider<AssistantRepository>(
  (ref) => AssistantRepository(ref.watch(dioProvider)),
);

final conversationsListProvider = FutureProvider<List<dynamic>>((ref) async {
  return ref.read(assistantRepositoryProvider).listConversations();
});

final messagesProvider =
    FutureProvider.family<List<dynamic>, String>((ref, conversationId) async {
  return ref.read(assistantRepositoryProvider).getMessages(conversationId);
});

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/l10n/app_strings.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../features/profile/data/profile_repository.dart';
import '../../data/assistant_repository.dart';

class AssistantScreen extends ConsumerWidget {
  const AssistantScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final conversations = ref.watch(conversationsListProvider);
    final lang = ref.watch(preferredLanguageProvider);

    return Scaffold(
      appBar: AppBar(title: Text(appStr(lang, 'assistant_title'))),
      floatingActionButton: FloatingActionButton(
        backgroundColor: AppColors.primary,
        onPressed: () => _startNewChat(context, ref),
        child: const Icon(Icons.add_comment_rounded, color: Colors.white),
      ),
      body: conversations.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (list) {
          if (list.isEmpty) {
            return _EmptyState(
                lang: lang, onNew: () => _startNewChat(context, ref));
          }
          return ListView.separated(
            padding: const EdgeInsets.all(20),
            itemCount: list.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (_, i) {
              final conv = list[i] as Map<String, dynamic>;
              return _ConversationTile(
                conversation: conv,
                lang: lang,
                onTap: () => context.go('/assistant/${conv['id']}'),
                onDelete: () async {
                  await ref
                      .read(assistantRepositoryProvider)
                      .deleteConversation(conv['id']);
                  ref.invalidate(conversationsListProvider);
                },
              );
            },
          );
        },
      ),
    );
  }

  void _startNewChat(BuildContext context, WidgetRef ref) async {
    final conv =
        await ref.read(assistantRepositoryProvider).createConversation();
    ref.invalidate(conversationsListProvider);
    if (context.mounted) {
      context.go('/assistant/${conv['id']}');
    }
  }
}

class _ConversationTile extends StatelessWidget {
  final Map<String, dynamic> conversation;
  final String lang;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  const _ConversationTile({
    required this.conversation,
    required this.lang,
    required this.onTap,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final title = conversation['title'] ?? 'New Conversation';
    final date = conversation['created_at'] as String?;

    return Material(
      color: Theme.of(context).colorScheme.surface,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.secondary,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.chat_bubble_outline_rounded,
                    color: AppColors.primary, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: Theme.of(context).textTheme.titleLarge,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                    if (date != null)
                      Text(
                        _formatDate(date),
                        style: Theme.of(context)
                            .textTheme
                            .bodyMedium
                            ?.copyWith(fontSize: 12),
                      ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.delete_outline, color: AppColors.error),
                onPressed: () => _confirmDelete(context),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatDate(String iso) {
    try {
      final dt = DateTime.parse(iso).toLocal();
      return '${dt.day}/${dt.month}/${dt.year}';
    } catch (_) {
      return iso;
    }
  }

  void _confirmDelete(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(appStr(lang, 'delete_chat_title')),
        content: Text(appStr(lang, 'delete_chat_content')),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(appStr(lang, 'cancel'))),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              onDelete();
            },
            child: Text(appStr(lang, 'delete'),
                style: const TextStyle(color: AppColors.error)),
          ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final String lang;
  final VoidCallback onNew;
  const _EmptyState({required this.lang, required this.onNew});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.health_and_safety_rounded,
                size: 72, color: AppColors.primary),
            const SizedBox(height: 20),
            Text(appStr(lang, 'your_health_assistant'),
                style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 8),
            Text(
              appStr(lang, 'assistant_desc'),
              style: Theme.of(context).textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: onNew,
              icon: const Icon(Icons.add_comment_rounded),
              label: Text(appStr(lang, 'start_conversation')),
            ),
          ],
        ),
      ),
    );
  }
}

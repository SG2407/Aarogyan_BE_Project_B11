import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../../../core/l10n/app_strings.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../features/profile/data/profile_repository.dart';
import '../../data/consultation_repository.dart';

class ConsultationsScreen extends ConsumerWidget {
  const ConsultationsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final consultationsAsync = ref.watch(consultationsListProvider);
    final lang = ref.watch(preferredLanguageProvider);

    return Scaffold(
      appBar: AppBar(title: Text(appStr(lang, 'consultations_title'))),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showCreateDialog(context, ref),
        backgroundColor: AppColors.primary,
        icon: const Icon(Icons.add, color: Colors.white),
        label: Text(appStr(lang, 'new_label'), style: const TextStyle(color: Colors.white)),
      ),
      body: consultationsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (list) {
          if (list.isEmpty) {
            return _EmptyState(lang: lang, onAdd: () => _showCreateDialog(context, ref));
          }
          return ListView.builder(
            padding: const EdgeInsets.all(20),
            itemCount: list.length,
            itemBuilder: (_, i) {
              final c = list[i] as Map<String, dynamic>;
              return _ConsultationCard(
                consultation: c,
                lang: lang,
                onTap: () => context.go('/consultations/${c['id']}'),
                onDelete: () async {
                  await ref
                      .read(consultationRepositoryProvider)
                      .deleteConsultation(c['id']);
                  ref.invalidate(consultationsListProvider);
                },
              );
            },
          );
        },
      ),
    );
  }

  void _showCreateDialog(BuildContext context, WidgetRef ref) {
    final nameCtrl = TextEditingController();
    String? startDate;
    final lang = ref.read(preferredLanguageProvider);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => Container(
          decoration: BoxDecoration(
            color: Theme.of(ctx).colorScheme.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          padding: EdgeInsets.only(
            left: 24,
            right: 24,
            top: 24,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(appStr(lang, 'new_consultation'),
                  style: Theme.of(ctx).textTheme.headlineSmall),
              const SizedBox(height: 20),
              TextFormField(
                controller: nameCtrl,
                autofocus: true,
                decoration: InputDecoration(
                  labelText: appStr(lang, 'consult_name_label'),
                  hintText: 'e.g. Skin Allergy Treatment',
                ),
              ),
              const SizedBox(height: 16),
              GestureDetector(
                onTap: () async {
                  final picked = await showDatePicker(
                    context: ctx,
                    initialDate: DateTime.now(),
                    firstDate: DateTime(2000),
                    lastDate: DateTime.now(),
                    builder: (c, child) => Theme(
                      data: Theme.of(c).copyWith(
                        colorScheme: Theme.of(c).colorScheme.copyWith(
                            primary: AppColors.primary),
                      ),
                      child: child!,
                    ),
                  );
                  if (picked != null) {
                    setState(() =>
                        startDate = DateFormat('yyyy-MM-dd').format(picked));
                  }
                },
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                  decoration: BoxDecoration(
                    border: Border.all(color: Theme.of(ctx).dividerColor),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.calendar_today_outlined,
                          color: Theme.of(ctx).colorScheme.onSurface.withValues(alpha: 0.5)),
                      const SizedBox(width: 12),
                      Text(
                        startDate ?? appStr(lang, 'consult_start_date'),
                        style: TextStyle(
                          color: startDate != null
                              ? Theme.of(ctx).colorScheme.onSurface
                              : Theme.of(ctx).colorScheme.onSurface.withValues(alpha: 0.5),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: () async {
                  if (nameCtrl.text.trim().isEmpty) return;
                  await ref
                      .read(consultationRepositoryProvider)
                      .createConsultation(
                        name: nameCtrl.text.trim(),
                        startDate: startDate,
                      );
                  ref.invalidate(consultationsListProvider);
                  if (ctx.mounted) Navigator.pop(ctx);
                },
                child: Text(appStr(lang, 'create_consultation')),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ConsultationCard extends StatelessWidget {
  final Map<String, dynamic> consultation;
  final String lang;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  const _ConsultationCard({
    required this.consultation,
    required this.lang,
    required this.onTap,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(20),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.secondary,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Icon(
                    Icons.folder_special_rounded,
                    color: AppColors.primary,
                    size: 26,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        consultation['name'] ?? '',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      if (consultation['start_date'] != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          'Started ${consultation['start_date']}',
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                      ],
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline_rounded,
                      color: AppColors.error, size: 20),
                  onPressed: () async {
                    final confirmed = await showDialog<bool>(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        title: Text(appStr(lang, 'delete_consultation')),
                        content: Text(
                          "Delete \"${consultation['name']}\"? All sessions and documents will be permanently removed.",
                        ),
                        actions: [
                          TextButton(
                              onPressed: () => Navigator.pop(ctx, false),
                              child: Text(appStr(lang, 'cancel'))),
                          TextButton(
                              onPressed: () => Navigator.pop(ctx, true),
                              child: Text(appStr(lang, 'delete'),
                                  style: const TextStyle(color: AppColors.error))),
                        ],
                      ),
                    );
                    if (confirmed == true) onDelete();
                  },
                ),
                Icon(Icons.arrow_forward_ios_rounded,
                    size: 14, color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final String lang;
  final VoidCallback onAdd;
  const _EmptyState({required this.lang, required this.onAdd});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.secondary,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.folder_open_rounded,
                  color: AppColors.primary, size: 40),
            ),
            const SizedBox(height: 24),
            Text(appStr(lang, 'no_consultations'),
                style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 8),
            Text(
              appStr(lang, 'no_consultations_sub'),
              style: Theme.of(context).textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),
            ElevatedButton.icon(
              onPressed: onAdd,
              icon: const Icon(Icons.add),
              label: Text(appStr(lang, 'create_consultation')),
            ),
          ],
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:open_file/open_file.dart';
import '../../../../core/theme/app_theme.dart';
import '../../data/consultation_repository.dart';

class ConsultationDetailScreen extends ConsumerWidget {
  final String consultationId;
  const ConsultationDetailScreen({super.key, required this.consultationId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final consultationAsync =
        ref.watch(consultationDetailProvider(consultationId));
    final sessionsAsync = ref.watch(sessionsProvider(consultationId));

    return Scaffold(
      appBar: AppBar(
        title: consultationAsync.maybeWhen(
          data: (c) => Text(c['name'] ?? 'Consultation'),
          orElse: () => const Text('Consultation'),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.picture_as_pdf_rounded),
            tooltip: 'Export PDF',
            onPressed: () => _exportPdf(context, ref),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showAddSessionSheet(context, ref),
        backgroundColor: AppColors.primary,
        icon: const Icon(Icons.add, color: Colors.white),
        label: const Text('Add Session', style: TextStyle(color: Colors.white)),
      ),
      body: sessionsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (sessions) {
          if (sessions.isEmpty) {
            return _EmptySessionsState(
              onAdd: () => _showAddSessionSheet(context, ref),
            );
          }
          return ListView.builder(
            padding: const EdgeInsets.all(20),
            itemCount: sessions.length,
            itemBuilder: (_, i) {
              final s = sessions[i] as Map<String, dynamic>;
              return _SessionTile(
                session: s,
                index: i + 1,
                onTap: () => context.go(
                  '/consultations/$consultationId/sessions/${s['id']}',
                ),
              );
            },
          );
        },
      ),
    );
  }

  void _exportPdf(BuildContext context, WidgetRef ref) async {
    final repo = ref.read(consultationRepositoryProvider);
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(
      const SnackBar(content: Text('Generating PDF...')),
    );
    try {
      final path = await repo.exportPdf(consultationId);
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(
        SnackBar(
          content: const Text('PDF downloaded'),
          action: SnackBarAction(
            label: 'Open',
            onPressed: () => OpenFile.open(path),
          ),
          duration: const Duration(seconds: 10),
        ),
      );
    } catch (e) {
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(
        SnackBar(content: Text('Export failed: $e')),
      );
    }
  }

  void _showAddSessionSheet(BuildContext context, WidgetRef ref) {
    final visitDateCtrl = TextEditingController();
    final symptomsCtrl = TextEditingController();
    final diagnosisCtrl = TextEditingController();
    final medicationsCtrl = TextEditingController();
    final notesCtrl = TextEditingController();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.85,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        builder: (_, scrollCtrl) => Container(
          decoration: BoxDecoration(
            color: Theme.of(ctx).colorScheme.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: ListView(
            controller: scrollCtrl,
            padding: EdgeInsets.only(
              left: 24,
              right: 24,
              top: 24,
              bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
            ),
            children: [
              Text('Add Session', style: Theme.of(ctx).textTheme.headlineSmall),
              const SizedBox(height: 20),
              _DatePickerField(
                controller: visitDateCtrl,
                label: 'Date of Visit',
              ),
              const SizedBox(height: 14),
              _buildField(symptomsCtrl, 'Symptoms', maxLines: 3),
              const SizedBox(height: 14),
              _buildField(diagnosisCtrl, 'Diagnosis', maxLines: 2),
              const SizedBox(height: 14),
              _buildField(medicationsCtrl, 'Medications', maxLines: 3),
              const SizedBox(height: 14),
              _buildField(notesCtrl, 'Doctor Notes', maxLines: 4),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: () async {
                  if (visitDateCtrl.text.isEmpty) {
                    ScaffoldMessenger.of(ctx).showSnackBar(
                      const SnackBar(
                          content: Text('Please select a visit date')),
                    );
                    return;
                  }
                  await ref.read(consultationRepositoryProvider).createSession(
                    consultationId,
                    {
                      'visit_date': visitDateCtrl.text,
                      if (symptomsCtrl.text.isNotEmpty)
                        'symptoms': symptomsCtrl.text,
                      if (diagnosisCtrl.text.isNotEmpty)
                        'diagnosis': diagnosisCtrl.text,
                      if (medicationsCtrl.text.isNotEmpty)
                        'medications': medicationsCtrl.text,
                      if (notesCtrl.text.isNotEmpty)
                        'doctor_notes': notesCtrl.text,
                    },
                  );
                  ref.invalidate(sessionsProvider(consultationId));
                  if (ctx.mounted) Navigator.pop(ctx);
                },
                child: const Text('Save Session'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildField(TextEditingController ctrl, String label,
      {int maxLines = 1}) {
    return TextFormField(
      controller: ctrl,
      maxLines: maxLines,
      decoration: InputDecoration(labelText: label),
    );
  }
}

class _DatePickerField extends StatefulWidget {
  final TextEditingController controller;
  final String label;
  const _DatePickerField({required this.controller, required this.label});

  @override
  State<_DatePickerField> createState() => _DatePickerFieldState();
}

class _DatePickerFieldState extends State<_DatePickerField> {
  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: widget.controller,
      readOnly: true,
      decoration: InputDecoration(
        labelText: widget.label,
        prefixIcon: const Icon(Icons.calendar_today_outlined),
      ),
      onTap: () async {
        final picked = await showDatePicker(
          context: context,
          initialDate: DateTime.now(),
          firstDate: DateTime(2000),
          lastDate: DateTime.now(),
          builder: (ctx, child) => Theme(
            data: Theme.of(ctx).copyWith(
              colorScheme: Theme.of(ctx).colorScheme.copyWith(
                  primary: AppColors.primary),
            ),
            child: child!,
          ),
        );
        if (picked != null) {
          widget.controller.text = DateFormat('yyyy-MM-dd').format(picked);
          setState(() {});
        }
      },
    );
  }
}

class _SessionTile extends StatelessWidget {
  final Map<String, dynamic> session;
  final int index;
  final VoidCallback onTap;

  const _SessionTile(
      {required this.session, required this.index, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final docs = (session['session_documents'] as List?)?.length ?? 0;
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
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.secondary,
                    shape: BoxShape.circle,
                  ),
                  child: Center(
                    child: Text(
                      '$index',
                      style: const TextStyle(
                        color: AppColors.primary,
                        fontWeight: FontWeight.w700,
                        fontSize: 16,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Session $index · ${session['visit_date'] ?? ''}',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      if (session['diagnosis'] != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          session['diagnosis'],
                          style: Theme.of(context).textTheme.bodyMedium,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                      if (docs > 0) ...[
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Icon(Icons.attach_file_rounded,
                                size: 14, color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5)),
                            const SizedBox(width: 4),
                            Text('$docs document${docs > 1 ? 's' : ''}',
                                style: Theme.of(context)
                                    .textTheme
                                    .bodyMedium
                                    ?.copyWith(fontSize: 12)),
                          ],
                        ),
                      ],
                    ],
                  ),
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

class _EmptySessionsState extends StatelessWidget {
  final VoidCallback onAdd;
  const _EmptySessionsState({required this.onAdd});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.event_note_rounded,
                size: 64, color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5)),
            const SizedBox(height: 16),
            Text('No sessions yet',
                style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 8),
            Text(
              'Add your first doctor visit to start building your consultation timeline.',
              style: Theme.of(context).textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: onAdd,
              icon: const Icon(Icons.add),
              label: const Text('Add Session'),
            ),
          ],
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';
import 'package:intl/intl.dart';
import '../../../../core/theme/app_theme.dart';
import '../../data/consultation_repository.dart';

class SessionDetailScreen extends ConsumerStatefulWidget {
  final String consultationId;
  final String sessionId;
  const SessionDetailScreen({
    super.key,
    required this.consultationId,
    required this.sessionId,
  });

  @override
  ConsumerState<SessionDetailScreen> createState() =>
      _SessionDetailScreenState();
}

class _SessionDetailScreenState extends ConsumerState<SessionDetailScreen> {
  bool _editing = false;
  bool _uploading = false;

  late TextEditingController _visitDateCtrl;
  late TextEditingController _symptomsCtrl;
  late TextEditingController _diagnosisCtrl;
  late TextEditingController _medicationsCtrl;
  late TextEditingController _notesCtrl;

  Map<String, dynamic>? _sessionData;

  @override
  void initState() {
    super.initState();
    _visitDateCtrl = TextEditingController();
    _symptomsCtrl = TextEditingController();
    _diagnosisCtrl = TextEditingController();
    _medicationsCtrl = TextEditingController();
    _notesCtrl = TextEditingController();
  }

  @override
  void dispose() {
    _visitDateCtrl.dispose();
    _symptomsCtrl.dispose();
    _diagnosisCtrl.dispose();
    _medicationsCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  void _populateControllers(Map<String, dynamic> session) {
    _visitDateCtrl.text = session['visit_date'] ?? '';
    _symptomsCtrl.text = session['symptoms'] ?? '';
    _diagnosisCtrl.text = session['diagnosis'] ?? '';
    _medicationsCtrl.text = session['medications'] ?? '';
    _notesCtrl.text = session['doctor_notes'] ?? '';
  }

  Future<void> _save() async {
    final repo = ref.read(consultationRepositoryProvider);
    await repo.updateSession(
      widget.consultationId,
      widget.sessionId,
      {
        'visit_date': _visitDateCtrl.text,
        'symptoms': _symptomsCtrl.text,
        'diagnosis': _diagnosisCtrl.text,
        'medications': _medicationsCtrl.text,
        'doctor_notes': _notesCtrl.text,
      },
    );
    ref.invalidate(sessionsProvider(widget.consultationId));
    setState(() => _editing = false);
  }

  Future<void> _pickAndUploadDocument(String sessionId) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf', 'jpg', 'jpeg', 'png'],
    );
    if (result == null || result.files.isEmpty) return;
    final file = result.files.first;
    if (file.path == null) return;
    setState(() => _uploading = true);
    try {
      await ref.read(consultationRepositoryProvider).uploadDocument(
            widget.consultationId,
            sessionId,
            file.path!,
            file.name,
            file.extension == 'pdf' ? 'application/pdf' : 'image/jpeg',
          );
      ref.invalidate(sessionsProvider(widget.consultationId));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Document uploaded successfully')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Upload failed: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final sessionsAsync = ref.watch(sessionsProvider(widget.consultationId));

    return sessionsAsync.when(
      loading: () =>
          const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (e, _) => Scaffold(body: Center(child: Text('Error: $e'))),
      data: (sessions) {
        final sessionList = sessions;
        final idx = sessionList.indexWhere((s) => s['id'] == widget.sessionId);
        if (idx == -1) {
          return const Scaffold(body: Center(child: Text('Session not found')));
        }
        final session = Map<String, dynamic>.from(sessionList[idx]);
        if (_sessionData == null) {
          _sessionData = session;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _populateControllers(session);
            if (mounted) setState(() {});
          });
        }
        final docs = (session['session_documents'] as List?) ?? [];

        return Scaffold(
          appBar: AppBar(
            title: Text('Session ${idx + 1}'),
            actions: [
              if (_editing)
                TextButton(
                  onPressed: _save,
                  child: const Text('Save',
                      style: TextStyle(
                          color: AppColors.primary,
                          fontWeight: FontWeight.w600)),
                )
              else
                IconButton(
                  icon: const Icon(Icons.edit_outlined),
                  tooltip: 'Edit',
                  onPressed: () => setState(() => _editing = true),
                ),
            ],
          ),
          body: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              // --- Visit Date ---
              _SectionCard(
                title: 'Visit Date',
                child: _editing
                    ? _DatePickerField(controller: _visitDateCtrl)
                    : _InfoRow(
                        icon: Icons.calendar_today_outlined,
                        label: session['visit_date'] ?? '—',
                      ),
              ),
              const SizedBox(height: 12),

              // --- Symptoms ---
              _SectionCard(
                title: 'Symptoms',
                child: _editing
                    ? TextFormField(
                        controller: _symptomsCtrl,
                        maxLines: 3,
                        decoration: const InputDecoration(
                            hintText: 'e.g. fever, headache'),
                      )
                    : _TextView(text: session['symptoms']),
              ),
              const SizedBox(height: 12),

              // --- Diagnosis ---
              _SectionCard(
                title: 'Diagnosis',
                child: _editing
                    ? TextFormField(
                        controller: _diagnosisCtrl,
                        maxLines: 2,
                        decoration:
                            const InputDecoration(hintText: 'e.g. Viral fever'),
                      )
                    : _TextView(text: session['diagnosis']),
              ),
              const SizedBox(height: 12),

              // --- Medications ---
              _SectionCard(
                title: 'Medications',
                child: _editing
                    ? TextFormField(
                        controller: _medicationsCtrl,
                        maxLines: 3,
                        decoration: const InputDecoration(
                            hintText: 'e.g. Paracetamol 500mg - twice daily'),
                      )
                    : _TextView(text: session['medications']),
              ),
              const SizedBox(height: 12),

              // --- Doctor Notes ---
              _SectionCard(
                title: 'Doctor Notes',
                child: _editing
                    ? TextFormField(
                        controller: _notesCtrl,
                        maxLines: 4,
                        decoration: const InputDecoration(
                            hintText: 'Any additional notes...'),
                      )
                    : _TextView(text: session['doctor_notes']),
              ),
              const SizedBox(height: 20),

              // --- Documents ---
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Documents',
                      style: Theme.of(context).textTheme.titleLarge),
                  _uploading
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : TextButton.icon(
                          onPressed: () =>
                              _pickAndUploadDocument(session['id']),
                          icon: const Icon(Icons.upload_file_rounded, size: 18),
                          label: const Text('Upload'),
                        ),
                ],
              ),
              const SizedBox(height: 8),
              if (docs.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Text(
                    'No documents uploaded yet. Upload a prescription or test report.',
                    style: Theme.of(context)
                        .textTheme
                        .bodyMedium
                        ?.copyWith(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5)),
                  ),
                )
              else
                ...docs
                    .map((doc) => _DocTile(doc: doc as Map<String, dynamic>)),
            ],
          ),
        );
      },
    );
  }
}

class _SectionCard extends StatelessWidget {
  final String title;
  final Widget child;
  const _SectionCard({required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: AppColors.primary, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          child,
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  const _InfoRow({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 18, color: AppColors.primary),
        const SizedBox(width: 8),
        Text(label, style: Theme.of(context).textTheme.bodyLarge),
      ],
    );
  }
}

class _TextView extends StatelessWidget {
  final String? text;
  const _TextView({this.text});

  @override
  Widget build(BuildContext context) {
    if (text == null || text!.isEmpty) {
      return Text('—',
          style: Theme.of(context)
              .textTheme
              .bodyMedium
              ?.copyWith(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5)));
    }
    return Text(text!, style: Theme.of(context).textTheme.bodyLarge);
  }
}

class _DocTile extends StatelessWidget {
  final Map<String, dynamic> doc;
  const _DocTile({required this.doc});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.secondary,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          const Icon(Icons.insert_drive_file_outlined,
              color: AppColors.primary, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(doc['file_name'] ?? 'Document',
                    style: Theme.of(context)
                        .textTheme
                        .titleLarge
                        ?.copyWith(fontSize: 14)),
                if (doc['extracted_text'] != null &&
                    (doc['extracted_text'] as String).isNotEmpty)
                  Text(
                    'Scanned • ${(doc['extracted_text'] as String).length} chars extracted',
                    style: Theme.of(context)
                        .textTheme
                        .bodyMedium
                        ?.copyWith(fontSize: 12),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DatePickerField extends StatefulWidget {
  final TextEditingController controller;
  const _DatePickerField({required this.controller});

  @override
  State<_DatePickerField> createState() => _DatePickerFieldState();
}

class _DatePickerFieldState extends State<_DatePickerField> {
  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: widget.controller,
      readOnly: true,
      decoration: const InputDecoration(
        hintText: 'Select date',
        prefixIcon: Icon(Icons.calendar_today_outlined),
      ),
      onTap: () async {
        final picked = await showDatePicker(
          context: context,
          initialDate:
              DateTime.tryParse(widget.controller.text) ?? DateTime.now(),
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

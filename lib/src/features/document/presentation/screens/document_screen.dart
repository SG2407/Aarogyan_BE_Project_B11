import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';
import '../../../../core/theme/app_theme.dart';
import '../../data/document_repository.dart';

class DocumentSummary {
  final String fileName;
  final Map<String, dynamic> summary;
  final String rawText;
  DocumentSummary(
      {required this.fileName, required this.summary, required this.rawText});
}

final _documentSummaryProvider = StateProvider<DocumentSummary?>((ref) => null);
final _loadingProvider = StateProvider<bool>((ref) => false);

class DocumentScreen extends ConsumerWidget {
  const DocumentScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final summary = ref.watch(_documentSummaryProvider);
    final loading = ref.watch(_loadingProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('Document Scanner')),
      body: summary == null
          ? _UploadPrompt(
              loading: loading, onUpload: () => _pickFile(context, ref))
          : _SummaryView(
              summary: summary,
              onScanAnother: () =>
                  ref.read(_documentSummaryProvider.notifier).state = null,
            ),
    );
  }

  Future<void> _pickFile(BuildContext context, WidgetRef ref) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf', 'jpg', 'jpeg', 'png'],
    );
    if (result == null || result.files.isEmpty) return;
    final file = result.files.first;
    if (file.path == null) return;

    ref.read(_loadingProvider.notifier).state = true;
    try {
      final repo = ref.read(documentRepositoryProvider);
      final data = await repo.summariseDocument(
        file.path!,
        file.name,
        file.extension == 'pdf' ? 'application/pdf' : 'image/jpeg',
      );
      ref.read(_documentSummaryProvider.notifier).state = DocumentSummary(
        fileName: file.name,
        summary: data['summary'] as Map<String, dynamic>? ?? {},
        rawText: data['extracted_text'] ?? '',
      );
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to scan document: $e')),
        );
      }
    } finally {
      ref.read(_loadingProvider.notifier).state = false;
    }
  }
}

class _UploadPrompt extends StatelessWidget {
  final bool loading;
  final VoidCallback onUpload;

  const _UploadPrompt({required this.loading, required this.onUpload});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 100,
              height: 100,
              decoration: BoxDecoration(
                color: AppColors.secondary,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.document_scanner_rounded,
                  size: 48, color: AppColors.primary),
            ),
            const SizedBox(height: 24),
            Text('Scan a Document',
                style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 12),
            Text(
              'Upload a prescription, test report, discharge summary, or any health document. Our AI will extract and explain the key information.',
              style: Theme.of(context).textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),
            if (loading)
              Column(
                children: [
                  const CircularProgressIndicator(),
                  const SizedBox(height: 16),
                  Text('Scanning document...',
                      style: Theme.of(context).textTheme.bodyMedium),
                ],
              )
            else
              ElevatedButton.icon(
                onPressed: onUpload,
                style: ElevatedButton.styleFrom(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                ),
                icon: const Icon(Icons.upload_file_rounded),
                label: const Text('Choose File'),
              ),
            const SizedBox(height: 12),
            if (!loading)
              Text(
                'Supports PDF, JPG, PNG',
                style: Theme.of(context)
                    .textTheme
                    .bodyMedium
                    ?.copyWith(color: AppColors.textSecondary),
              ),
          ],
        ),
      ),
    );
  }
}

class _SummaryView extends StatelessWidget {
  final DocumentSummary summary;
  final VoidCallback onScanAnother;

  const _SummaryView({required this.summary, required this.onScanAnother});

  @override
  Widget build(BuildContext context) {
    final s = summary.summary;

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        // Header
        Row(
          children: [
            const Icon(Icons.check_circle_rounded,
                color: AppColors.primary, size: 24),
            const SizedBox(width: 8),
            Expanded(
              child: Text(summary.fileName,
                  style: Theme.of(context).textTheme.titleLarge,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis),
            ),
          ],
        ),
        const SizedBox(height: 20),

        // Summary sections
        if (s['document_type'] != null) ...[
          _SummarySection(title: 'Document Type', content: s['document_type']),
          const SizedBox(height: 12),
        ],
        if (s['patient'] != null) ...[
          _SummarySection(title: 'Patient Info', content: s['patient']),
          const SizedBox(height: 12),
        ],
        if (s['diagnosis'] != null) ...[
          _SummarySection(title: 'Diagnosis', content: s['diagnosis']),
          const SizedBox(height: 12),
        ],
        if (s['medications'] != null) ...[
          _SummarySection(title: 'Medications', content: s['medications']),
          const SizedBox(height: 12),
        ],
        if (s['tests'] != null) ...[
          _SummarySection(title: 'Test Results', content: s['tests']),
          const SizedBox(height: 12),
        ],
        if (s['instructions'] != null) ...[
          _SummarySection(title: 'Instructions', content: s['instructions']),
          const SizedBox(height: 12),
        ],
        if (s['follow_up'] != null) ...[
          _SummarySection(title: 'Follow-up', content: s['follow_up']),
          const SizedBox(height: 12),
        ],
        if (s['summary'] != null) ...[
          _SummarySection(title: 'AI Summary', content: s['summary']),
          const SizedBox(height: 12),
        ],

        // If none of the above keys present, show raw summary
        if (s.isEmpty && summary.rawText.isNotEmpty) ...[
          _SummarySection(title: 'Extracted Text', content: summary.rawText),
          const SizedBox(height: 12),
        ],

        const SizedBox(height: 20),
        OutlinedButton.icon(
          onPressed: onScanAnother,
          icon: const Icon(Icons.refresh_rounded),
          label: const Text('Scan Another Document'),
        ),
      ],
    );
  }
}

class _SummarySection extends StatelessWidget {
  final String title;
  final dynamic content;

  const _SummarySection({required this.title, required this.content});

  String _format(dynamic v) {
    if (v is List) return v.join('\n• ');
    if (v is Map) {
      return v.entries.map((e) => '${e.key}: ${e.value}').join('\n');
    }
    return v.toString();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: AppColors.primary,
                    fontWeight: FontWeight.w600,
                  )),
          const SizedBox(height: 6),
          Text(_format(content), style: Theme.of(context).textTheme.bodyLarge),
        ],
      ),
    );
  }
}

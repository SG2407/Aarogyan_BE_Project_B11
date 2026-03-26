import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';
import '../../../../core/theme/app_theme.dart';
import '../../data/document_repository.dart';

class DocumentResult {
  final String fileName;
  final String documentType;
  final String explanation;
  final List<String> keyFindings;
  final int confidenceScore;
  final String disclaimer;
  final String rawText;

  DocumentResult({
    required this.fileName,
    required this.documentType,
    required this.explanation,
    required this.keyFindings,
    required this.confidenceScore,
    required this.disclaimer,
    required this.rawText,
  });
}

final _documentResultProvider = StateProvider<DocumentResult?>((ref) => null);
final _loadingProvider = StateProvider<bool>((ref) => false);

class DocumentScreen extends ConsumerWidget {
  const DocumentScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final result = ref.watch(_documentResultProvider);
    final loading = ref.watch(_loadingProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Document Scanner')),
      body: result == null
          ? _UploadPrompt(
              loading: loading,
              onPickFile: () => _pickFile(context, ref),
              onCamera: () => _takePhoto(context, ref),
            )
          : _ResultView(
              result: result,
              onScanAnother: () =>
                  ref.read(_documentResultProvider.notifier).state = null,
            ),
    );
  }

  Future<void> _pickFile(BuildContext context, WidgetRef ref) async {
    final picked = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf', 'jpg', 'jpeg', 'png'],
    );
    if (picked == null || picked.files.isEmpty) return;
    final file = picked.files.first;
    if (file.path == null) return;

    String contentType;
    switch (file.extension?.toLowerCase()) {
      case 'pdf':
        contentType = 'application/pdf';
        break;
      case 'png':
        contentType = 'image/png';
        break;
      default:
        contentType = 'image/jpeg';
    }
    await _processFile(context, ref, file.path!, file.name, contentType);
  }

  Future<void> _takePhoto(BuildContext context, WidgetRef ref) async {
    final picked = await ImagePicker().pickImage(
      source: ImageSource.camera,
      imageQuality: 85,
    );
    if (picked == null) return;
    final fileName = 'scan_${DateTime.now().millisecondsSinceEpoch}.jpg';
    await _processFile(context, ref, picked.path, fileName, 'image/jpeg');
  }

  Future<void> _processFile(
    BuildContext context,
    WidgetRef ref,
    String path,
    String name,
    String contentType,
  ) async {
    ref.read(_loadingProvider.notifier).state = true;
    try {
      final fileSize = await File(path).length();
      if (fileSize > 1536 * 1024) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                  'File too large (${(fileSize / (1024 * 1024)).toStringAsFixed(1)} MB). Please use a document under 1.5 MB.'),
              backgroundColor: Colors.red.shade700,
            ),
          );
        }
        return;
      }
      final repo = ref.read(documentRepositoryProvider);
      final data = await repo.summariseDocument(path, name, contentType);
      final summary = data['summary'] as Map<String, dynamic>? ?? {};
      ref.read(_documentResultProvider.notifier).state = DocumentResult(
        fileName: name,
        documentType: summary['document_type']?.toString() ?? 'Document',
        explanation: summary['explanation']?.toString() ?? '',
        keyFindings: (summary['key_findings'] as List<dynamic>?)
                ?.map((e) => e.toString())
                .toList() ??
            [],
        confidenceScore: (summary['confidence_score'] as num?)?.toInt() ?? 70,
        disclaimer: summary['disclaimer']?.toString() ?? '',
        rawText: data['ocr_text']?.toString() ?? '',
      );
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to scan document: $e'),
            backgroundColor: Colors.red.shade700,
          ),
        );
      }
    } finally {
      ref.read(_loadingProvider.notifier).state = false;
    }
  }
}

// ─── Upload prompt ────────────────────────────────────────────────────────────

class _UploadPrompt extends StatelessWidget {
  final bool loading;
  final VoidCallback onPickFile;
  final VoidCallback onCamera;

  const _UploadPrompt({
    required this.loading,
    required this.onPickFile,
    required this.onCamera,
  });

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
                color: Theme.of(context).colorScheme.secondary,
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
              'Upload a prescription, test report, discharge summary, or any health document. Our AI will explain what it means in simple words.',
              style: Theme.of(context).textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),
            if (loading)
              Column(
                children: [
                  const CircularProgressIndicator(),
                  const SizedBox(height: 16),
                  Text(
                    'Scanning & analysing document…\nThis may take a minute.',
                    style: Theme.of(context).textTheme.bodyMedium,
                    textAlign: TextAlign.center,
                  ),
                ],
              )
            else
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: onCamera,
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        side: const BorderSide(color: AppColors.primary),
                        foregroundColor: AppColors.primary,
                      ),
                      icon: const Icon(Icons.camera_alt_rounded),
                      label: const Text('Camera'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: onPickFile,
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                      ),
                      icon: const Icon(Icons.upload_file_rounded),
                      label: const Text('Choose File'),
                    ),
                  ),
                ],
              ),
            const SizedBox(height: 12),
            if (!loading)
              Text(
                'Camera · PDF · JPG · PNG  (max 1.5 MB)',
                style: Theme.of(context)
                    .textTheme
                    .bodyMedium
                    ?.copyWith(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5)),
              ),
          ],
        ),
      ),
    );
  }
}

// ─── Result view ──────────────────────────────────────────────────────────────

class _ResultView extends StatelessWidget {
  final DocumentResult result;
  final VoidCallback onScanAnother;

  const _ResultView({required this.result, required this.onScanAnother});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        // ── File header ──
        Row(
          children: [
            const Icon(Icons.check_circle_rounded,
                color: AppColors.primary, size: 24),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                result.fileName,
                style: Theme.of(context).textTheme.titleMedium,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                result.documentType,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: AppColors.primary,
                      fontWeight: FontWeight.w600,
                    ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),

        // ── AI Explanation ──
        _Card(
          icon: Icons.auto_awesome_rounded,
          iconColor: AppColors.primary,
          title: 'AI Explanation',
          child: Text(
            result.explanation,
            style: Theme.of(context).textTheme.bodyLarge,
          ),
        ),
        const SizedBox(height: 14),

        // ── Key Findings ──
        if (result.keyFindings.isNotEmpty) ...[
          _Card(
            icon: Icons.fact_check_rounded,
            iconColor: Colors.teal,
            title: 'Key Findings',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: result.keyFindings
                  .map((f) => Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('• ',
                                style: TextStyle(fontWeight: FontWeight.bold)),
                            Expanded(
                              child: Text(
                                f,
                                style: Theme.of(context).textTheme.bodyMedium,
                              ),
                            ),
                          ],
                        ),
                      ))
                  .toList(),
            ),
          ),
          const SizedBox(height: 14),
        ],

        // ── Confidence Score ──
        _Card(
          icon: Icons.analytics_rounded,
          iconColor: _confidenceColor(result.confidenceScore),
          title: 'Analysis Confidence',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    _confidenceLabel(result.confidenceScore),
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: _confidenceColor(result.confidenceScore),
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                  Text(
                    '${result.confidenceScore}%',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          color: _confidenceColor(result.confidenceScore),
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: LinearProgressIndicator(
                  value: result.confidenceScore / 100,
                  minHeight: 8,
                  backgroundColor: Colors.grey.shade200,
                  valueColor: AlwaysStoppedAnimation(
                      _confidenceColor(result.confidenceScore)),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Reflects how clearly the document text was extracted by OCR.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5),
                    ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),

        // ── Disclaimer ──
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.amber.shade50,
            border: Border.all(color: Colors.amber.shade300),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.info_outline_rounded,
                  color: Colors.amber.shade700, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  result.disclaimer,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Colors.amber.shade900,
                      ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),

        OutlinedButton.icon(
          onPressed: onScanAnother,
          icon: const Icon(Icons.refresh_rounded),
          label: const Text('Scan Another Document'),
        ),
        const SizedBox(height: 20),
      ],
    );
  }

  Color _confidenceColor(int score) {
    if (score >= 80) return Colors.green;
    if (score >= 55) return Colors.orange;
    return Colors.red;
  }

  String _confidenceLabel(int score) {
    if (score >= 80) return 'High confidence';
    if (score >= 55) return 'Moderate confidence';
    return 'Low confidence — OCR quality was poor';
  }
}

// ─── Shared card widget ───────────────────────────────────────────────────────

class _Card extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final Widget child;

  const _Card({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: iconColor, size: 18),
              const SizedBox(width: 8),
              Text(
                title,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: iconColor,
                      fontWeight: FontWeight.w600,
                    ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }
}

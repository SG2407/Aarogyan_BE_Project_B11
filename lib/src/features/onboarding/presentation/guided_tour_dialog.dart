import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_theme.dart';
import 'guided_tour_provider.dart';

/// Shows the "Would you like a guided tour?" dialog.
/// Returns true if user selected yes, false if no.
/// Also sets the [tourLanguageProvider] based on user selection.
Future<bool> showGuidedTourDialog(BuildContext context, WidgetRef ref) async {
  final result = await showGeneralDialog<bool>(
    context: context,
    barrierDismissible: false,
    barrierColor: Colors.black.withValues(alpha: 0.6),
    transitionDuration: const Duration(milliseconds: 400),
    transitionBuilder: (context, anim, secondAnim, child) {
      return SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0, 0.15),
          end: Offset.zero,
        ).animate(CurvedAnimation(parent: anim, curve: Curves.easeOutCubic)),
        child: FadeTransition(opacity: anim, child: child),
      );
    },
    pageBuilder: (context, anim, secondAnim) {
      return _GuidedTourDialogContent(ref: ref);
    },
  );
  return result ?? false;
}

class _GuidedTourDialogContent extends StatefulWidget {
  final WidgetRef ref;
  const _GuidedTourDialogContent({required this.ref});

  @override
  State<_GuidedTourDialogContent> createState() =>
      _GuidedTourDialogContentState();
}

class _GuidedTourDialogContentState extends State<_GuidedTourDialogContent> {
  String _selectedLang = 'en';

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Material(
        color: Colors.transparent,
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 32),
          padding: const EdgeInsets.all(28),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(
                color: AppColors.primary.withValues(alpha: 0.2),
                blurRadius: 30,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Icon
                Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.explore_rounded,
                    color: AppColors.primary,
                    size: 36,
                  ),
                ),
                const SizedBox(height: 20),
                // Title
                Text(
                  'Welcome to Aarogyan! 🌿',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                // Description
                Text(
                  'Would you like a quick guided tour of the app? '
                  'We\'ll walk you through all the features with voice instructions '
                  'and on-screen highlights so you feel right at home.',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        height: 1.5,
                      ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                // Language selector
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.translate_rounded,
                              size: 18, color: AppColors.primary),
                          const SizedBox(width: 8),
                          Text(
                            'Choose tour language',
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 14,
                              color: Theme.of(context).colorScheme.onSurface,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          _LangChip(
                            label: 'English',
                            value: 'en',
                            selected: _selectedLang == 'en',
                            onTap: () =>
                                setState(() => _selectedLang = 'en'),
                          ),
                          const SizedBox(width: 8),
                          _LangChip(
                            label: 'हिन्दी',
                            value: 'hi',
                            selected: _selectedLang == 'hi',
                            onTap: () =>
                                setState(() => _selectedLang = 'hi'),
                          ),
                          const SizedBox(width: 8),
                          _LangChip(
                            label: 'मराठी',
                            value: 'mr',
                            selected: _selectedLang == 'mr',
                            onTap: () =>
                                setState(() => _selectedLang = 'mr'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                // What you'll learn
                Container(
                  margin: const EdgeInsets.symmetric(vertical: 12),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Column(
                    children: const [
                      _FeatureRow(
                          Icons.chat_bubble_rounded, 'AI Health Assistant'),
                      SizedBox(height: 8),
                      _FeatureRow(
                          Icons.document_scanner_rounded, 'Document Scanner'),
                      SizedBox(height: 8),
                      _FeatureRow(
                          Icons.favorite_rounded, 'Emotional Buddy (Orbz)'),
                      SizedBox(height: 8),
                      _FeatureRow(
                          Icons.bar_chart_rounded, 'Mental Health Tracker'),
                      SizedBox(height: 8),
                      _FeatureRow(Icons.folder_special_rounded,
                          'Consultation Tracker'),
                      SizedBox(height: 8),
                      _FeatureRow(Icons.person_rounded, 'Profile Setup'),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                // Yes button
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton.icon(
                    onPressed: () {
                      widget.ref
                          .read(tourLanguageProvider.notifier)
                          .state = _selectedLang;
                      Navigator.of(context).pop(true);
                    },
                    icon: const Icon(Icons.play_arrow_rounded),
                    label: const Text(
                      'Yes, show me around!',
                      style: TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w600),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                // No button
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: TextButton(
                    onPressed: () => Navigator.of(context).pop(false),
                    child: Text(
                      'No thanks, I\'ll explore on my own',
                      style: TextStyle(
                        color: Theme.of(context)
                            .colorScheme
                            .onSurface
                            .withValues(alpha: 0.6),
                        fontSize: 14,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _FeatureRow extends StatelessWidget {
  final IconData icon;
  final String label;
  const _FeatureRow(this.icon, this.label);

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 18, color: AppColors.primary),
        const SizedBox(width: 10),
        Text(
          label,
          style: TextStyle(
            fontSize: 13,
            color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.8),
          ),
        ),
      ],
    );
  }
}

class _LangChip extends StatelessWidget {
  final String label;
  final String value;
  final bool selected;
  final VoidCallback onTap;

  const _LangChip({
    required this.label,
    required this.value,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: selected
                ? AppColors.primary
                : AppColors.primary.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: selected
                  ? AppColors.primary
                  : AppColors.primary.withValues(alpha: 0.2),
            ),
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: selected ? Colors.white : AppColors.primary,
            ),
          ),
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:go_router/go_router.dart';
import 'package:tutorial_coach_mark/tutorial_coach_mark.dart';
import '../../../core/theme/app_theme.dart';
import 'guided_tour_provider.dart';

/// Describes a single step in a screen's tour.
class TourStep {
  final GlobalKey key;
  final String title;
  final String description;
  final String ttsText;
  final ContentAlign align;
  final ShapeLightFocus shape;

  const TourStep({
    required this.key,
    required this.title,
    required this.description,
    required this.ttsText,
    this.align = ContentAlign.bottom,
    this.shape = ShapeLightFocus.RRect,
  });
}

/// Central service that creates and shows [TutorialCoachMark] with TTS narration.
class TourService {
  TourService._();

  static final FlutterTts _tts = FlutterTts();
  static String _currentTtsLang = '';

  static Future<void> _initTts(String langCode) async {
    final locale = _langToLocale(langCode);
    if (_currentTtsLang == locale) return;
    _currentTtsLang = locale;
    await _tts.setLanguage(locale);
    await _tts.setSpeechRate(0.45);
    await _tts.setVolume(1.0);
    await _tts.setPitch(1.0);
  }

  static String _langToLocale(String code) {
    switch (code) {
      case 'hi':
        return 'hi-IN';
      case 'mr':
        return 'mr-IN';
      default:
        return 'en-US';
    }
  }

  /// Show the coach mark tour for the given steps.
  /// After all steps finish, advances the tour to the next phase and navigates.
  static Future<void> showTour({
    required BuildContext context,
    required WidgetRef ref,
    required List<TourStep> steps,
    required TourPhase phase,
  }) async {
    final langCode = ref.read(tourLanguageProvider);
    await _initTts(langCode);

    // Filter out steps whose keys are not currently in the widget tree
    final validSteps = steps.where((s) => s.key.currentContext != null).toList();
    if (validSteps.isEmpty) {
      _advancePhase(context, ref);
      return;
    }

    int currentStepIdx = 0;

    final targets = validSteps.map((step) {
      return TargetFocus(
        identify: step.title,
        keyTarget: step.key,
        alignSkip: Alignment.bottomRight,
        enableOverlayTab: true,
        enableTargetTab: true,
        shape: step.shape,
        radius: 12,
        paddingFocus: 8,
        contents: [
          TargetContent(
            align: step.align,
            builder: (context, controller) {
              return _TourStepContent(
                title: step.title,
                description: step.description,
                stepNumber: validSteps.indexOf(step) + 1,
                totalSteps: validSteps.length,
                isLast: validSteps.indexOf(step) == validSteps.length - 1,
              );
            },
          ),
        ],
      );
    }).toList();

    // Speak first step
    _speak(validSteps[0].ttsText);

    TutorialCoachMark(
      targets: targets,
      colorShadow: AppColors.primary,
      opacityShadow: 0.85,
      textSkip: 'SKIP TOUR',
      textStyleSkip: const TextStyle(
        color: Colors.white,
        fontWeight: FontWeight.w600,
        fontSize: 14,
      ),
      paddingFocus: 10,
      onClickTarget: (target) {
        currentStepIdx++;
        if (currentStepIdx < validSteps.length) {
          _speak(validSteps[currentStepIdx].ttsText);
        }
      },
      onClickOverlay: (target) {
        currentStepIdx++;
        if (currentStepIdx < validSteps.length) {
          _speak(validSteps[currentStepIdx].ttsText);
        }
      },
      onFinish: () {
        _tts.stop();
        _advancePhase(context, ref);
      },
      onSkip: () {
        _tts.stop();
        ref.read(guidedTourProvider.notifier).skipTour();
        return true;
      },
    ).show(context: context);
  }

  static void _advancePhase(BuildContext context, WidgetRef ref) {
    final notifier = ref.read(guidedTourProvider.notifier);
    // Peek at the next phase before advancing
    final currentPhase = ref.read(guidedTourProvider).currentPhase;
    final phaseOrder = [
      TourPhase.home,
      TourPhase.profile,
      TourPhase.consultations,
      TourPhase.assistant,
      TourPhase.documents,
      TourPhase.buddy,
      TourPhase.mentalHealth,
      TourPhase.completed,
    ];
    final idx = phaseOrder.indexOf(currentPhase);
    final nextPhase =
        (idx >= 0 && idx < phaseOrder.length - 1) ? phaseOrder[idx + 1] : null;

    if (nextPhase == null || nextPhase == TourPhase.completed) {
      // Last phase — show completion dialog
      _showTourCompleteDialog(context, ref).then((_) {
        final route = notifier.advanceToNextPhase();
        if (route != null && context.mounted) context.go(route);
      });
    } else {
      // Show "Next up" transition dialog
      _showTransitionDialog(context, ref, nextPhase).then((_) {
        final route = notifier.advanceToNextPhase();
        if (route != null && context.mounted) context.go(route);
      });
    }
  }

  /// Transition dialog showing which feature comes next.
  static Future<void> _showTransitionDialog(
      BuildContext context, WidgetRef ref, TourPhase nextPhase) {
    final lang = ref.read(tourLanguageProvider);
    final titles = phaseTitles[lang] ?? phaseTitles['en']!;
    final title = titles[nextPhase] ?? nextPhase.name;
    final icon = phaseIcons[nextPhase] ?? Icons.arrow_forward_rounded;

    final ttsMap = {
      'en': 'Next up, $title',
      'hi': 'अगला, $title',
      'mr': 'पुढील, $title',
    };
    _speak(ttsMap[lang] ?? ttsMap['en']!);

    return showGeneralDialog<void>(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black.withValues(alpha: 0.6),
      transitionDuration: const Duration(milliseconds: 350),
      transitionBuilder: (ctx, anim, _, child) {
        return ScaleTransition(
          scale: CurvedAnimation(parent: anim, curve: Curves.easeOutBack),
          child: FadeTransition(opacity: anim, child: child),
        );
      },
      pageBuilder: (ctx, _, __) {
        return Center(
          child: Material(
            color: Colors.transparent,
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 48),
              padding: const EdgeInsets.all(28),
              decoration: BoxDecoration(
                color: Theme.of(ctx).colorScheme.surface,
                borderRadius: BorderRadius.circular(24),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.primary.withValues(alpha: 0.25),
                    blurRadius: 30,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 64,
                    height: 64,
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.12),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(icon, color: AppColors.primary, size: 32),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    lang == 'hi'
                        ? 'अगला'
                        : lang == 'mr'
                            ? 'पुढील'
                            : 'Next Up',
                    style: TextStyle(
                      color: AppColors.primary,
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    title,
                    style: Theme.of(ctx).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: ElevatedButton.icon(
                      onPressed: () => Navigator.of(ctx).pop(),
                      icon: const Icon(Icons.arrow_forward_rounded, size: 20),
                      label: Text(
                        lang == 'hi'
                            ? 'आगे बढ़ें'
                            : lang == 'mr'
                                ? 'पुढे जा'
                                : 'Continue',
                        style: const TextStyle(
                            fontSize: 15, fontWeight: FontWeight.w600),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  /// Tour complete celebration dialog.
  static Future<void> _showTourCompleteDialog(
      BuildContext context, WidgetRef ref) {
    final lang = ref.read(tourLanguageProvider);
    final ttsMap = {
      'en':
          'Congratulations! You have completed the guided tour. Enjoy using Aarogyan!',
      'hi':
          'बधाई हो! आपने गाइडेड टूर पूरा कर लिया है। आरोग्यन का आनंद लें!',
      'mr':
          'अभिनंदन! तुम्ही मार्गदर्शित टूर पूर्ण केला आहे. आरोग्यनचा आनंद घ्या!',
    };
    _speak(ttsMap[lang] ?? ttsMap['en']!);

    return showGeneralDialog<void>(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black.withValues(alpha: 0.6),
      transitionDuration: const Duration(milliseconds: 350),
      transitionBuilder: (ctx, anim, _, child) {
        return ScaleTransition(
          scale: CurvedAnimation(parent: anim, curve: Curves.easeOutBack),
          child: FadeTransition(opacity: anim, child: child),
        );
      },
      pageBuilder: (ctx, _, __) {
        return Center(
          child: Material(
            color: Colors.transparent,
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 48),
              padding: const EdgeInsets.all(28),
              decoration: BoxDecoration(
                color: Theme.of(ctx).colorScheme.surface,
                borderRadius: BorderRadius.circular(24),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.primary.withValues(alpha: 0.25),
                    blurRadius: 30,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('🎉', style: TextStyle(fontSize: 48)),
                  const SizedBox(height: 16),
                  Text(
                    lang == 'hi'
                        ? 'टूर पूरा हुआ!'
                        : lang == 'mr'
                            ? 'टूर पूर्ण झाला!'
                            : 'Tour Complete!',
                    style: Theme.of(ctx).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 10),
                  Text(
                    lang == 'hi'
                        ? 'आप आरोग्यन की सभी सुविधाओं से परिचित हो गए हैं। अपनी स्वास्थ्य यात्रा का आनंद लें!'
                        : lang == 'mr'
                            ? 'तुम्ही आरोग्यनच्या सर्व वैशिष्ट्यांशी परिचित झालात. तुमच्या आरोग्य प्रवासाचा आनंद घ्या!'
                            : 'You\'re all set! You\'ve explored every feature of Aarogyan. Enjoy your health journey!',
                    style: Theme.of(ctx).textTheme.bodyMedium?.copyWith(
                          height: 1.5,
                        ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: ElevatedButton(
                      onPressed: () => Navigator.of(ctx).pop(),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      child: Text(
                        lang == 'hi'
                            ? 'शुरू करें'
                            : lang == 'mr'
                                ? 'सुरू करा'
                                : 'Let\'s Go!',
                        style: const TextStyle(
                            fontSize: 15, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  static Future<void> _speak(String text) async {
    await _tts.stop();
    await _tts.speak(text);
  }

  static Future<void> stopTts() async {
    await _tts.stop();
  }
}

/// Tour step content widget shown in the coach mark overlay.
class _TourStepContent extends StatelessWidget {
  final String title;
  final String description;
  final int stepNumber;
  final int totalSteps;
  final bool isLast;

  const _TourStepContent({
    required this.title,
    required this.description,
    required this.stepNumber,
    required this.totalSteps,
    required this.isLast,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.15),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  '$stepNumber / $totalSteps',
                  style: const TextStyle(
                    color: AppColors.primary,
                    fontWeight: FontWeight.w600,
                    fontSize: 12,
                  ),
                ),
              ),
              const Spacer(),
              Icon(
                Icons.volume_up_rounded,
                color: AppColors.primary.withValues(alpha: 0.6),
                size: 18,
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            title,
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontWeight: FontWeight.w700,
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            description,
            style: TextStyle(
              color: AppColors.textPrimary.withValues(alpha: 0.7),
              fontSize: 14,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            isLast ? 'Tap to continue to next section →' : 'Tap anywhere to continue',
            style: TextStyle(
              color: AppColors.primary.withValues(alpha: 0.7),
              fontSize: 12,
              fontStyle: FontStyle.italic,
            ),
          ),
        ],
      ),
    );
  }
}

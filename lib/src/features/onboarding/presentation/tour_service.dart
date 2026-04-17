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
  static bool _ttsInitialized = false;

  static Future<void> _initTts() async {
    if (_ttsInitialized) return;
    await _tts.setLanguage('en-US');
    await _tts.setSpeechRate(0.45);
    await _tts.setVolume(1.0);
    await _tts.setPitch(1.0);
    _ttsInitialized = true;
  }

  /// Show the coach mark tour for the given steps.
  /// After all steps finish, advances the tour to the next phase and navigates.
  static Future<void> showTour({
    required BuildContext context,
    required WidgetRef ref,
    required List<TourStep> steps,
    required TourPhase phase,
  }) async {
    await _initTts();

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
    final route = ref.read(guidedTourProvider.notifier).advanceToNextPhase();
    if (route != null && context.mounted) {
      context.go(route);
    }
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

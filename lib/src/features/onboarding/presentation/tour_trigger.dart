import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tutorial_coach_mark/tutorial_coach_mark.dart';
import 'guided_tour_provider.dart';
import 'screen_keys.dart';
import 'tour_service.dart';

/// A zero-size widget that detects when its [phase] becomes the active
/// tour phase and triggers the corresponding screen tour.
///
/// Drop one instance into each screen's widget tree.
class TourTrigger extends ConsumerStatefulWidget {
  final TourPhase phase;

  const TourTrigger({super.key, required this.phase});

  @override
  ConsumerState<TourTrigger> createState() => _TourTriggerState();
}

class _TourTriggerState extends ConsumerState<TourTrigger> {
  bool _triggered = false;

  @override
  Widget build(BuildContext context) {
    final tourState = ref.watch(guidedTourProvider);

    if (!_triggered &&
        tourState.isActive &&
        tourState.currentPhase == widget.phase &&
        tourState.pendingTourStart) {
      _triggered = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          ref.read(guidedTourProvider.notifier).markTourStarted();
          _startTourForPhase(context, ref, widget.phase);
        }
      });
    }

    return const SizedBox.shrink();
  }

  void _startTourForPhase(BuildContext context, WidgetRef ref, TourPhase phase) {
    final steps = _buildStepsForPhase(ref, phase);
    TourService.showTour(
      context: context,
      ref: ref,
      steps: steps,
      phase: phase,
    );
  }

  List<TourStep> _buildStepsForPhase(WidgetRef ref, TourPhase phase) {
    switch (phase) {
      case TourPhase.home:
        return _homeSteps(ref);
      case TourPhase.profile:
        return _profileSteps(ref);
      case TourPhase.consultations:
        return _consultationsSteps(ref);
      case TourPhase.assistant:
        return _assistantSteps(ref);
      case TourPhase.documents:
        return _documentSteps(ref);
      case TourPhase.buddy:
        return _buddySteps(ref);
      case TourPhase.mentalHealth:
        return _mentalHealthSteps(ref);
      default:
        return [];
    }
  }

  // ── Home screen steps ───────────────────────────────────────────────────────
  List<TourStep> _homeSteps(WidgetRef ref) {
    final keys = ref.read(homeScreenKeysProvider);
    final navKeys = ref.read(bottomNavKeysProvider);
    return [
      TourStep(
        key: keys.headerKey,
        title: 'Welcome to Aarogyan!',
        description:
            'This is your health dashboard. From here you can access all features of the app.',
        ttsText:
            'Welcome to Aarogyan! This is your health dashboard. From here you can access all the features of the app.',
        align: ContentAlign.bottom,
      ),
      TourStep(
        key: keys.askAiKey,
        title: 'Ask AI Health Questions',
        description:
            'Tap here to ask any health-related question. The AI uses your health profile to give personalised answers.',
        ttsText:
            'Tap here to ask any health related question. The AI uses your health profile to give personalized answers.',
        align: ContentAlign.bottom,
      ),
      TourStep(
        key: keys.scanDocKey,
        title: 'Scan Medical Documents',
        description:
            'Tap here to scan prescriptions, test reports, or any medical document. The AI will explain it in simple words.',
        ttsText:
            'Tap here to scan prescriptions, test reports, or any medical document. The AI will explain it in simple words.',
        align: ContentAlign.bottom,
      ),
      TourStep(
        key: keys.featureCardsKey,
        title: 'Explore Features',
        description:
            'These cards give you quick access to Consultation Tracker, Document Scanner, and Mental Health Tracker.',
        ttsText:
            'These cards give you quick access to the Consultation Tracker, Document Scanner, and Mental Health Tracker.',
        align: ContentAlign.top,
      ),
      // Bottom nav items
      TourStep(
        key: navKeys[0],
        title: 'Home Tab',
        description: 'This tab brings you back to the home dashboard.',
        ttsText: 'This is the Home tab. It brings you back to the dashboard.',
        align: ContentAlign.top,
        shape: ShapeLightFocus.Circle,
      ),
      TourStep(
        key: navKeys[1],
        title: 'Consultation Tracker',
        description:
            'Track your doctor visits, treatments, and medical sessions here.',
        ttsText:
            'This is the Consultation Tracker. Track your doctor visits, treatments, and medical sessions here.',
        align: ContentAlign.top,
        shape: ShapeLightFocus.Circle,
      ),
      TourStep(
        key: navKeys[2],
        title: 'AI Health Assistant',
        description:
            'Chat with the AI assistant about your health concerns.',
        ttsText:
            'This is the AI Health Assistant. Chat with the AI about your health concerns.',
        align: ContentAlign.top,
        shape: ShapeLightFocus.Circle,
      ),
      TourStep(
        key: navKeys[3],
        title: 'Emotional Buddy (Orbz)',
        description:
            'Your voice-based emotional companion. Speak to Orbz for emotional support and mental health tracking.',
        ttsText:
            'This is Orbz, your Emotional Buddy. Speak to Orbz for emotional support and mental health tracking.',
        align: ContentAlign.top,
        shape: ShapeLightFocus.Circle,
      ),
      TourStep(
        key: navKeys[4],
        title: 'Your Profile',
        description:
            'View and edit your health profile, medical history, and app settings.',
        ttsText:
            'This is your Profile tab. You can view and edit your health profile, medical history, and app settings.',
        align: ContentAlign.top,
        shape: ShapeLightFocus.Circle,
      ),
    ];
  }

  // ── Profile screen steps ────────────────────────────────────────────────────
  List<TourStep> _profileSteps(WidgetRef ref) {
    final keys = ref.read(profileScreenKeysProvider);
    return [
      TourStep(
        key: keys.personalInfoKey,
        title: 'Personal Information',
        description:
            'Fill in your name, date of birth, height, weight, and other details. This helps the AI give better health recommendations.',
        ttsText:
            'Fill in your personal information here. This helps the AI give you better health recommendations.',
        align: ContentAlign.bottom,
      ),
      TourStep(
        key: keys.medicalHistoryKey,
        title: 'Medical History',
        description:
            'Add your chronic conditions, allergies, past surgeries, and family history. The more you share, the more accurate the AI advice.',
        ttsText:
            'Add your medical history here. The more you share, the more accurate and personalized the AI advice will be.',
        align: ContentAlign.bottom,
      ),
      TourStep(
        key: keys.saveButtonKey,
        title: 'Save Your Profile',
        description:
            'After filling in your details, tap this button to save. You can always come back and update it later.',
        ttsText:
            'After filling in your details, tap Save Profile. You can always come back and update it later.',
        align: ContentAlign.top,
      ),
      TourStep(
        key: keys.themeToggleKey,
        title: 'Theme Toggle',
        description:
            'Switch between light and dark mode from this button in the top right.',
        ttsText: 'You can switch between light and dark mode from this button.',
        align: ContentAlign.bottom,
        shape: ShapeLightFocus.Circle,
      ),
    ];
  }

  // ── Consultations screen steps ──────────────────────────────────────────────
  List<TourStep> _consultationsSteps(WidgetRef ref) {
    final keys = ref.read(consultationsScreenKeysProvider);
    return [
      TourStep(
        key: keys.consultationListKey,
        title: 'Your Consultations',
        description:
            'All your medical consultations appear here. Each consultation can have multiple sessions and documents.',
        ttsText:
            'All your medical consultations appear here. Each consultation can have multiple sessions and documents.',
        align: ContentAlign.bottom,
      ),
      TourStep(
        key: keys.newConsultationFabKey,
        title: 'Create New Consultation',
        description:
            'Tap this button to create a new consultation. Give it a name and optional start date to begin tracking.',
        ttsText:
            'Tap this button to create a new consultation. Give it a name and an optional start date to begin tracking.',
        align: ContentAlign.top,
        shape: ShapeLightFocus.Circle,
      ),
    ];
  }

  // ── Assistant screen steps ──────────────────────────────────────────────────
  List<TourStep> _assistantSteps(WidgetRef ref) {
    final keys = ref.read(assistantScreenKeysProvider);
    return [
      TourStep(
        key: keys.chatListKey,
        title: 'AI Health Assistant',
        description:
            'This is where your conversations with the AI health assistant are listed. You can ask about symptoms, medicines, test reports, and more.',
        ttsText:
            'This is the AI Health Assistant. Your conversations are listed here. You can ask about symptoms, medicines, test reports, and more.',
        align: ContentAlign.bottom,
      ),
      TourStep(
        key: keys.newChatFabKey,
        title: 'Start New Conversation',
        description:
            'Tap this button to start a new health conversation. You can type or use voice input to ask your questions.',
        ttsText:
            'Tap this button to start a new conversation. You can type or use voice input to ask your health questions.',
        align: ContentAlign.top,
        shape: ShapeLightFocus.Circle,
      ),
    ];
  }

  // ── Document screen steps ───────────────────────────────────────────────────
  List<TourStep> _documentSteps(WidgetRef ref) {
    final keys = ref.read(documentScreenKeysProvider);
    return [
      TourStep(
        key: keys.descriptionKey,
        title: 'Document Scanner',
        description:
            'Upload or photograph any medical document — prescriptions, blood test reports, discharge summaries. The AI will read and explain it in simple language.',
        ttsText:
            'This is the Document Scanner. Upload or photograph any medical document. The AI will read and explain it in simple language.',
        align: ContentAlign.bottom,
      ),
      TourStep(
        key: keys.cameraButtonKey,
        title: 'Camera Scan',
        description:
            'Use your phone camera to take a photo of a medical document for instant analysis.',
        ttsText:
            'Use the camera button to take a photo of a medical document for instant analysis.',
        align: ContentAlign.top,
      ),
      TourStep(
        key: keys.uploadButtonKey,
        title: 'Upload File',
        description:
            'Or upload a file from your phone. Supports PDF, JPG, and PNG formats up to 1.5 MB.',
        ttsText:
            'Or tap here to upload a file from your phone. Supports PDF, JPG, and PNG formats up to 1.5 megabytes.',
        align: ContentAlign.top,
      ),
    ];
  }

  // ── Buddy screen steps ──────────────────────────────────────────────────────
  List<TourStep> _buddySteps(WidgetRef ref) {
    final keys = ref.read(buddyScreenKeysProvider);
    return [
      TourStep(
        key: keys.orbKey,
        title: 'Meet Orbz',
        description:
            'This is Orbz, your emotional companion. The orb animates based on the conversation state — idle, listening, thinking, or speaking.',
        ttsText:
            'Meet Orbz, your emotional companion. The orb animates based on whether it is idle, listening, thinking, or speaking.',
        align: ContentAlign.bottom,
      ),
      TourStep(
        key: keys.startButtonKey,
        title: 'Start a Conversation',
        description:
            'Tap this button to begin. Just speak naturally — Orbz listens, understands, and responds with voice. Pause for a few seconds to send your message.',
        ttsText:
            'Tap this button to begin a conversation. Just speak naturally. Orbz listens, understands, and responds with voice. Pause for a few seconds to send your message.',
        align: ContentAlign.top,
      ),
      TourStep(
        key: keys.voiceSelectKey,
        title: 'Choose a Voice',
        description:
            'Tap here to choose a different voice for Orbz. You can preview each voice before selecting.',
        ttsText:
            'Tap here to choose a different voice for Orbz. You can preview each voice before selecting.',
        align: ContentAlign.bottom,
        shape: ShapeLightFocus.Circle,
      ),
      TourStep(
        key: keys.infoButtonKey,
        title: 'Usage Tips',
        description:
            'Tap this icon anytime to see tips on how to get the best experience with Orbz.',
        ttsText:
            'Tap this icon anytime to see tips on how to get the best experience with Orbz.',
        align: ContentAlign.bottom,
        shape: ShapeLightFocus.Circle,
      ),
    ];
  }

  // ── Mental Health screen steps ──────────────────────────────────────────────
  List<TourStep> _mentalHealthSteps(WidgetRef ref) {
    final keys = ref.read(mentalHealthScreenKeysProvider);
    return [
      TourStep(
        key: keys.bodyKey,
        title: 'Mental Health Tracker',
        description:
            'This screen shows your mood trends, emotion breakdown, session history, and a mood calendar — all powered by your conversations with Orbz.',
        ttsText:
            'This is the Mental Health Tracker. It shows your mood trends, emotion breakdown, and session history. All data comes from your conversations with Orbz.',
        align: ContentAlign.bottom,
      ),
      TourStep(
        key: keys.statsKey,
        title: 'Session Statistics',
        description:
            'See your total sessions and average mood score at a glance. Talk to Orbz regularly to build meaningful insights.',
        ttsText:
            'Here you can see your total sessions and average mood score. Talk to Orbz regularly to build meaningful insights.',
        align: ContentAlign.bottom,
      ),
    ];
  }
}

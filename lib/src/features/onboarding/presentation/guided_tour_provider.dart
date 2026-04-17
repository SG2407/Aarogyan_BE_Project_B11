import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/onboarding_repository.dart';

enum TourPhase {
  none,
  home,
  profile,
  consultations,
  assistant,
  documents,
  buddy,
  mentalHealth,
  completed,
}

/// Display names for each phase (used in the transition dialog).
const phaseTitles = {
  'en': {
    TourPhase.home: 'Home Dashboard',
    TourPhase.profile: 'Your Profile',
    TourPhase.consultations: 'Consultation Tracker',
    TourPhase.assistant: 'AI Health Assistant',
    TourPhase.documents: 'Document Scanner',
    TourPhase.buddy: 'Emotional Buddy (Orbz)',
    TourPhase.mentalHealth: 'Mental Health Tracker',
  },
  'hi': {
    TourPhase.home: 'होम डैशबोर्ड',
    TourPhase.profile: 'आपकी प्रोफ़ाइल',
    TourPhase.consultations: 'परामर्श ट्रैकर',
    TourPhase.assistant: 'AI स्वास्थ्य सहायक',
    TourPhase.documents: 'दस्तावेज़ स्कैनर',
    TourPhase.buddy: 'इमोशनल बडी (ऑर्ब्ज़)',
    TourPhase.mentalHealth: 'मानसिक स्वास्थ्य ट्रैकर',
  },
  'mr': {
    TourPhase.home: 'होम डॅशबोर्ड',
    TourPhase.profile: 'तुमचे प्रोफाइल',
    TourPhase.consultations: 'सल्लामसलत ट्रॅकर',
    TourPhase.assistant: 'AI आरोग्य सहाय्यक',
    TourPhase.documents: 'दस्तऐवज स्कॅनर',
    TourPhase.buddy: 'इमोशनल बडी (ऑर्ब्ज)',
    TourPhase.mentalHealth: 'मानसिक आरोग्य ट्रॅकर',
  },
};

/// Icons for each phase.
const phaseIcons = {
  TourPhase.home: Icons.home_rounded,
  TourPhase.profile: Icons.person_rounded,
  TourPhase.consultations: Icons.folder_special_rounded,
  TourPhase.assistant: Icons.chat_bubble_rounded,
  TourPhase.documents: Icons.document_scanner_rounded,
  TourPhase.buddy: Icons.favorite_rounded,
  TourPhase.mentalHealth: Icons.bar_chart_rounded,
};

/// Selected language for tour voice narration.
/// Values: 'en', 'hi', 'mr'
final tourLanguageProvider = StateProvider<String>((ref) => 'en');

class GuidedTourState {
  final bool isActive;
  final TourPhase currentPhase;
  /// Set to true when phase changes; screen sets it false after starting its tour.
  final bool pendingTourStart;

  const GuidedTourState({
    this.isActive = false,
    this.currentPhase = TourPhase.none,
    this.pendingTourStart = false,
  });

  GuidedTourState copyWith({
    bool? isActive,
    TourPhase? currentPhase,
    bool? pendingTourStart,
  }) {
    return GuidedTourState(
      isActive: isActive ?? this.isActive,
      currentPhase: currentPhase ?? this.currentPhase,
      pendingTourStart: pendingTourStart ?? this.pendingTourStart,
    );
  }
}

class GuidedTourNotifier extends Notifier<GuidedTourState> {
  @override
  GuidedTourState build() => const GuidedTourState();

  static const _phaseOrder = [
    TourPhase.home,
    TourPhase.profile,
    TourPhase.consultations,
    TourPhase.assistant,
    TourPhase.documents,
    TourPhase.buddy,
    TourPhase.mentalHealth,
    TourPhase.completed,
  ];

  static const _phaseRoutes = {
    TourPhase.home: '/home',
    TourPhase.profile: '/profile',
    TourPhase.consultations: '/consultations',
    TourPhase.assistant: '/assistant',
    TourPhase.documents: '/documents',
    TourPhase.buddy: '/buddy',
    TourPhase.mentalHealth: '/mental-health',
  };

  /// Start the guided tour from the home screen.
  void startTour() {
    // Reset completed flag so the tour can run again if restarted manually.
    ref.read(onboardingRepositoryProvider).setTourCompleted(false);
    state = const GuidedTourState(
      isActive: true,
      currentPhase: TourPhase.home,
      pendingTourStart: true,
    );
  }

  /// Mark that the current phase's tour has started (prevent double trigger).
  void markTourStarted() {
    state = state.copyWith(pendingTourStart: false);
  }

  /// Advance to the next tour phase. Returns the route to navigate to, or null if completed.
  String? advanceToNextPhase() {
    final currentIdx = _phaseOrder.indexOf(state.currentPhase);
    if (currentIdx < 0 || currentIdx >= _phaseOrder.length - 1) {
      _completeTour();
      return null;
    }
    final nextPhase = _phaseOrder[currentIdx + 1];
    if (nextPhase == TourPhase.completed) {
      _completeTour();
      return '/home';
    }
    state = GuidedTourState(
      isActive: true,
      currentPhase: nextPhase,
      pendingTourStart: true,
    );
    return _phaseRoutes[nextPhase];
  }

  void _completeTour() {
    ref.read(onboardingRepositoryProvider).setTourCompleted();
    state = const GuidedTourState(
      isActive: false,
      currentPhase: TourPhase.completed,
      pendingTourStart: false,
    );
  }

  /// End the tour early (user skips).
  void skipTour() {
    ref.read(onboardingRepositoryProvider).setTourCompleted();
    state = const GuidedTourState();
  }
}

final guidedTourProvider =
    NotifierProvider<GuidedTourNotifier, GuidedTourState>(
        GuidedTourNotifier.new);

// ── Bottom nav GlobalKeys (shared between MainShell and HomeScreen tour) ──
final bottomNavKeysProvider = Provider<List<GlobalKey>>((ref) {
  return List.generate(5, (_) => GlobalKey());
});

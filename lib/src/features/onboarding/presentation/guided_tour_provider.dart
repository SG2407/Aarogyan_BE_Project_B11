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

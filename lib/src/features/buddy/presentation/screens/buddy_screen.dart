import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:record/record.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../../../core/theme/app_theme.dart';
import '../../data/buddy_repository.dart';

// ─── State ────────────────────────────────────────────────────────────────────
enum BuddyPhase { idle, listening, processing, playing }

class ConversationTurn {
  final String role; // 'user' | 'assistant'
  final String content;
  const ConversationTurn({required this.role, required this.content});
  Map<String, String> toMap() => {'role': role, 'content': content};
}

class BuddyStateData {
  final BuddyPhase phase;
  final bool conversationActive;
  final String? lastUserText;
  final String? lastReply;
  final List<ConversationTurn> history;
  final String? error;

  const BuddyStateData({
    this.phase = BuddyPhase.idle,
    this.conversationActive = false,
    this.lastUserText,
    this.lastReply,
    this.history = const [],
    this.error,
  });

  BuddyStateData copyWith({
    BuddyPhase? phase,
    bool? conversationActive,
    String? lastUserText,
    String? lastReply,
    List<ConversationTurn>? history,
    String? error,
  }) {
    return BuddyStateData(
      phase: phase ?? this.phase,
      conversationActive: conversationActive ?? this.conversationActive,
      lastUserText: lastUserText ?? this.lastUserText,
      lastReply: lastReply ?? this.lastReply,
      history: history ?? this.history,
      error: error,
    );
  }
}

// ─── Notifier ─────────────────────────────────────────────────────────────────
class BuddyNotifier extends AutoDisposeNotifier<BuddyStateData> {
  final _recorder = AudioRecorder();
  final _player = AudioPlayer();
  String? _recordingPath;

  @override
  BuddyStateData build() {
    ref.onDispose(() {
      _recorder.dispose();
      _player.dispose();
    });
    return const BuddyStateData();
  }

  /// "Start Conversation" — activates the UI, ready for first input
  Future<void> startConversation() async {
    state = state.copyWith(conversationActive: true, history: [], error: null);
  }

  /// "Start Talking" — user taps mic button, begin recording
  Future<void> startTalking() async {
    if (!await _recorder.hasPermission()) {
      state = state.copyWith(
        phase: BuddyPhase.idle,
        error: 'Microphone permission denied',
      );
      return;
    }

    final dir = await getTemporaryDirectory();
    _recordingPath =
        '${dir.path}/buddy_${DateTime.now().millisecondsSinceEpoch}.m4a';

    await _recorder.start(
      const RecordConfig(encoder: AudioEncoder.aacLc),
      path: _recordingPath!,
    );

    state = state.copyWith(phase: BuddyPhase.listening, error: null);
  }

  /// "Stop Talking" — user taps stop button, send audio to backend
  Future<void> stopTalking() async {
    final path = await _recorder.stop();
    if (path == null) return;

    state = state.copyWith(phase: BuddyPhase.processing);

    try {
      final repo = ref.read(buddyRepositoryProvider);
      final historyMaps = state.history.map((t) => t.toMap()).toList();
      final result = await repo.sendVoice(path, historyMaps);

      final userText = result['user_text'] as String? ?? '';
      final reply = result['buddy_text'] as String? ?? '';
      final audioBase64 = result['audio_base64'] as String?;

      final newHistory = [
        ...state.history,
        ConversationTurn(role: 'user', content: userText),
        ConversationTurn(role: 'assistant', content: reply),
      ];
      final trimmed = newHistory.length > 10
          ? newHistory.sublist(newHistory.length - 10)
          : newHistory;

      state = state.copyWith(
        phase: BuddyPhase.playing,
        lastUserText: userText,
        lastReply: reply,
        history: trimmed,
        error: null,
      );

      if (audioBase64 != null && audioBase64.isNotEmpty) {
        await _playBase64Audio(audioBase64);
      }

      if (state.conversationActive && state.phase == BuddyPhase.playing) {
        state = state.copyWith(phase: BuddyPhase.idle);
      }
    } catch (e) {
      String msg = 'Something went wrong — please try again.';
      if (e is DioException) {
        final status = e.response?.statusCode;
        final detail = e.response?.data is Map
            ? (e.response!.data as Map)['detail'] ?? e.message
            : e.message;
        msg = 'Error $status: $detail';
      }
      state = state.copyWith(
        phase: BuddyPhase.idle,
        error: msg,
      );
    } finally {
      try {
        final f = File(path);
        if (await f.exists()) await f.delete();
      } catch (_) {}
    }
  }

  Future<void> _playBase64Audio(String base64Audio) async {
    final bytes = base64Decode(base64Audio);
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/buddy_response.mp3');
    await file.writeAsBytes(bytes);
    await _player.setFilePath(file.path);
    await _player.play();
    await _player.playerStateStream.firstWhere(
      (s) =>
          s.processingState == ProcessingState.completed ||
          s.processingState == ProcessingState.idle,
    );
  }

  /// Interrupt AI mid-speech → return to idle
  Future<void> interrupt() async {
    await _player.stop();
    state = state.copyWith(phase: BuddyPhase.idle);
  }

  Future<void> endConversation() async {
    await _recorder.cancel();
    await _player.stop();
    state = const BuddyStateData();
  }
}

final buddyNotifierProvider =
    AutoDisposeNotifierProvider<BuddyNotifier, BuddyStateData>(
        BuddyNotifier.new);

// ─── Screen ───────────────────────────────────────────────────────────────────
class BuddyScreen extends ConsumerWidget {
  const BuddyScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(buddyNotifierProvider);
    final notifier = ref.read(buddyNotifierProvider.notifier);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Orbz — Emotional Buddy'),
        actions: [
          if (s.conversationActive)
            TextButton(
              onPressed: notifier.endConversation,
              child: const Text('End'),
            ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          child: Column(
            children: [
              const Spacer(),
              _OrbzAvatar(phase: s.phase),
              const SizedBox(height: 28),
              _PhaseLabel(
                  phase: s.phase, conversationActive: s.conversationActive),
              const SizedBox(height: 20),
              if (s.error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(
                    s.error!,
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(color: AppColors.error),
                    textAlign: TextAlign.center,
                  ),
                ),
              const Spacer(),
              _BottomControls(
                phase: s.phase,
                conversationActive: s.conversationActive,
                onStart: notifier.startConversation,
                onStartTalking: notifier.startTalking,
                onStopTalking: notifier.stopTalking,
                onInterrupt: notifier.interrupt,
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Orbz Avatar ──────────────────────────────────────────────────────────────
class _OrbzAvatar extends StatelessWidget {
  final BuddyPhase phase;
  const _OrbzAvatar({required this.phase});

  @override
  Widget build(BuildContext context) {
    final isListening = phase == BuddyPhase.listening;
    final isPlaying = phase == BuddyPhase.playing;
    final isProcessing = phase == BuddyPhase.processing;

    Color bgColor = Theme.of(context).colorScheme.secondary;
    if (isListening) bgColor = AppColors.primary;
    if (isPlaying) bgColor = AppColors.accent;
    if (isProcessing) bgColor = AppColors.primary.withValues(alpha: 0.55);

    return AnimatedContainer(
      duration: const Duration(milliseconds: 400),
      width: (isListening || isPlaying) ? 160 : 140,
      height: (isListening || isPlaying) ? 160 : 140,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: bgColor,
        boxShadow: (isListening || isPlaying)
            ? [
                BoxShadow(
                  color: bgColor.withValues(alpha: 0.45),
                  blurRadius: 48,
                  spreadRadius: 12,
                ),
              ]
            : [],
      ),
      child: Center(
        child: isProcessing
            ? const CircularProgressIndicator(
                color: Colors.white, strokeWidth: 3)
            : const Text(
                'O',
                style: TextStyle(
                  fontSize: 72,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
      ),
    )
        .animate(
          onPlay: (c) =>
              (isListening || isPlaying) ? c.repeat(reverse: true) : c.stop(),
        )
        .scaleXY(
          duration: 800.ms,
          begin: 1.0,
          end: (isListening || isPlaying) ? 1.07 : 1.0,
        );
  }
}

// ─── Phase label ──────────────────────────────────────────────────────────────
class _PhaseLabel extends StatelessWidget {
  final BuddyPhase phase;
  final bool conversationActive;
  const _PhaseLabel({required this.phase, required this.conversationActive});

  String _label() {
    if (!conversationActive) return 'Tap below to start talking with Orbz';
    switch (phase) {
      case BuddyPhase.idle:
        return 'Tap below to start talking with Orbz';
      case BuddyPhase.listening:
        return 'Listening...';
      case BuddyPhase.processing:
        return 'Orbz is thinking...';
      case BuddyPhase.playing:
        return 'Orbz is speaking...';
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 300),
      child: Text(
        _label(),
        key: ValueKey(_label()),
        style: Theme.of(context)
            .textTheme
            .headlineSmall
            ?.copyWith(color: AppColors.primary),
        textAlign: TextAlign.center,
      ),
    );
  }
}

// ─── Bottom controls ──────────────────────────────────────────────────────────
class _BottomControls extends StatelessWidget {
  final BuddyPhase phase;
  final bool conversationActive;
  final VoidCallback onStart;
  final VoidCallback onStartTalking;
  final VoidCallback onStopTalking;
  final VoidCallback onInterrupt;

  const _BottomControls({
    required this.phase,
    required this.conversationActive,
    required this.onStart,
    required this.onStartTalking,
    required this.onStopTalking,
    required this.onInterrupt,
  });

  @override
  Widget build(BuildContext context) {
    // ── Not started yet ──
    if (!conversationActive) {
      return Column(
        children: [
          ElevatedButton.icon(
            onPressed: onStart,
            icon: const Icon(Icons.favorite_rounded),
            label: const Text('Start Conversation'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(32)),
              textStyle:
                  const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'Start a conversation with your emotional buddy',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context)
                      .colorScheme
                      .onSurface
                      .withValues(alpha: 0.5),
                ),
            textAlign: TextAlign.center,
          ),
        ],
      );
    }

    // ── Idle — show Start Talking button ──
    if (phase == BuddyPhase.idle) {
      return Column(
        children: [
          GestureDetector(
            onTap: onStartTalking,
            child: Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.1),
                shape: BoxShape.circle,
                border: Border.all(color: AppColors.primary, width: 2),
              ),
              child: const Icon(Icons.mic_rounded,
                  color: AppColors.primary, size: 30),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'Tap to start talking',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context)
                      .colorScheme
                      .onSurface
                      .withValues(alpha: 0.5),
                ),
          ),
        ],
      );
    }

    // ── Listening — show Stop Talking button ──
    if (phase == BuddyPhase.listening) {
      return Column(
        children: [
          GestureDetector(
            onTap: onStopTalking,
            child: Container(
              width: 72,
              height: 72,
              decoration: const BoxDecoration(
                color: Color(0xFFE53935),
                shape: BoxShape.circle,
              ),
              child:
                  const Icon(Icons.stop_rounded, color: Colors.white, size: 30),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'Tap to stop and send',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context)
                      .colorScheme
                      .onSurface
                      .withValues(alpha: 0.5),
                ),
          ),
        ],
      );
    }

    // ── AI is speaking — show Interrupt button ──
    if (phase == BuddyPhase.playing) {
      return Column(
        children: [
          GestureDetector(
            onTap: onInterrupt,
            child: Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: AppColors.error.withValues(alpha: 0.1),
                shape: BoxShape.circle,
                border: Border.all(color: AppColors.error, width: 2),
              ),
              child: const Icon(Icons.mic_rounded,
                  color: AppColors.error, size: 30),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'Tap to interrupt and speak',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context)
                      .colorScheme
                      .onSurface
                      .withValues(alpha: 0.5),
                ),
          ),
        ],
      );
    }

    // ── Processing — spinner hint, no button ──
    return Text(
      'Processing your message...',
      style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color:
                Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5),
          ),
      textAlign: TextAlign.center,
    );
  }
}

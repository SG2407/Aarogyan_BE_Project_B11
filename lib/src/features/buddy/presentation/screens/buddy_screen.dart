import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:record/record.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../../../core/theme/app_theme.dart';
import '../../data/buddy_repository.dart';

// --- State ---
enum BuddyState { idle, recording, processing, playing }

class BuddyStateData {
  final BuddyState state;
  final String? lastReply;
  final double? moodScore;
  final String? error;

  const BuddyStateData({
    this.state = BuddyState.idle,
    this.lastReply,
    this.moodScore,
    this.error,
  });

  BuddyStateData copyWith({
    BuddyState? state,
    String? lastReply,
    double? moodScore,
    String? error,
  }) {
    return BuddyStateData(
      state: state ?? this.state,
      lastReply: lastReply ?? this.lastReply,
      moodScore: moodScore ?? this.moodScore,
      error: error,
    );
  }
}

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

  Future<void> startRecording() async {
    if (!await _recorder.hasPermission()) {
      state = state.copyWith(
          state: BuddyState.idle, error: 'Microphone permission denied');
      return;
    }
    final dir = await getTemporaryDirectory();
    _recordingPath =
        '${dir.path}/orbz_${DateTime.now().millisecondsSinceEpoch}.m4a';
    await _recorder.start(
      const RecordConfig(encoder: AudioEncoder.aacLc),
      path: _recordingPath!,
    );
    state = state.copyWith(state: BuddyState.recording, error: null);
  }

  Future<void> stopRecordingAndSend() async {
    final path = await _recorder.stop();
    if (path == null) return;
    state = state.copyWith(state: BuddyState.processing);
    try {
      final repo = ref.read(buddyRepositoryProvider);
      final result = await repo.sendVoice(path);

      final reply = result['reply'] as String? ?? '';
      final moodScore = (result['mood_score'] as num?)?.toDouble() ?? 5.0;
      final audioBase64 = result['audio_base64'] as String?;

      state = state.copyWith(
        state: BuddyState.playing,
        lastReply: reply,
        moodScore: moodScore,
      );

      if (audioBase64 != null && audioBase64.isNotEmpty) {
        await _playBase64Audio(audioBase64);
      }
      state = state.copyWith(state: BuddyState.idle);
    } catch (e) {
      state = state.copyWith(
        state: BuddyState.idle,
        error: 'Something went wrong. Please try again.',
      );
    } finally {
      // Clean up temp recording file
      try {
        final f = File(path);
        if (await f.exists()) await f.delete();
      } catch (_) {}
    }
  }

  Future<void> _playBase64Audio(String base64Audio) async {
    final bytes = base64Decode(base64Audio);
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/orbz_response.mp3');
    await file.writeAsBytes(bytes);
    await _player.setFilePath(file.path);
    await _player.play();
    await _player.playerStateStream.firstWhere(
      (s) => s.processingState == ProcessingState.completed,
    );
  }

  void cancelRecording() async {
    await _recorder.cancel();
    state = state.copyWith(state: BuddyState.idle);
  }
}

final buddyNotifierProvider =
    AutoDisposeNotifierProvider<BuddyNotifier, BuddyStateData>(
        BuddyNotifier.new);

// --- UI ---
class BuddyScreen extends ConsumerWidget {
  const BuddyScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final buddyState = ref.watch(buddyNotifierProvider);
    final notifier = ref.read(buddyNotifierProvider.notifier);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('Orbz — Emotional Buddy')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              const Spacer(),

              // Orbz animated avatar
              _OrbzAvatar(state: buddyState.state),
              const SizedBox(height: 32),

              // State label
              _StateLabel(state: buddyState.state),
              const SizedBox(height: 16),

              // Mood score if available
              if (buddyState.moodScore != null) ...[
                _MoodBar(score: buddyState.moodScore!),
                const SizedBox(height: 16),
              ],

              // Last reply bubble
              if (buddyState.lastReply != null &&
                  buddyState.lastReply!.isNotEmpty) ...[
                _ReplyBubble(text: buddyState.lastReply!),
                const SizedBox(height: 16),
              ],

              // Error
              if (buddyState.error != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: Text(buddyState.error!,
                      style: Theme.of(context)
                          .textTheme
                          .bodyMedium
                          ?.copyWith(color: AppColors.error),
                      textAlign: TextAlign.center),
                ),

              const Spacer(),

              // Action button
              _ActionButton(
                state: buddyState.state,
                onPressStart: notifier.startRecording,
                onPressStop: notifier.stopRecordingAndSend,
                onCancel: notifier.cancelRecording,
              ),

              const SizedBox(height: 24),

              Text(
                'Hold the button and speak. Orbz is here to listen.',
                style: Theme.of(context)
                    .textTheme
                    .bodyMedium
                    ?.copyWith(color: AppColors.textSecondary),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _OrbzAvatar extends StatelessWidget {
  final BuddyState state;
  const _OrbzAvatar({required this.state});

  @override
  Widget build(BuildContext context) {
    final isActive =
        state == BuddyState.recording || state == BuddyState.processing;
    final isPlaying = state == BuddyState.playing;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 400),
      width: isActive ? 160 : 140,
      height: isActive ? 160 : 140,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: isActive ? AppColors.primary : AppColors.secondary,
        boxShadow: isActive
            ? [
                BoxShadow(
                  color: AppColors.primary.withValues(alpha: 0.4),
                  blurRadius: 40,
                  spreadRadius: 10,
                ),
              ]
            : isPlaying
                ? [
                    BoxShadow(
                      color: AppColors.accent.withValues(alpha: 0.4),
                      blurRadius: 40,
                      spreadRadius: 10,
                    ),
                  ]
                : [],
      ),
      child: Center(
        child: Text(
          'O',
          style: TextStyle(
            fontSize: 72,
            fontWeight: FontWeight.w700,
            color: isActive ? Colors.white : AppColors.primary,
          ),
        ),
      ),
    )
        .animate(
          onPlay: (controller) =>
              isActive ? controller.repeat(reverse: true) : controller.stop(),
        )
        .scaleXY(
          duration: 800.ms,
          begin: 1.0,
          end: isActive ? 1.08 : 1.0,
        );
  }
}

class _StateLabel extends StatelessWidget {
  final BuddyState state;
  const _StateLabel({required this.state});

  String _label() {
    switch (state) {
      case BuddyState.idle:
        return 'Tap to talk to Orbz';
      case BuddyState.recording:
        return 'Listening...';
      case BuddyState.processing:
        return 'Orbz is thinking...';
      case BuddyState.playing:
        return 'Orbz is speaking...';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Text(
      _label(),
      style: Theme.of(context)
          .textTheme
          .headlineSmall
          ?.copyWith(color: AppColors.primary),
      textAlign: TextAlign.center,
    );
  }
}

class _MoodBar extends StatelessWidget {
  final double score; // 1–10
  const _MoodBar({required this.score});

  String _moodLabel() {
    if (score >= 8) return 'Great mood 😄';
    if (score >= 6) return 'Good mood 🙂';
    if (score >= 4) return 'Neutral 😐';
    if (score >= 2) return 'Low mood 😔';
    return 'Very low mood 😢';
  }

  Color _moodColor() {
    if (score >= 8) return const Color(0xFF4CAF50);
    if (score >= 6) return const Color(0xFF8BC34A);
    if (score >= 4) return const Color(0xFFFFC107);
    if (score >= 2) return const Color(0xFFFF9800);
    return AppColors.error;
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('Mood', style: Theme.of(context).textTheme.bodyMedium),
            Text(_moodLabel(),
                style: Theme.of(context)
                    .textTheme
                    .bodyMedium
                    ?.copyWith(color: _moodColor())),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: LinearProgressIndicator(
            value: (score - 1) / 9,
            minHeight: 8,
            backgroundColor: AppColors.secondary,
            valueColor: AlwaysStoppedAnimation<Color>(_moodColor()),
          ),
        ),
      ],
    );
  }
}

class _ReplyBubble extends StatelessWidget {
  final String text;
  const _ReplyBubble({required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        text,
        style: Theme.of(context).textTheme.bodyLarge,
        textAlign: TextAlign.center,
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  final BuddyState state;
  final VoidCallback onPressStart;
  final VoidCallback onPressStop;
  final VoidCallback onCancel;

  const _ActionButton({
    required this.state,
    required this.onPressStart,
    required this.onPressStop,
    required this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    if (state == BuddyState.idle || state == BuddyState.playing) {
      return GestureDetector(
        onTap: onPressStart,
        child: Container(
          width: 80,
          height: 80,
          decoration: const BoxDecoration(
            color: AppColors.primary,
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.mic_rounded, color: Colors.white, size: 36),
        ),
      );
    }

    if (state == BuddyState.recording) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          GestureDetector(
            onTap: onCancel,
            child: Container(
              width: 60,
              height: 60,
              decoration: BoxDecoration(
                color: AppColors.error.withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.close_rounded,
                  color: AppColors.error, size: 28),
            ),
          ),
          const SizedBox(width: 20),
          GestureDetector(
            onTap: onPressStop,
            child: Container(
              width: 80,
              height: 80,
              decoration: const BoxDecoration(
                color: AppColors.primary,
                shape: BoxShape.circle,
              ),
              child:
                  const Icon(Icons.stop_rounded, color: Colors.white, size: 36),
            ),
          ),
        ],
      );
    }

    // Processing
    return Container(
      width: 80,
      height: 80,
      decoration: const BoxDecoration(
        color: AppColors.secondary,
        shape: BoxShape.circle,
      ),
      child: const Padding(
        padding: EdgeInsets.all(20),
        child: CircularProgressIndicator(
          strokeWidth: 3,
          color: AppColors.primary,
        ),
      ),
    );
  }
}

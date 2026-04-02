import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vad/vad.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';
import '../../../../core/l10n/app_strings.dart';
import '../../../../core/theme/app_theme.dart';
import '../../data/buddy_repository.dart';
import '../../../profile/data/profile_repository.dart';
import '../widgets/orb_widget.dart';

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
  final double soundLevel; // 0.0–1.0, driven by mic input while listening
  final String? sessionGroupId;
  final Map<String, dynamic>? sessionSummary;

  const BuddyStateData({
    this.phase = BuddyPhase.idle,
    this.conversationActive = false,
    this.lastUserText,
    this.lastReply,
    this.history = const [],
    this.error,
    this.soundLevel = 0.0,
    this.sessionGroupId,
    this.sessionSummary,
  });

  BuddyStateData copyWith({
    BuddyPhase? phase,
    bool? conversationActive,
    String? lastUserText,
    String? lastReply,
    List<ConversationTurn>? history,
    String? error,
    double? soundLevel,
    String? sessionGroupId,
    Map<String, dynamic>? sessionSummary,
  }) {
    return BuddyStateData(
      phase: phase ?? this.phase,
      conversationActive: conversationActive ?? this.conversationActive,
      lastUserText: lastUserText ?? this.lastUserText,
      lastReply: lastReply ?? this.lastReply,
      history: history ?? this.history,
      error: error,
      soundLevel: soundLevel ?? this.soundLevel,
      sessionGroupId: sessionGroupId ?? this.sessionGroupId,
      sessionSummary: sessionSummary,
    );
  }
}

// ─── Notifier ─────────────────────────────────────────────────────────────────

/// Convert PCM float samples (–1.0 … 1.0, 16 kHz mono) to a valid WAV file.
Uint8List _samplesToWav(List<double> samples, {int sampleRate = 16000}) {
  final pcm16 = Int16List(samples.length);
  for (int i = 0; i < samples.length; i++) {
    pcm16[i] = (samples[i] * 32767).clamp(-32768, 32767).toInt();
  }
  final pcmBytes = pcm16.buffer.asUint8List();
  final header = ByteData(44);
  void _ascii(int offset, String s) {
    for (int i = 0; i < s.length; i++) {
      header.setUint8(offset + i, s.codeUnitAt(i));
    }
  }

  _ascii(0, 'RIFF');
  header.setUint32(4, 36 + pcmBytes.length, Endian.little);
  _ascii(8, 'WAVE');
  _ascii(12, 'fmt ');
  header.setUint32(16, 16, Endian.little); // PCM chunk size
  header.setUint16(20, 1, Endian.little); // PCM format
  header.setUint16(22, 1, Endian.little); // mono
  header.setUint32(24, sampleRate, Endian.little);
  header.setUint32(28, sampleRate * 2, Endian.little); // byte rate
  header.setUint16(32, 2, Endian.little); // block align
  header.setUint16(34, 16, Endian.little); // bits per sample
  _ascii(36, 'data');
  header.setUint32(40, pcmBytes.length, Endian.little);

  return Uint8List.fromList([...header.buffer.asUint8List(), ...pcmBytes]);
}

class BuddyNotifier extends AutoDisposeNotifier<BuddyStateData> {
  late final VadHandler _vad;
  final _player = AudioPlayer();

  bool _disposed = false;
  String _preferredLang = 'English';

  /// Guard against overlapping processing cycles
  bool _processing = false;

  /// Audio chunk playback queue (base64-encoded WAV)
  final _audioQueue = <String>[];
  bool _playingQueue = false;

  /// Accumulated speech samples across thinking-pause segments.
  /// If the user pauses briefly (< post-speech wait), segments are merged.
  final _pendingSamples = <double>[];
  Timer? _postSpeechTimer;
  bool _vadListening = false;

  // ── Tuning constants ────────────────────────────────────────────────────────
  // Legacy Silero model: 1 frame ≈ 96 ms
  static const _redemptionFrames = 20; // ~1.92 s silence before onSpeechEnd
  static const _minSpeechFrames = 5; // ~480 ms minimum speech
  static const _postSpeechWaitMs = 1500; // 1.5 s extra wait after onSpeechEnd
  // Total pause tolerance: ~1.92 + 1.5 = ~3.4 s  — handles thinking pauses
  static const _maxPendingSamples = 16000 * 60; // 60 s hard cap

  @override
  BuddyStateData build() {
    _vad = VadHandler.create(isDebug: false);
    _setupVadListeners();

    ref.onDispose(() {
      _disposed = true;
      _postSpeechTimer?.cancel();
      if (_vadListening) _vad.stopListening().catchError((_) {});
      _vad.dispose();
      _player.dispose();
    });
    return const BuddyStateData();
  }

  // ── VAD event wiring ────────────────────────────────────────────────────────

  void _setupVadListeners() {
    // User started making a sound — cancel post-speech timer so we keep
    // accumulating instead of committing prematurely.
    _vad.onSpeechStart.listen((_) {
      if (_disposed || !state.conversationActive || _processing) return;
      _postSpeechTimer?.cancel();
      debugPrint('[Buddy] VAD: speech start (timer cancelled)');
    });

    // Confirmed real speech (past minSpeechFrames) — show "Listening…"
    _vad.onRealSpeechStart.listen((_) {
      if (_disposed || !state.conversationActive || _processing) return;
      debugPrint('[Buddy] VAD: real speech started');
      _set(state.copyWith(phase: BuddyPhase.listening));
    });

    // Speech segment ended — accumulate samples and start post-speech timer.
    _vad.onSpeechEnd.listen((List<double> samples) {
      if (_disposed || !state.conversationActive || _processing) return;
      debugPrint('[Buddy] VAD: speech ended — ${samples.length} samples '
          '(pending total: ${_pendingSamples.length + samples.length})');
      _pendingSamples.addAll(samples);

      // Hard cap: if speech exceeds 60 s, commit immediately
      if (_pendingSamples.length >= _maxPendingSamples) {
        debugPrint('[Buddy] Max pending samples reached — committing');
        _commitSpeech();
        return;
      }
      _startPostSpeechTimer();
    });

    // Misfire (sound too short to be speech). If we have pending samples and
    // the timer was just cancelled by onSpeechStart, restart it so we don't
    // hang indefinitely.
    _vad.onVADMisfire.listen((_) {
      if (_disposed || !state.conversationActive || _processing) return;
      debugPrint('[Buddy] VAD: misfire');
      if (_pendingSamples.isNotEmpty && !(_postSpeechTimer?.isActive ?? false)) {
        _startPostSpeechTimer();
      }
    });

    // Per-frame speech probability → drive orb animation
    _vad.onFrameProcessed.listen((frameData) {
      if (_disposed || !state.conversationActive || _processing) return;
      _set(state.copyWith(soundLevel: frameData.isSpeech.clamp(0.0, 1.0)));
    });

    _vad.onError.listen((String msg) {
      debugPrint('[Buddy] VAD error: $msg');
      if (!_disposed) {
        _set(state.copyWith(
            phase: BuddyPhase.idle, error: 'Voice detection error: $msg'));
      }
    });
  }

  // ── Public API ──────────────────────────────────────────────────────────────

  Future<void> startConversation({String preferredLang = 'English'}) async {
    _preferredLang = preferredLang;
    final groupId = const Uuid().v4();
    _set(state.copyWith(
      conversationActive: true,
      history: [],
      error: null,
      soundLevel: 0.0,
      sessionGroupId: groupId,
    ));
    await _startVadListening();
  }

  Future<void> interrupt() async {
    await _player.stop();
    _audioQueue.clear();
    _playingQueue = false;
    _set(state.copyWith(phase: BuddyPhase.idle, soundLevel: 0.0));
    await _startVadListening();
  }

  Future<void> endConversation() async {
    _postSpeechTimer?.cancel();
    _pendingSamples.clear();
    if (_vadListening) {
      await _vad.stopListening().catchError((_) {});
      _vadListening = false;
    }
    await _player.stop();
    _audioQueue.clear();
    _playingQueue = false;
    _processing = false;
    _set(const BuddyStateData());
  }

  void clearSummary() {
    _set(const BuddyStateData());
  }

  // ── Internal helpers ────────────────────────────────────────────────────────

  void _set(BuddyStateData s) {
    if (!_disposed) state = s;
  }

  /// Start the Silero VAD. The package manages its own AudioRecorder internally.
  Future<void> _startVadListening() async {
    if (_disposed || !state.conversationActive) return;

    _pendingSamples.clear();
    _postSpeechTimer?.cancel();

    _set(state.copyWith(
      phase: BuddyPhase.listening,
      error: null,
      soundLevel: 0.0,
    ));

    try {
      await _vad.startListening(
        redemptionFrames: _redemptionFrames,
        minSpeechFrames: _minSpeechFrames,
        positiveSpeechThreshold: 0.5,
        negativeSpeechThreshold: 0.35,
        preSpeechPadFrames: 3,
        frameSamples: 1536,
        model: 'legacy',
      );
      _vadListening = true;
      debugPrint('[Buddy] VAD listening started');
    } catch (e) {
      debugPrint('[Buddy] VAD startListening failed: $e');
      _set(state.copyWith(
        phase: BuddyPhase.idle,
        error: 'Microphone error — please check permissions.',
      ));
    }
  }

  void _startPostSpeechTimer() {
    _postSpeechTimer?.cancel();
    _postSpeechTimer = Timer(
      const Duration(milliseconds: _postSpeechWaitMs),
      _commitSpeech,
    );
  }

  /// Commit all accumulated speech segments → WAV file → backend.
  Future<void> _commitSpeech() async {
    if (_processing || _disposed || _pendingSamples.isEmpty) return;
    _processing = true;
    _postSpeechTimer?.cancel();

    final sampleCount = _pendingSamples.length;
    debugPrint('[Buddy] Committing speech: $sampleCount samples '
        '(≈${(sampleCount / 16000).toStringAsFixed(1)}s)');

    try {
      // Stop VAD while processing / playing response
      if (_vadListening) {
        await _vad.stopListening().catchError((_) {});
        _vadListening = false;
      }

      // Convert to WAV and save to temp file
      final wavBytes = _samplesToWav(List.of(_pendingSamples));
      _pendingSamples.clear();

      final dir = await getTemporaryDirectory();
      final path =
          '${dir.path}/buddy_vad_${DateTime.now().millisecondsSinceEpoch}.wav';
      await File(path).writeAsBytes(wavBytes);

      debugPrint('[Buddy] WAV file: ${wavBytes.length} bytes → $path');
      _set(state.copyWith(phase: BuddyPhase.processing, soundLevel: 0.0));
      await _processAudio(path);
    } catch (e) {
      debugPrint('[Buddy] commitSpeech error: $e');
      _processing = false;
      _pendingSamples.clear();
      if (!_disposed && state.conversationActive) {
        _set(state.copyWith(
            phase: BuddyPhase.idle, error: 'Processing error.'));
        await Future.delayed(const Duration(seconds: 2));
        await _startVadListening();
      }
    }
  }

  /// Upload audio to /buddy/chat-stream and handle the NDJSON event stream.
  Future<void> _processAudio(String audioPath) async {
    try {
      final repo = ref.read(buddyRepositoryProvider);
      final historyMaps = state.history.map((t) => t.toMap()).toList();

      debugPrint('[Buddy] Uploading audio to chat-stream...');

      String userText = '';
      String fullReply = '';

      await for (final event in repo.streamChat(
        audioPath,
        historyMaps,
        preferredLanguage: _preferredLang,
        sessionGroupId: state.sessionGroupId,
      )) {
        if (_disposed) return;

        final type = event['type'] as String?;

        switch (type) {
          case 'transcript':
            userText = event['text'] as String? ?? '';
            debugPrint('[Buddy] Transcript: "$userText"');
            _set(state.copyWith(
              lastUserText: userText,
              phase: BuddyPhase.processing,
            ));
            break;

          case 'sentence':
            final sentence = event['text'] as String? ?? '';
            fullReply += (fullReply.isEmpty ? '' : ' ') + sentence;
            debugPrint('[Buddy] Sentence ${event['index']}: "$sentence"');
            _set(state.copyWith(
              lastReply: fullReply,
              phase: BuddyPhase.playing,
            ));
            break;

          case 'audio':
            final b64 = event['data'] as String?;
            if (b64 != null && b64.isNotEmpty) {
              _enqueueAudio(b64);
            }
            break;

          case 'done':
            final reply = event['full_reply'] as String? ?? fullReply;
            debugPrint('[Buddy] Stream done. Reply: '
                '"${reply.substring(0, reply.length.clamp(0, 80))}"');
            final newHistory = [
              ...state.history,
              ConversationTurn(role: 'user', content: userText),
              ConversationTurn(role: 'assistant', content: reply),
            ];
            final trimmed = newHistory.length > 20
                ? newHistory.sublist(newHistory.length - 20)
                : newHistory;
            _set(state.copyWith(
              lastReply: reply,
              history: trimmed,
              error: null,
            ));
            break;

          case 'error':
            debugPrint('[Buddy] Stream error: ${event['message']}');
            _set(state.copyWith(
              phase: BuddyPhase.idle,
              error: event['message'] as String? ?? 'Server error',
            ));
            break;
        }
      }

      // Wait for audio queue to finish playing
      await _waitForQueueDone();

      // Auto-loop: restart VAD listening
      if (!_disposed && state.conversationActive) {
        _processing = false;
        await _startVadListening();
        return;
      }
    } catch (e) {
      debugPrint('[Buddy] ERROR in _processAudio: $e');
      if (_disposed) return;
      String msg = 'Something went wrong — please try again.';
      int retryDelay = 2;

      if (e is DioException) {
        final statusCode = e.response?.statusCode;
        if (statusCode == 404 || statusCode == 502 || statusCode == 503) {
          msg = appStr(_preferredLang, 'service_starting');
          retryDelay = 10;
        } else {
          final detail = e.response?.data is Map
              ? (e.response!.data as Map)['detail'] ?? e.message
              : e.message;
          msg = 'Error $statusCode: $detail';
        }
      }

      _set(state.copyWith(phase: BuddyPhase.idle, error: msg));
      await Future.delayed(Duration(seconds: retryDelay));
      if (!_disposed && state.conversationActive) {
        _processing = false;
        await _startVadListening();
        return;
      }
    } finally {
      _processing = false;
    }
  }

  // ── Audio queue playback ────────────────────────────────────────────────────

  void _enqueueAudio(String base64Audio) {
    _audioQueue.add(base64Audio);
    if (!_playingQueue) _playQueue();
  }

  Future<void> _playQueue() async {
    _playingQueue = true;
    while (_audioQueue.isNotEmpty) {
      if (_disposed) break;
      final chunk = _audioQueue.removeAt(0);
      await _playBase64Audio(chunk);
    }
    _playingQueue = false;
  }

  Future<void> _waitForQueueDone() async {
    // Wait until the queue drains and playback finishes
    while (_playingQueue) {
      await Future.delayed(const Duration(milliseconds: 100));
      if (_disposed) return;
    }
  }

  Future<void> _playBase64Audio(String base64Audio) async {
    final bytes = base64Decode(base64Audio);
    final dir = await getTemporaryDirectory();
    final file = File(
        '${dir.path}/buddy_chunk_${DateTime.now().millisecondsSinceEpoch}.wav');
    await file.writeAsBytes(bytes);
    await _player.setFilePath(file.path);
    await _player.play();
    await _player.playerStateStream.firstWhere(
      (s) =>
          s.processingState == ProcessingState.completed ||
          s.processingState == ProcessingState.idle,
    );
  }
}

final buddyNotifierProvider =
    AutoDisposeNotifierProvider<BuddyNotifier, BuddyStateData>(
        BuddyNotifier.new);

// Maps BuddyPhase → ConversationState used by OrbWidget
ConversationState _toConvState(BuddyPhase phase) {
  switch (phase) {
    case BuddyPhase.idle:
      return ConversationState.idle;
    case BuddyPhase.listening:
      return ConversationState.listening;
    case BuddyPhase.processing:
      return ConversationState.thinking;
    case BuddyPhase.playing:
      return ConversationState.speaking;
  }
}

// ─── Screen ───────────────────────────────────────────────────────────────────
class BuddyScreen extends ConsumerStatefulWidget {
  const BuddyScreen({super.key});

  @override
  ConsumerState<BuddyScreen> createState() => _BuddyScreenState();
}

class _BuddyScreenState extends ConsumerState<BuddyScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _entryCtrl;
  late Animation<double> _entryFade;
  late Animation<Offset> _entrySlide;

  @override
  void initState() {
    super.initState();
    _entryCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    )..forward();
    _entryFade = CurvedAnimation(parent: _entryCtrl, curve: Curves.easeOut);
    _entrySlide = Tween<Offset>(
      begin: const Offset(0, 0.08),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _entryCtrl, curve: Curves.easeOut));
  }

  @override
  void dispose() {
    _entryCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(buddyNotifierProvider);
    final notifier = ref.read(buddyNotifierProvider.notifier);
    final profileAsync = ref.watch(profileProvider);
    final preferredLang =
        profileAsync.valueOrNull?['preferred_language'] as String? ?? 'English';

    final convState = _toConvState(s.phase);
    final displayText = s.lastReply ?? s.lastUserText ?? '';

    // Show session summary dialog when available
    // (Removed — mood data is available in Mental Health Tracker instead)

    return Scaffold(
      backgroundColor: const Color(0xFF071412),
      body: FadeTransition(
        opacity: _entryFade,
        child: SlideTransition(
          position: _entrySlide,
          child: Stack(
            children: [
              _AnimatedBackground(state: convState),
              SafeArea(
                child: Column(
                  children: [
                    _buildTopBar(context),
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          _StateLabel(state: convState),
                          const SizedBox(height: 20),
                          OrbWidget(state: convState, size: 200),
                          const SizedBox(height: 20),
                          _DisplayText(text: displayText),
                        ],
                      ),
                    ),
                    if (s.error != null)
                      Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 24, vertical: 8),
                        child: Text(
                          s.error!,
                          style: TextStyle(
                            color: const Color(0xFFFF6666).withOpacity(0.9),
                            fontSize: 13,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    _BuddyBottomControls(
                      isActive: s.conversationActive,
                      onStart: () => notifier.startConversation(
                          preferredLang: preferredLang),
                      onEnd: notifier.endConversation,
                      lang: preferredLang,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTopBar(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Center(
        child: Column(
          children: [
            const Text(
              'Buddy',
              style: TextStyle(
                color: Colors.white,
                fontSize: 17,
                fontWeight: FontWeight.w600,
              ),
            ),
            Text(
              'Your Emotional Companion',
              style: TextStyle(
                color: Colors.white.withOpacity(0.45),
                fontSize: 11,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Animated background gradient ─────────────────────────────────────────────
class _AnimatedBackground extends StatelessWidget {
  final ConversationState state;
  const _AnimatedBackground({required this.state});

  Color _bgColorFor(ConversationState s) {
    switch (s) {
      case ConversationState.idle:
        return AppColors.primary;
      case ConversationState.listening:
        return const Color(0xFF00D2A0);
      case ConversationState.processing:
        return const Color(0xFFFF6B6B);
      case ConversationState.thinking:
        return const Color(0xFFFF4499);
      case ConversationState.speaking:
        return const Color(0xFF4ECDC4);
    }
  }

  @override
  Widget build(BuildContext context) {
    final color = _bgColorFor(state);
    return AnimatedContainer(
      duration: const Duration(milliseconds: 700),
      decoration: BoxDecoration(
        gradient: RadialGradient(
          center: const Alignment(0, -0.2),
          radius: 1.4,
          colors: [color.withOpacity(0.22), const Color(0xFF071412)],
        ),
      ),
    );
  }
}

// ─── State label above orb ─────────────────────────────────────────────────────
class _StateLabel extends StatelessWidget {
  final ConversationState state;
  const _StateLabel({required this.state});

  String get _label {
    switch (state) {
      case ConversationState.idle:
        return 'Tap to start';
      case ConversationState.listening:
        return 'Listening...';
      case ConversationState.processing:
        return 'Processing...';
      case ConversationState.thinking:
        return 'Buddy is thinking...';
      case ConversationState.speaking:
        return 'Buddy is speaking...';
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 400),
      transitionBuilder: (child, anim) =>
          FadeTransition(opacity: anim, child: child),
      child: Text(
        _label,
        key: ValueKey(_label),
        style: TextStyle(
          color: Colors.white.withOpacity(0.6),
          fontSize: 15,
          fontWeight: FontWeight.w400,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}

// ─── Display text bubble ───────────────────────────────────────────────────────
class _DisplayText extends StatelessWidget {
  final String text;
  const _DisplayText({required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 500),
        transitionBuilder: (child, anim) =>
            FadeTransition(opacity: anim, child: child),
        child: text.isEmpty
            ? const SizedBox.shrink()
            : Container(
                key: ValueKey(text),
                constraints: const BoxConstraints(maxHeight: 120),
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 14,
                ),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.07),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(
                    color: Colors.white.withOpacity(0.1),
                    width: 1,
                  ),
                ),
                child: SingleChildScrollView(
                  child: Text(
                    text,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      height: 1.55,
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                ),
              ),
      ),
    );
  }
}

// ─── Bottom controls ───────────────────────────────────────────────────────────
class _BuddyBottomControls extends StatelessWidget {
  final bool isActive;
  final VoidCallback onStart;
  final VoidCallback onEnd;
  final String lang;

  const _BuddyBottomControls({
    required this.isActive,
    required this.onStart,
    required this.onEnd,
    required this.lang,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
      child: Column(
        children: [
          if (!isActive)
            _StartButton(onTap: onStart, lang: lang)
          else
            _EndButton(onTap: onEnd, lang: lang),
        ],
      ),
    );
  }
}

// ─── Start button with pulse animation ────────────────────────────────────────
class _StartButton extends StatefulWidget {
  final VoidCallback onTap;
  final String lang;
  const _StartButton({required this.onTap, required this.lang});

  @override
  State<_StartButton> createState() => _StartButtonState();
}

class _StartButtonState extends State<_StartButton>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);
    _scale = Tween<double>(begin: 1.0, end: 1.06).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeInOutSine),
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _scale,
      builder: (_, child) => Transform.scale(scale: _scale.value, child: child),
      child: GestureDetector(
        onTap: widget.onTap,
        child: Container(
          width: double.infinity,
          height: 64,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [AppColors.primary, const Color(0xFF2DA882)],
            ),
            borderRadius: BorderRadius.circular(32),
            boxShadow: [
              BoxShadow(
                color: AppColors.primary.withOpacity(0.50),
                blurRadius: 24,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.mic_rounded, color: Colors.white, size: 24),
              const SizedBox(width: 12),
              Text(
                appStr(widget.lang, 'start_conversation'),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.3,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── End button ────────────────────────────────────────────────────────────────
class _EndButton extends StatelessWidget {
  final VoidCallback onTap;
  final String lang;
  const _EndButton({required this.onTap, required this.lang});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        height: 64,
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.08),
          borderRadius: BorderRadius.circular(32),
          border: Border.all(
            color: const Color(0xFFFF4444).withOpacity(0.6),
            width: 1.5,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.stop_circle_outlined,
              color: const Color(0xFFFF6666).withOpacity(0.9),
              size: 24,
            ),
            const SizedBox(width: 12),
            Text(
              appStr(lang, 'end'),
              style: TextStyle(
                color: const Color(0xFFFF8888).withOpacity(0.9),
                fontSize: 17,
                fontWeight: FontWeight.w500,
                letterSpacing: 0.3,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

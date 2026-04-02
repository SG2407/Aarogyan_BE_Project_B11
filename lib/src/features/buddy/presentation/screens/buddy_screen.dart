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
import 'package:shared_preferences/shared_preferences.dart';
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
  final String selectedSpeaker;

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
    this.selectedSpeaker = 'priya',
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
    String? selectedSpeaker,
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
      selectedSpeaker: selectedSpeaker ?? this.selectedSpeaker,
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
    _loadSavedSpeaker();

    ref.onDispose(() {
      _disposed = true;
      _postSpeechTimer?.cancel();
      if (_vadListening) _vad.stopListening().catchError((_) {});
      _vad.dispose();
      _player.dispose();
    });
    return const BuddyStateData();
  }

  Future<void> _loadSavedSpeaker() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString('buddy_speaker');
    if (saved != null && !_disposed) {
      _set(state.copyWith(selectedSpeaker: saved));
    }
  }

  Future<void> setSpeaker(String speakerId) async {
    _set(state.copyWith(selectedSpeaker: speakerId));
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('buddy_speaker', speakerId);
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
        speaker: state.selectedSpeaker,
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
                    _buildTopBar(context, notifier, s),
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

  Widget _buildTopBar(
      BuildContext context, BuddyNotifier notifier, BuddyStateData s) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
      child: Row(
        children: [
          // ── Instruction button (top-left) ──
          _GlassIconButton(
            icon: Icons.info_outline_rounded,
            onTap: () => _showInstructionsDialog(context),
          ),
          const Spacer(),
          // ── Title ──
          Column(
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
          const Spacer(),
          // ── Voice selection button (top-right) ──
          _GlassIconButton(
            icon: Icons.record_voice_over_rounded,
            onTap: () => _showVoiceSelectionSheet(context, ref),
          ),
        ],
      ),
    );
  }

  void _showInstructionsDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (_) => const _InstructionsDialog(),
    );
  }

  void _showVoiceSelectionSheet(BuildContext context, WidgetRef ref) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _VoiceSelectionSheet(parentRef: ref),
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

// ─── Glass icon button ────────────────────────────────────────────────────────
class _GlassIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _GlassIconButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.08),
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white.withOpacity(0.12)),
        ),
        child: Icon(icon, color: Colors.white.withOpacity(0.7), size: 20),
      ),
    );
  }
}

// ─── Instructions dialog ──────────────────────────────────────────────────────
class _InstructionsDialog extends StatelessWidget {
  const _InstructionsDialog();

  static const _tips = [
    {
      'icon': Icons.mic_rounded,
      'title': 'Speak naturally',
      'desc': 'Talk to Buddy like you would to a close friend. '
          'There\'s no right or wrong way to express yourself.',
    },
    {
      'icon': Icons.timer_rounded,
      'title': 'Take your time',
      'desc': 'Buddy waits for you — pauses while you think are fine. '
          'Speak when you\'re ready.',
    },
    {
      'icon': Icons.language_rounded,
      'title': 'Use your language',
      'desc': 'Speak in English, Hindi, or Marathi — Buddy understands and '
          'replies in the same language.',
    },
    {
      'icon': Icons.emoji_emotions_rounded,
      'title': 'Be honest about feelings',
      'desc': 'The more openly you share how you feel, the better Buddy can '
          'support you and track your emotional health accurately.',
    },
    {
      'icon': Icons.insights_rounded,
      'title': 'Check your Tracker',
      'desc': 'Visit Mental Health Tracker to see mood trends, emotion '
          'patterns, and insights from your sessions.',
    },
  ];

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 380),
        decoration: BoxDecoration(
          color: const Color(0xFF0F1F1C).withOpacity(0.95),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: Colors.white.withOpacity(0.1)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 20),
            const Text(
              'How to use Buddy',
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Tips for the best experience',
              style: TextStyle(
                color: Colors.white.withOpacity(0.45),
                fontSize: 12,
              ),
            ),
            const SizedBox(height: 16),
            ..._tips.map((tip) => _TipRow(
                  icon: tip['icon'] as IconData,
                  title: tip['title'] as String,
                  desc: tip['desc'] as String,
                )),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: SizedBox(
                width: double.infinity,
                child: TextButton(
                  onPressed: () => Navigator.pop(context),
                  style: TextButton.styleFrom(
                    backgroundColor: AppColors.primary.withOpacity(0.15),
                    foregroundColor: AppColors.primary,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  child: const Text('Got it',
                      style:
                          TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
                ),
              ),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }
}

class _TipRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String desc;
  const _TipRow(
      {required this.icon, required this.title, required this.desc});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: AppColors.primary.withOpacity(0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: AppColors.primary, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    )),
                const SizedBox(height: 2),
                Text(desc,
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.55),
                      fontSize: 12,
                      height: 1.4,
                    )),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Voice selection bottom sheet ─────────────────────────────────────────────
class _VoiceSelectionSheet extends StatefulWidget {
  final WidgetRef parentRef;
  const _VoiceSelectionSheet({required this.parentRef});

  @override
  State<_VoiceSelectionSheet> createState() => _VoiceSelectionSheetState();
}

class _VoiceSelectionSheetState extends State<_VoiceSelectionSheet> {
  final _previewPlayer = AudioPlayer();
  String? _loadingSpeaker;

  static const _voices = [
    // Female
    {'id': 'priya', 'name': 'Priya', 'gender': 'female', 'desc': 'Warm & gentle'},
    {'id': 'simran', 'name': 'Simran', 'gender': 'female', 'desc': 'Calm & soothing'},
    {'id': 'kavya', 'name': 'Kavya', 'gender': 'female', 'desc': 'Soft & empathetic'},
    {'id': 'shreya', 'name': 'Shreya', 'gender': 'female', 'desc': 'Clear & friendly'},
    {'id': 'neha', 'name': 'Neha', 'gender': 'female', 'desc': 'Bright & cheerful'},
    {'id': 'roopa', 'name': 'Roopa', 'gender': 'female', 'desc': 'Mature & comforting'},
    // Male
    {'id': 'aditya', 'name': 'Aditya', 'gender': 'male', 'desc': 'Calm & reassuring'},
    {'id': 'kabir', 'name': 'Kabir', 'gender': 'male', 'desc': 'Deep & grounding'},
    {'id': 'anand', 'name': 'Anand', 'gender': 'male', 'desc': 'Warm & supportive'},
    {'id': 'rohan', 'name': 'Rohan', 'gender': 'male', 'desc': 'Friendly & steady'},
    {'id': 'dev', 'name': 'Dev', 'gender': 'male', 'desc': 'Gentle & composed'},
    {'id': 'rahul', 'name': 'Rahul', 'gender': 'male', 'desc': 'Warm & natural'},
  ];

  @override
  void dispose() {
    _previewPlayer.dispose();
    super.dispose();
  }

  Future<void> _previewVoice(String speakerId) async {
    setState(() => _loadingSpeaker = speakerId);
    try {
      final repo = widget.parentRef.read(buddyRepositoryProvider);
      final url = repo.getVoiceSampleUrl(speakerId);
      await _previewPlayer.setUrl(url);
      await _previewPlayer.play();
      // Wait for playback to complete
      await _previewPlayer.playerStateStream.firstWhere(
        (s) =>
            s.processingState == ProcessingState.completed ||
            s.processingState == ProcessingState.idle,
      );
    } catch (e) {
      debugPrint('[Voice] preview error: $e');
    }
    if (mounted) setState(() => _loadingSpeaker = null);
  }

  @override
  Widget build(BuildContext context) {
    final currentSpeaker =
        widget.parentRef.watch(buddyNotifierProvider).selectedSpeaker;

    return Container(
      margin: const EdgeInsets.only(top: 60),
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.75,
      ),
      decoration: BoxDecoration(
        color: const Color(0xFF0F1F1C).withOpacity(0.97),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        border: Border.all(color: Colors.white.withOpacity(0.1)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 12),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.2),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'Choose a Voice',
            style: TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Tap play to preview, select to apply',
            style: TextStyle(
              color: Colors.white.withOpacity(0.45),
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 16),
          Flexible(
            child: ListView(
              shrinkWrap: true,
              padding: EdgeInsets.only(
                  bottom: MediaQuery.of(context).padding.bottom + 16),
              children: _voices.map((v) {
            final id = v['id'] as String;
            final isSelected = id == currentSpeaker;
            final isLoading = _loadingSpeaker == id;
            return _VoiceTile(
              name: v['name'] as String,
              desc: v['desc'] as String,
              gender: v['gender'] as String,
              isSelected: isSelected,
              isLoading: isLoading,
              onPreview: () => _previewVoice(id),
              onSelect: () {
                widget.parentRef
                    .read(buddyNotifierProvider.notifier)
                    .setSpeaker(id);
              },
            );
          }).toList(),
            ),
          ),
        ],
      ),
    );
  }
}

class _VoiceTile extends StatelessWidget {
  final String name;
  final String desc;
  final String gender;
  final bool isSelected;
  final bool isLoading;
  final VoidCallback onPreview;
  final VoidCallback onSelect;

  const _VoiceTile({
    required this.name,
    required this.desc,
    required this.gender,
    required this.isSelected,
    required this.isLoading,
    required this.onPreview,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onSelect,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: isSelected
              ? AppColors.primary.withOpacity(0.12)
              : Colors.white.withOpacity(0.04),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isSelected
                ? AppColors.primary.withOpacity(0.4)
                : Colors.white.withOpacity(0.06),
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: (gender == 'female'
                        ? const Color(0xFFE879A8)
                        : const Color(0xFF5B8DEF))
                    .withOpacity(0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                gender == 'female' ? Icons.face_3_rounded : Icons.face_rounded,
                color: gender == 'female'
                    ? const Color(0xFFE879A8)
                    : const Color(0xFF5B8DEF),
                size: 20,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name,
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w600)),
                  Text(desc,
                      style: TextStyle(
                          color: Colors.white.withOpacity(0.45),
                          fontSize: 12)),
                ],
              ),
            ),
            // Play preview
            GestureDetector(
              onTap: onPreview,
              child: Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.08),
                  shape: BoxShape.circle,
                ),
                child: isLoading
                    ? Padding(
                        padding: const EdgeInsets.all(8),
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white.withOpacity(0.5),
                        ),
                      )
                    : Icon(Icons.play_arrow_rounded,
                        color: Colors.white.withOpacity(0.7), size: 18),
              ),
            ),
            const SizedBox(width: 8),
            // Selected check
            if (isSelected)
              Icon(Icons.check_circle_rounded,
                  color: AppColors.primary, size: 22)
            else
              Icon(Icons.circle_outlined,
                  color: Colors.white.withOpacity(0.2), size: 22),
          ],
        ),
      ),
    );
  }
}

import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:speech_to_text/speech_recognition_result.dart';
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
const _sttLocale = {
  'English': 'en-US',
  'Hindi': 'hi-IN',
  'Marathi': 'mr-IN',
};

class BuddyNotifier extends AutoDisposeNotifier<BuddyStateData> {
  final _speech = stt.SpeechToText();
  final _player = AudioPlayer();

  bool _speechInitialised = false;
  bool _disposed = false;
  String _preferredLang = 'English';

  /// Partial transcript while speech-to-text is running
  String _partialTranscript = '';

  /// Guard against _processText being called twice for the same utterance
  bool _processing = false;

  @override
  BuddyStateData build() {
    ref.onDispose(() {
      _disposed = true;
      _speech.stop();
      _player.dispose();
    });
    return const BuddyStateData();
  }

  // ── Public API ──────────────────────────────────────────────────────────────

  /// Called when user taps "Start Conversation".
  /// Initialises on-device STT and immediately starts listening.
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
    await _initSpeech();
    if (_speechInitialised) {
      await _startListening();
    } else {
      _set(state.copyWith(
        error: 'Microphone permission denied or Speech not available.',
      ));
    }
  }

  /// Called when user taps the interrupt button during playback.
  Future<void> interrupt() async {
    await _player.stop();
    _set(state.copyWith(phase: BuddyPhase.idle, soundLevel: 0.0));
    await _startListening();
  }

  Future<void> endConversation() async {
    await _speech.stop();
    await _player.stop();
    _partialTranscript = '';

    _set(const BuddyStateData());
  }

  void clearSummary() {
    _set(const BuddyStateData());
  }

  // ── Internal helpers ────────────────────────────────────────────────────────

  void _set(BuddyStateData s) {
    if (!_disposed) state = s;
  }

  Future<void> _initSpeech() async {
    if (_speechInitialised) return;
    _speechInitialised = await _speech.initialize(
      onStatus: _onSpeechStatus,
      onError: (e) {
        if (_disposed) return;
        _set(state.copyWith(
          phase: BuddyPhase.idle,
          error: 'Speech error: ${e.errorMsg}',
          soundLevel: 0.0,
        ));
      },
    );
  }

  /// Start on-device speech recognition.
  /// `pauseFor` acts as the on-device VAD — auto-finalises after 5 s of silence.
  Future<void> _startListening() async {
    if (_disposed || !state.conversationActive) return;
    if (!_speechInitialised) return;

    _partialTranscript = '';
    _set(state.copyWith(
        phase: BuddyPhase.listening, error: null, soundLevel: 0.0));

    await _speech.listen(
      onResult: _onResult,
      listenFor: const Duration(seconds: 60),
      pauseFor: const Duration(seconds: 5),
      localeId: _sttLocale[_preferredLang] ?? 'en-US',
      onSoundLevelChange: (level) {
        // SpeechToText reports roughly –2..10 dB; normalise to 0..1
        final norm = ((level + 2) / 12).clamp(0.0, 1.0);
        _set(state.copyWith(soundLevel: norm));
      },
      listenOptions: stt.SpeechListenOptions(
        cancelOnError: false,
        partialResults: true,
      ),
    );
  }

  /// Called on every partial/final recognition event.
  void _onResult(SpeechRecognitionResult result) {
    if (_disposed) return;
    _partialTranscript = result.recognizedWords;

    if (result.finalResult && _partialTranscript.trim().isNotEmpty) {
      if (!_processing) _processText(_partialTranscript.trim());
    }
  }

  /// SpeechToText status callback — 'done' fires when `pauseFor` silence is
  /// reached without a `finalResult=true` callback arriving first.
  void _onSpeechStatus(String status) {
    if (_disposed) return;
    if (status == 'done' &&
        state.phase == BuddyPhase.listening &&
        _partialTranscript.trim().isNotEmpty) {
      if (!_processing) _processText(_partialTranscript.trim());
    }
  }

  /// Send recognised text to backend, play the response, then loop back to
  /// listening — completing the fully autonomous conversation cycle.
  Future<void> _processText(String userText) async {
    if (_disposed || _processing) return;
    _processing = true;
    await _speech.stop();
    _partialTranscript = '';

    _set(state.copyWith(
      phase: BuddyPhase.processing,
      lastUserText: userText,
      soundLevel: 0.0,
    ));

    try {
      final repo = ref.read(buddyRepositoryProvider);
      final historyMaps = state.history.map((t) => t.toMap()).toList();
      final result = await repo.sendText(
        userText,
        historyMaps,
        preferredLanguage: _preferredLang,
        sessionGroupId: state.sessionGroupId,
      );

      if (_disposed) return;

      final reply = result['buddy_text'] as String? ?? '';
      final audioBase64 = result['audio_base64'] as String?;

      final newHistory = [
        ...state.history,
        ConversationTurn(role: 'user', content: userText),
        ConversationTurn(role: 'assistant', content: reply),
      ];
      // Keep last 10 turns (20 messages) to bound context size
      final trimmed = newHistory.length > 20
          ? newHistory.sublist(newHistory.length - 20)
          : newHistory;

      _set(state.copyWith(
        phase: BuddyPhase.playing,
        lastReply: reply,
        history: trimmed,
        error: null,
      ));

      if (audioBase64 != null && audioBase64.isNotEmpty) {
        await _playBase64Audio(audioBase64);
      }

      // Auto-loop: restart listening once audio finishes
      if (_disposed) return;
      if (state.conversationActive && state.phase == BuddyPhase.playing) {
        await _startListening();
      }
    } catch (e) {
      if (_disposed) return;
      String msg = 'Something went wrong — please try again.';
      int retryDelay = 2;

      if (e is DioException) {
        final statusCode = e.response?.statusCode;
        // 404 / 502 / 503 → HF Space cold-start or sleeping; retry after longer pause
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
        await _startListening();
      }
    }
    _processing = false;
  }

  Future<void> _playBase64Audio(String base64Audio) async {
    final bytes = base64Decode(base64Audio);
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/buddy_response.wav');
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


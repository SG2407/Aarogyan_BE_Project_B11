import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:math' as math;
import '../../../../core/theme/app_theme.dart';
import '../../../../core/l10n/app_strings.dart';
import '../../data/buddy_repository.dart';
import '../../../profile/data/profile_repository.dart';

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

  const BuddyStateData({
    this.phase = BuddyPhase.idle,
    this.conversationActive = false,
    this.lastUserText,
    this.lastReply,
    this.history = const [],
    this.error,
    this.soundLevel = 0.0,
  });

  BuddyStateData copyWith({
    BuddyPhase? phase,
    bool? conversationActive,
    String? lastUserText,
    String? lastReply,
    List<ConversationTurn>? history,
    String? error,
    double? soundLevel,
  }) {
    return BuddyStateData(
      phase: phase ?? this.phase,
      conversationActive: conversationActive ?? this.conversationActive,
      lastUserText: lastUserText ?? this.lastUserText,
      lastReply: lastReply ?? this.lastReply,
      history: history ?? this.history,
      error: error,
      soundLevel: soundLevel ?? this.soundLevel,
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
    _set(state.copyWith(
      conversationActive: true,
      history: [],
      error: null,
      soundLevel: 0.0,
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
    _set(state.copyWith(phase: BuddyPhase.listening, error: null, soundLevel: 0.0));

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
      _processText(_partialTranscript.trim());
    }
  }

  /// SpeechToText status callback — 'done' fires when `pauseFor` silence is
  /// reached without a `finalResult=true` callback arriving first.
  void _onSpeechStatus(String status) {
    if (_disposed) return;
    if (status == 'done' &&
        state.phase == BuddyPhase.listening &&
        _partialTranscript.trim().isNotEmpty) {
      _processText(_partialTranscript.trim());
    }
  }

  /// Send recognised text to backend, play the response, then loop back to
  /// listening — completing the fully autonomous conversation cycle.
  Future<void> _processText(String userText) async {
    if (_disposed) return;
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
    final profileAsync = ref.watch(profileProvider);
    final preferredLang = profileAsync.valueOrNull?['preferred_language'] as String? ?? 'English';

    return Scaffold(
      appBar: AppBar(
        title: Text(appStr(preferredLang, 'buddy_title')),
        actions: [
          if (s.conversationActive)
            TextButton(
              onPressed: notifier.endConversation,
              child: Text(appStr(preferredLang, 'end')),
            ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const Spacer(),
              Center(
                child: _OrbzAvatar(
                  phase: s.phase,
                  soundLevel: s.soundLevel,
                ),
              ),
              const SizedBox(height: 28),
              _PhaseLabel(
                phase: s.phase,
                conversationActive: s.conversationActive,
                lastUserText: s.lastUserText,
                lastReply: s.lastReply,
                lang: preferredLang,
              ),
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
                onStart: () => notifier.startConversation(preferredLang: preferredLang),
                onInterrupt: notifier.interrupt,
                lang: preferredLang,
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
class _OrbzAvatar extends StatefulWidget {
  final BuddyPhase phase;
  final double soundLevel;
  const _OrbzAvatar({required this.phase, this.soundLevel = 0.0});

  @override
  State<_OrbzAvatar> createState() => _OrbzAvatarState();
}

class _OrbzAvatarState extends State<_OrbzAvatar>
    with TickerProviderStateMixin {
  late final AnimationController _breathCtrl;
  late final AnimationController _rippleCtrl;
  late final AnimationController _glowCtrl;
  late final AnimationController _ringCtrl;
  late final AnimationController _innerCtrl;

  @override
  void initState() {
    super.initState();
    _breathCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 3200));
    _rippleCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1600));
    _glowCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1100));
    _ringCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 2800));
    _innerCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 5000))
      ..repeat();
    _syncAnimations(widget.phase);
  }

  void _syncAnimations(BuddyPhase phase) {
    _breathCtrl.stop();
    _rippleCtrl.stop();
    _glowCtrl.stop();
    _ringCtrl.stop();
    switch (phase) {
      case BuddyPhase.idle:
        _breathCtrl.repeat(reverse: true);
        _glowCtrl.repeat(reverse: true);
        break;
      case BuddyPhase.listening:
        _rippleCtrl.repeat();
        _glowCtrl.repeat(reverse: true);
        break;
      case BuddyPhase.processing:
      case BuddyPhase.playing:
        _ringCtrl.repeat();
        _glowCtrl.repeat(reverse: true);
        break;
    }
  }

  @override
  void didUpdateWidget(_OrbzAvatar old) {
    super.didUpdateWidget(old);
    if (old.phase != widget.phase) _syncAnimations(widget.phase);
  }

  @override
  void dispose() {
    _breathCtrl.dispose();
    _rippleCtrl.dispose();
    _glowCtrl.dispose();
    _ringCtrl.dispose();
    _innerCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: SizedBox(
        width: 260,
        height: 260,
        child: AnimatedBuilder(
          animation: Listenable.merge(
              [_breathCtrl, _rippleCtrl, _glowCtrl, _ringCtrl, _innerCtrl]),
          builder: (_, __) => CustomPaint(
            painter: _OrbPainter(
              phase: widget.phase,
              breathT: _breathCtrl.value,
              rippleT: _rippleCtrl.value,
              glowT: _glowCtrl.value,
              ringT: _ringCtrl.value,
              innerT: _innerCtrl.value,
              soundLevel: widget.soundLevel,
            ),
          ),
        ),
      ),
    );
  }
}

class _OrbPainter extends CustomPainter {
  final BuddyPhase phase;
  final double breathT;
  final double rippleT;
  final double glowT;
  final double ringT;
  final double innerT;
  final double soundLevel;

  _OrbPainter({
    required this.phase,
    required this.breathT,
    required this.rippleT,
    required this.glowT,
    required this.ringT,
    required this.innerT,
    this.soundLevel = 0.0,
  });

  static const _idleColors = [Color(0xFF1DE9B6), Color(0xFF00ACC1)];
  static const _listenColors = [Color(0xFF76FF03), Color(0xFF1DE9B6)];
  static const _processColors = [Color(0xFF40C4FF), Color(0xFF5C6BC0)];
  static const _playColors = [Color(0xFF64FFDA), Color(0xFF2979FF)];

  List<Color> get _clrs {
    if (phase == BuddyPhase.listening) return _listenColors;
    if (phase == BuddyPhase.processing) return _processColors;
    if (phase == BuddyPhase.playing) return _playColors;
    return _idleColors;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    final c = Offset(cx, cy);
    final baseR = size.width * 0.30;
    final double scale;
    if (phase == BuddyPhase.listening) {
      scale = 1.0 + soundLevel * 0.18;
    } else if (phase == BuddyPhase.idle) {
      scale = 1.0 + breathT * 0.08;
    } else {
      scale = 1.0;
    }
    final r = baseR * scale;
    final clrs = _clrs;

    _drawOuterAura(canvas, c, r, clrs);
    if (phase == BuddyPhase.listening) _drawRipples(canvas, c, r, clrs);
    if (phase == BuddyPhase.playing || phase == BuddyPhase.processing) {
      _drawEnergyRings(canvas, c, r, clrs);
    }
    _drawCoreOrb(canvas, c, r, clrs);
    _drawHighlight(canvas, c, r);
    _drawEdgeGlow(canvas, c, r, clrs);
  }

  void _drawOuterAura(Canvas canvas, Offset c, double r, List<Color> clrs) {
    final auraR = r * 2.1;
    final alpha =
        phase == BuddyPhase.idle ? 0.07 + breathT * 0.05 : 0.12 + glowT * 0.08;
    canvas.drawCircle(
      c,
      auraR,
      Paint()
        ..shader = RadialGradient(colors: [
          clrs[0].withValues(alpha: alpha),
          clrs[1].withValues(alpha: alpha * 0.3),
          clrs[1].withValues(alpha: 0),
        ], stops: const [
          0.0,
          0.55,
          1.0
        ]).createShader(Rect.fromCircle(center: c, radius: auraR)),
    );
  }

  void _drawRipples(Canvas canvas, Offset c, double r, List<Color> clrs) {
    for (int i = 0; i < 4; i++) {
      final t = (rippleT + i * 0.25) % 1.0;
      final rR = r * (1.08 + t * 1.9);
      final a = (1.0 - t) * 0.55;
      if (a < 0.01) continue;
      canvas.drawCircle(
        c,
        rR,
        Paint()
          ..color = clrs[0].withValues(alpha: a)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.5 * (1.0 - t),
      );
    }
  }

  void _drawEnergyRings(Canvas canvas, Offset c, double r, List<Color> clrs) {
    final ringR = r * 1.42;
    final start = ringT * math.pi * 2;
    // Outer soft glow arc
    canvas.drawArc(
      Rect.fromCircle(center: c, radius: ringR),
      start,
      math.pi * 1.6,
      false,
      Paint()
        ..color = clrs[0].withValues(alpha: 0.18)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 12
        ..strokeCap = StrokeCap.round
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
    );
    // Bright leading arc
    canvas.drawArc(
      Rect.fromCircle(center: c, radius: ringR),
      start,
      math.pi * 1.6,
      false,
      Paint()
        ..color = clrs[0].withValues(alpha: 0.9)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..strokeCap = StrokeCap.round,
    );
    // Counter-rotating inner arc
    canvas.drawArc(
      Rect.fromCircle(center: c, radius: r * 1.22),
      -start * 0.65,
      math.pi * 0.85,
      false,
      Paint()
        ..color = clrs[1].withValues(alpha: 0.55)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.8
        ..strokeCap = StrokeCap.round,
    );
  }

  void _drawCoreOrb(Canvas canvas, Offset c, double r, List<Color> clrs) {
    // Fluid internal gradient that slowly orbits
    final gx = math.cos(innerT * math.pi * 2) * 0.28;
    final gy = math.sin(innerT * math.pi * 2) * 0.28;
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..shader = RadialGradient(
          center: Alignment(gx, gy),
          colors: [
            Colors.white.withValues(alpha: 0.95),
            clrs[0],
            clrs[1],
          ],
          stops: const [0.0, 0.42, 1.0],
        ).createShader(Rect.fromCircle(center: c, radius: r)),
    );
    // Fluid boundary ring when listening
    if (phase == BuddyPhase.listening) {
      canvas.drawCircle(
        c,
        r,
        Paint()
          ..color = clrs[0].withValues(alpha: 0.2 + glowT * 0.15)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 5
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5),
      );
    }
  }

  void _drawHighlight(Canvas canvas, Offset c, double r) {
    final h = Offset(c.dx - r * 0.27, c.dy - r * 0.27);
    canvas.drawCircle(
      h,
      r * 0.30,
      Paint()
        ..shader = RadialGradient(colors: [
          Colors.white.withValues(alpha: 0.7),
          Colors.white.withValues(alpha: 0.0),
        ]).createShader(Rect.fromCircle(center: h, radius: r * 0.30)),
    );
  }

  void _drawEdgeGlow(Canvas canvas, Offset c, double r, List<Color> clrs) {
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..color = clrs[0].withValues(alpha: 0.40 + glowT * 0.20)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3.5
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8),
    );
  }

  @override
  bool shouldRepaint(_OrbPainter old) => true;
}

// ─── Phase label ──────────────────────────────────────────────────────────────
class _PhaseLabel extends StatelessWidget {
  final BuddyPhase phase;
  final bool conversationActive;
  final String? lastUserText;
  final String? lastReply;
  final String lang;

  const _PhaseLabel({
    required this.phase,
    required this.conversationActive,
    required this.lang,
    this.lastUserText,
    this.lastReply,
  });

  String _headline() {
    if (!conversationActive) return appStr(lang, 'tap_to_begin');
    switch (phase) {
      case BuddyPhase.idle:
        return appStr(lang, 'starting');
      case BuddyPhase.listening:
        return appStr(lang, 'listening');
      case BuddyPhase.processing:
        return appStr(lang, 'thinking');
      case BuddyPhase.playing:
        return appStr(lang, 'speaking');
    }
  }

  @override
  Widget build(BuildContext context) {
    final caption = phase == BuddyPhase.listening
        ? appStr(lang, 'speak_freely')
        : phase == BuddyPhase.playing
            ? appStr(lang, 'tap_to_interrupt_caption')
            : null;

    return Column(
      children: [
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 300),
          child: Text(
            _headline(),
            key: ValueKey(_headline()),
            style: Theme.of(context)
                .textTheme
                .headlineSmall
                ?.copyWith(color: AppColors.primary),
            textAlign: TextAlign.center,
          ),
        ),
        if (caption != null) ...[
          const SizedBox(height: 6),
          Text(
            caption,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context)
                      .colorScheme
                      .onSurface
                      .withValues(alpha: 0.55),
                ),
            textAlign: TextAlign.center,
          ),
        ],
        if (lastUserText != null && conversationActive) ...[
          const SizedBox(height: 16),
          _TranscriptChip(userText: lastUserText!, reply: lastReply),
        ],
      ],
    );
  }
}

class _TranscriptChip extends StatelessWidget {
  final String userText;
  final String? reply;
  const _TranscriptChip({required this.userText, this.reply});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.person_rounded,
                  size: 14, color: AppColors.primary),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  userText,
                  style: Theme.of(context).textTheme.bodySmall,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          if (reply != null && reply!.isNotEmpty) ...[
            const SizedBox(height: 6),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.auto_awesome_rounded,
                    size: 14, color: Color(0xFF1DE9B6)),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    reply!,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context)
                              .colorScheme
                              .onSurface
                              .withValues(alpha: 0.7),
                        ),
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

// ─── Bottom controls ──────────────────────────────────────────────────────────
class _BottomControls extends StatelessWidget {
  final BuddyPhase phase;
  final bool conversationActive;
  final VoidCallback onStart;
  final VoidCallback onInterrupt;
  final String lang;

  const _BottomControls({
    required this.phase,
    required this.conversationActive,
    required this.onStart,
    required this.onInterrupt,
    required this.lang,
  });

  @override
  Widget build(BuildContext context) {
    // ── Not started ──
    if (!conversationActive) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          ElevatedButton.icon(
            onPressed: onStart,
            icon: const Icon(Icons.favorite_rounded),
            label: Text(appStr(lang, 'start_conversation')),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              padding:
                  const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(32)),
              textStyle:
                  const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            appStr(lang, 'one_tap_hint'),
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

    // ── Listening — no button, show animated sound-wave indicator ──
    if (phase == BuddyPhase.listening) {
      return Column(
        children: [
          const _SoundWaveIndicator(),
          const SizedBox(height: 8),
          Text(
            appStr(lang, 'pause_hint'),
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: Theme.of(context)
                      .colorScheme
                      .onSurface
                      .withValues(alpha: 0.4),
                ),
          ),
        ],
      );
    }

    // ── Playing — interrupt button ──
    if (phase == BuddyPhase.playing) {
      return Column(
        children: [
          GestureDetector(
            onTap: onInterrupt,
            child: Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: AppColors.error.withValues(alpha: 0.1),
                shape: BoxShape.circle,
                border: Border.all(color: AppColors.error, width: 2),
              ),
              child: const Icon(Icons.mic_rounded,
                  color: AppColors.error, size: 28),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            appStr(lang, 'tap_interrupt'),
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: Theme.of(context)
                      .colorScheme
                      .onSurface
                      .withValues(alpha: 0.4),
                ),
          ),
        ],
      );
    }

    // ── Processing / idle spinner ──
    return Column(
      children: [
        const SizedBox(
          width: 32,
          height: 32,
          child: CircularProgressIndicator(strokeWidth: 2.5),
        ),
        const SizedBox(height: 8),
        Text(
          'Please wait…',
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: Theme.of(context)
                    .colorScheme
                    .onSurface
                    .withValues(alpha: 0.4),
              ),
        ),
      ],
    );
  }
}

// ─── Animated sound-wave indicator shown while listening ──────────────────────
class _SoundWaveIndicator extends StatefulWidget {
  const _SoundWaveIndicator();

  @override
  State<_SoundWaveIndicator> createState() => _SoundWaveIndicatorState();
}

class _SoundWaveIndicatorState extends State<_SoundWaveIndicator>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1200))
      ..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, __) {
        return Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(5, (i) {
            final t = (_ctrl.value + i * 0.2) % 1.0;
            final h = 6.0 + 18.0 * math.sin(t * math.pi);
            return Container(
              width: 4,
              height: h,
              margin: const EdgeInsets.symmetric(horizontal: 3),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.7),
                borderRadius: BorderRadius.circular(2),
              ),
            );
          }),
        );
      },
    );
  }
}

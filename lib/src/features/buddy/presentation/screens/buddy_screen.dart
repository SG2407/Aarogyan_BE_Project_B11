import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:record/record.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:math' as math;
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
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const Spacer(),
              Center(child: _OrbzAvatar(phase: s.phase)),
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
class _OrbzAvatar extends StatefulWidget {
  final BuddyPhase phase;
  const _OrbzAvatar({required this.phase});

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

  _OrbPainter({
    required this.phase,
    required this.breathT,
    required this.rippleT,
    required this.glowT,
    required this.ringT,
    required this.innerT,
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
    final scale = phase == BuddyPhase.idle ? 1.0 + breathT * 0.08 : 1.0;
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

  void _drawOuterAura(
      Canvas canvas, Offset c, double r, List<Color> clrs) {
    final auraR = r * 2.1;
    final alpha = phase == BuddyPhase.idle
        ? 0.07 + breathT * 0.05
        : 0.12 + glowT * 0.08;
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

  void _drawRipples(
      Canvas canvas, Offset c, double r, List<Color> clrs) {
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

  void _drawEnergyRings(
      Canvas canvas, Offset c, double r, List<Color> clrs) {
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

  void _drawCoreOrb(
      Canvas canvas, Offset c, double r, List<Color> clrs) {
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

  void _drawEdgeGlow(
      Canvas canvas, Offset c, double r, List<Color> clrs) {
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
        crossAxisAlignment: CrossAxisAlignment.center,
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
        crossAxisAlignment: CrossAxisAlignment.center,
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
        crossAxisAlignment: CrossAxisAlignment.center,
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
        crossAxisAlignment: CrossAxisAlignment.center,
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

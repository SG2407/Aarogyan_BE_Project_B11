import 'dart:math' as math;
import 'package:flutter/material.dart';

// Visual-only state enum used to drive the Orb visuals.
// Map from BuddyPhase using _toConvState() in buddy_screen.dart.
enum ConversationState {
  idle,
  listening,
  processing,
  thinking,
  speaking,
}

class OrbWidget extends StatefulWidget {
  final ConversationState state;
  final double size;

  const OrbWidget({super.key, required this.state, this.size = 260});

  @override
  State<OrbWidget> createState() => _OrbWidgetState();
}

class _OrbWidgetState extends State<OrbWidget> with TickerProviderStateMixin {
  late AnimationController _breatheCtrl;
  late Animation<double> _breatheAnim;
  late AnimationController _rotateCtrl;
  late Animation<double> _rotateAnim;
  late AnimationController _rotate2Ctrl;
  late Animation<double> _rotate2Anim;
  late AnimationController _rippleCtrl;
  late Animation<double> _rippleAnim;
  late Animation<double> _rippleOpacity;
  late AnimationController _thinkCtrl;
  late Animation<double> _thinkAnim;
  late AnimationController _speakCtrl;
  late Animation<double> _speakAnim;
  late AnimationController _colorCtrl;
  late Animation<double> _colorAnim;

  ConversationState _prevState = ConversationState.idle;

  @override
  void initState() {
    super.initState();

    _breatheCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3000),
    )..repeat(reverse: true);
    _breatheAnim = CurvedAnimation(
      parent: _breatheCtrl,
      curve: Curves.easeInOutSine,
    );

    _rotateCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 8000),
    )..repeat();
    _rotateAnim =
        Tween<double>(begin: 0, end: 2 * math.pi).animate(_rotateCtrl);

    _rotate2Ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 12000),
    )..repeat();
    _rotate2Anim =
        Tween<double>(begin: 2 * math.pi, end: 0).animate(_rotate2Ctrl);

    _rippleCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    )..repeat();
    _rippleAnim = Tween<double>(begin: 0.7, end: 1.4).animate(
        CurvedAnimation(parent: _rippleCtrl, curve: Curves.easeOut));
    _rippleOpacity = Tween<double>(begin: 0.6, end: 0.0).animate(
        CurvedAnimation(parent: _rippleCtrl, curve: Curves.easeOut));

    _thinkCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();
    _thinkAnim =
        Tween<double>(begin: 0, end: 2 * math.pi).animate(_thinkCtrl);

    _speakCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    )..repeat(reverse: true);
    _speakAnim = CurvedAnimation(
      parent: _speakCtrl,
      curve: Curves.easeInOutSine,
    );

    _colorCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );
    _colorAnim =
        CurvedAnimation(parent: _colorCtrl, curve: Curves.easeInOut);
  }

  @override
  void didUpdateWidget(OrbWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.state != widget.state) {
      _prevState = oldWidget.state;
      _colorCtrl.forward(from: 0);

      switch (widget.state) {
        case ConversationState.idle:
          _breatheCtrl.duration = const Duration(milliseconds: 3500);
          _rotateCtrl.duration = const Duration(milliseconds: 10000);
          break;
        case ConversationState.listening:
          _breatheCtrl.duration = const Duration(milliseconds: 2000);
          _rotateCtrl.duration = const Duration(milliseconds: 6000);
          break;
        case ConversationState.processing:
          _breatheCtrl.duration = const Duration(milliseconds: 1500);
          _rotateCtrl.duration = const Duration(milliseconds: 4000);
          break;
        case ConversationState.thinking:
          _breatheCtrl.duration = const Duration(milliseconds: 1000);
          _rotateCtrl.duration = const Duration(milliseconds: 2500);
          break;
        case ConversationState.speaking:
          _breatheCtrl.duration = const Duration(milliseconds: 800);
          _rotateCtrl.duration = const Duration(milliseconds: 3500);
          break;
      }
    }
  }

  @override
  void dispose() {
    _breatheCtrl.dispose();
    _rotateCtrl.dispose();
    _rotate2Ctrl.dispose();
    _rippleCtrl.dispose();
    _thinkCtrl.dispose();
    _speakCtrl.dispose();
    _colorCtrl.dispose();
    super.dispose();
  }

  List<Color> _colorsFor(ConversationState s) {
    switch (s) {
      case ConversationState.idle:
        return [
          const Color(0xFF1A6B5A),
          const Color(0xFF2DA882),
          const Color(0xFF00D2A0),
        ];
      case ConversationState.listening:
        return [
          const Color(0xFF00D2A0),
          const Color(0xFF00A8CC),
          const Color(0xFF0066FF),
        ];
      case ConversationState.processing:
        return [
          const Color(0xFFFFB347),
          const Color(0xFFFF6B6B),
          const Color(0xFFFF4499),
        ];
      case ConversationState.thinking:
        return [
          const Color(0xFFFF6B6B),
          const Color(0xFFFF4499),
          const Color(0xFF9B6DFF),
        ];
      case ConversationState.speaking:
        return [
          const Color(0xFF4ECDC4),
          const Color(0xFF44A8B3),
          const Color(0xFF6B73FF),
        ];
    }
  }

  List<Color> _lerpColorList(List<Color> a, List<Color> b, double t) {
    return List.generate(a.length, (i) => Color.lerp(a[i], b[i], t)!);
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([
        _breatheAnim,
        _rotateAnim,
        _rotate2Anim,
        _rippleAnim,
        _thinkAnim,
        _speakAnim,
        _colorAnim,
      ]),
      builder: (context, _) {
        final t = _colorAnim.value;
        final prevColors = _colorsFor(_prevState);
        final currColors = _colorsFor(widget.state);
        final colors = _lerpColorList(prevColors, currColors, t);

        final isListening = widget.state == ConversationState.listening;
        final isSpeaking = widget.state == ConversationState.speaking;
        final isThinking = widget.state == ConversationState.thinking ||
            widget.state == ConversationState.processing;

        double coreScale = 1.0 + _breatheAnim.value * 0.06;
        if (isSpeaking) {
          coreScale += _speakAnim.value * 0.10;
        }
        if (isThinking) {
          coreScale += math.sin(_thinkAnim.value * 3) * 0.04;
        }

        final sz = widget.size;

        return SizedBox(
          width: sz * 1.5,
          height: sz * 1.5,
          child: Stack(
            alignment: Alignment.center,
            children: [
              if (isListening) ...[
                _buildRipple(
                  sz,
                  colors[0].withOpacity(_rippleOpacity.value),
                  _rippleAnim.value,
                ),
                _buildRipple(
                  sz,
                  colors[1].withOpacity(_rippleOpacity.value * 0.5),
                  _rippleAnim.value * 1.15,
                ),
              ],
              // Outer halo ring — rotates clockwise
              Transform.rotate(
                angle: _rotateAnim.value,
                child: Container(
                  width: sz * 1.18,
                  height: sz * 1.18,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: SweepGradient(
                      colors: [
                        colors[0].withOpacity(0.0),
                        colors[0].withOpacity(0.45),
                        colors[1].withOpacity(0.35),
                        colors[2].withOpacity(0.20),
                        colors[0].withOpacity(0.0),
                      ],
                    ),
                  ),
                ),
              ),
              // Inner halo ring — rotates counter-clockwise
              Transform.rotate(
                angle: _rotate2Anim.value,
                child: Container(
                  width: sz * 1.06,
                  height: sz * 1.06,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: SweepGradient(
                      colors: [
                        colors[2].withOpacity(0.0),
                        colors[2].withOpacity(0.30),
                        colors[1].withOpacity(0.25),
                        colors[2].withOpacity(0.0),
                      ],
                    ),
                  ),
                ),
              ),
              if (isThinking)
                _buildOrbitDots(sz, colors, _thinkAnim.value),
              // Core orb
              Transform.scale(
                scale: coreScale,
                child: Container(
                  width: sz,
                  height: sz,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [
                        colors[0].withOpacity(0.9),
                        colors[1].withOpacity(0.75),
                        colors[2].withOpacity(0.6),
                        Colors.black.withOpacity(0.4),
                      ],
                      stops: const [0.0, 0.4, 0.75, 1.0],
                      center: const Alignment(-0.3, -0.3),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: colors[0].withOpacity(0.5),
                        blurRadius: sz * 0.35,
                        spreadRadius: sz * 0.05,
                      ),
                      BoxShadow(
                        color: colors[1].withOpacity(0.3),
                        blurRadius: sz * 0.55,
                        spreadRadius: sz * 0.02,
                      ),
                    ],
                  ),
                ),
              ),
              // Gloss highlight
              Transform.scale(
                scale: coreScale,
                child: Container(
                  width: sz * 0.38,
                  height: sz * 0.22,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(sz * 0.2),
                    gradient: RadialGradient(
                      colors: [
                        Colors.white.withOpacity(0.55),
                        Colors.white.withOpacity(0.0),
                      ],
                    ),
                  ),
                ),
              ),
              if (isSpeaking)
                _buildWaveform(sz, colors, _speakAnim.value),
            ],
          ),
        );
      },
    );
  }

  Widget _buildRipple(double sz, Color color, double scale) {
    return Container(
      width: sz * scale,
      height: sz * scale,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: color, width: 2),
      ),
    );
  }

  Widget _buildOrbitDots(double sz, List<Color> colors, double angle) {
    const dotCount = 5;
    return SizedBox(
      width: sz * 1.3,
      height: sz * 1.3,
      child: Stack(
        alignment: Alignment.center,
        children: List.generate(dotCount, (i) {
          final dotAngle = angle + (2 * math.pi * i / dotCount);
          final radius = sz * 0.52;
          final x = math.cos(dotAngle) * radius;
          final y = math.sin(dotAngle) * radius;
          final dotSize = sz * (0.048 + 0.016 * math.sin(dotAngle * 2));
          return Transform.translate(
            offset: Offset(x, y),
            child: Container(
              width: dotSize,
              height: dotSize,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color:
                    colors[i % colors.length].withOpacity(0.85),
                boxShadow: [
                  BoxShadow(
                    color: colors[i % colors.length].withOpacity(0.5),
                    blurRadius: dotSize * 1.5,
                  ),
                ],
              ),
            ),
          );
        }),
      ),
    );
  }

  Widget _buildWaveform(double sz, List<Color> colors, double pulse) {
    const barCount = 7;
    final heights = List.generate(barCount, (i) {
      final phase = i / barCount * math.pi * 2;
      return 0.3 +
          0.7 *
              math
                  .pow(math.sin(phase + pulse * math.pi), 2)
                  .abs()
                  .toDouble();
    });

    return SizedBox(
      width: sz * 0.55,
      height: sz * 0.35,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: List.generate(barCount, (i) {
          return AnimatedContainer(
            duration: const Duration(milliseconds: 80),
            width: sz * 0.035,
            height: sz * 0.25 * heights[i],
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(sz * 0.02),
              color: Colors.white.withOpacity(0.75),
              boxShadow: [
                BoxShadow(
                    color: colors[0].withOpacity(0.4), blurRadius: 4),
              ],
            ),
          );
        }),
      ),
    );
  }
}

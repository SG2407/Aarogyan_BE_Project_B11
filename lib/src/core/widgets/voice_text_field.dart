import 'package:flutter/material.dart';
import 'package:speech_to_text/speech_to_text.dart';
import '../theme/app_theme.dart';

/// A TextFormField with a built-in mic button for voice input.
/// Tap the mic to start dictating; tap again (or wait for a pause) to stop.
/// Recognised text is appended to [controller].
class VoiceTextField extends StatefulWidget {
  final TextEditingController controller;
  final String? hintText;
  final String? labelText;
  final int maxLines;

  const VoiceTextField({
    super.key,
    required this.controller,
    this.hintText,
    this.labelText,
    this.maxLines = 1,
  });

  @override
  State<VoiceTextField> createState() => _VoiceTextFieldState();
}

class _VoiceTextFieldState extends State<VoiceTextField>
    with SingleTickerProviderStateMixin {
  final SpeechToText _speech = SpeechToText();
  bool _listening = false;
  late AnimationController _pulseCtrl;
  late Animation<double> _pulseAnim;

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    )..repeat(reverse: true);
    _pulseAnim = Tween<double>(begin: 0.85, end: 1.15).animate(
      CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut),
    );
    _pulseCtrl.stop();
  }

  @override
  void dispose() {
    _speech.stop();
    _pulseCtrl.dispose();
    super.dispose();
  }

  Future<void> _toggle() async {
    if (_listening) {
      await _speech.stop();
      _pulseCtrl.stop();
      setState(() => _listening = false);
      return;
    }

    final available = await _speech.initialize(
      onError: (_) {
        _pulseCtrl.stop();
        if (mounted) setState(() => _listening = false);
      },
      onStatus: (status) {
        if (status == 'done' || status == 'notListening') {
          _pulseCtrl.stop();
          if (mounted) setState(() => _listening = false);
        }
      },
    );

    if (!available) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
                'Speech recognition not available on this device.'),
          ),
        );
      }
      return;
    }

    setState(() => _listening = true);
    _pulseCtrl.repeat(reverse: true);

    await _speech.listen(
      onResult: (result) {
        if (result.finalResult && result.recognizedWords.isNotEmpty) {
          final current = widget.controller.text.trimRight();
          widget.controller.text = current.isEmpty
              ? result.recognizedWords
              : '$current ${result.recognizedWords}';
          widget.controller.selection = TextSelection.collapsed(
            offset: widget.controller.text.length,
          );
        }
      },
      listenFor: const Duration(seconds: 60),
      pauseFor: const Duration(seconds: 3),
      cancelOnError: true,
    );
  }

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: widget.controller,
      maxLines: widget.maxLines,
      decoration: InputDecoration(
        hintText: widget.hintText,
        labelText: widget.labelText,
        suffixIcon: Padding(
          padding: const EdgeInsets.only(right: 4),
          child: _listening
              ? ScaleTransition(
                  scale: _pulseAnim,
                  child: IconButton(
                    tooltip: 'Stop recording',
                    onPressed: _toggle,
                    icon: const Icon(Icons.mic_rounded, color: Colors.red),
                  ),
                )
              : IconButton(
                  tooltip: 'Voice input',
                  onPressed: _toggle,
                  icon: const Icon(Icons.mic_none_rounded,
                      color: AppColors.primary),
                ),
        ),
      ),
    );
  }
}

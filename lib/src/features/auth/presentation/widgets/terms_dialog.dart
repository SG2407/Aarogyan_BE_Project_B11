import 'dart:async';
import 'package:flutter/material.dart';
import '../../../../core/theme/app_theme.dart';

/// Shows the Terms & Conditions dialog.
/// Returns the typed signature string on acceptance, or null if dismissed.
Future<String?> showTermsDialog(BuildContext context) {
  return showDialog<String>(
    context: context,
    barrierDismissible: false,
    builder: (_) => const _TermsDialog(),
  );
}

class _TermsDialog extends StatefulWidget {
  const _TermsDialog();

  @override
  State<_TermsDialog> createState() => _TermsDialogState();
}

class _TermsDialogState extends State<_TermsDialog> {
  final _scrollCtrl = ScrollController();
  final _signatureCtrl = TextEditingController();

  // Signature field is enabled only after user scrolls to bottom AND 15s pass
  bool _scrolledToBottom = false;
  bool _timerDone = false;
  int _secondsLeft = 15;
  Timer? _timer;

  bool get _signatureEnabled => _scrolledToBottom && _timerDone;

  @override
  void initState() {
    super.initState();
    _scrollCtrl.addListener(_onScroll);
    _startTimer();
  }

  void _startTimer() {
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      setState(() {
        if (_secondsLeft > 1) {
          _secondsLeft--;
        } else {
          _secondsLeft = 0;
          _timerDone = true;
          t.cancel();
        }
      });
    });
  }

  void _onScroll() {
    if (_scrolledToBottom) return;
    final pos = _scrollCtrl.position;
    // Consider "at bottom" when within 40px of the max extent
    if (pos.pixels >= pos.maxScrollExtent - 40) {
      setState(() => _scrolledToBottom = true);
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _scrollCtrl.dispose();
    _signatureCtrl.dispose();
    super.dispose();
  }

  void _accept() {
    final sig = _signatureCtrl.text.trim();
    if (sig.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Please type your full name as signature')),
      );
      return;
    }
    Navigator.of(context).pop(sig);
  }

  @override
  Widget build(BuildContext context) {
    const bgColor =
        Color(0xFFA8D5C2); // saturated mint green — dialog & section bg
    const signatureFillColor =
        Color(0xFF7BBFA6); // deeper green for enabled signature field

    // Return a raw Material(transparent) instead of Dialog to bypass Flutter M3's
    // surfaceContainerHigh override which forces the dialog surface to white.
    return Material(
      type: MaterialType.transparency,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 32),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.85,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // ── Header ──────────────────────────────────────────────
                  Container(
                    width: double.infinity,
                    color: AppColors.primary,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 20, vertical: 16),
                    child: const Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.verified_user_rounded,
                                color: Colors.white70, size: 20),
                            SizedBox(width: 8),
                            Text(
                              'Terms & Conditions',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                        SizedBox(height: 4),
                        Text(
                          'Please read carefully before signing',
                          style: TextStyle(color: Colors.white70, fontSize: 13),
                        ),
                      ],
                    ),
                  ),

                  // ── Scrollable T&C content ───────────────────────────────
                  Flexible(
                    child: Container(
                      color: bgColor,
                      child: SingleChildScrollView(
                        controller: _scrollCtrl,
                        padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
                        child: const _TermsContent(),
                      ),
                    ),
                  ),

                  // ── Signature section ─────────────────────────────────
                  Container(
                    width: double.infinity,
                    color: bgColor,
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Divider(color: Color(0xFFB2DFDB), thickness: 1),
                        const SizedBox(height: 8),

                        _StatusHint(
                          scrolledToBottom: _scrolledToBottom,
                          timerDone: _timerDone,
                          secondsLeft: _secondsLeft,
                          signatureEnabled: _signatureEnabled,
                        ),
                        const SizedBox(height: 10),

                        // Wrap TextField in Theme to override global white fillColor
                        Theme(
                          data: Theme.of(context).copyWith(
                            inputDecorationTheme: InputDecorationTheme(
                              filled: true,
                              fillColor: _signatureEnabled
                                  ? signatureFillColor
                                  : Colors.grey.shade200,
                              contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 16, vertical: 14),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10),
                                borderSide: const BorderSide(
                                    color: AppColors.primary, width: 1.4),
                              ),
                              disabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10),
                                borderSide:
                                    BorderSide(color: Colors.grey.shade400),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10),
                                borderSide: const BorderSide(
                                    color: AppColors.primary, width: 2),
                              ),
                            ),
                          ),
                          child: TextField(
                            controller: _signatureCtrl,
                            enabled: _signatureEnabled,
                            style: const TextStyle(
                              color: AppColors.textPrimary,
                              fontWeight: FontWeight.w500,
                            ),
                            decoration: InputDecoration(
                              labelText: 'Type your full name as signature',
                              labelStyle: TextStyle(
                                color: _signatureEnabled
                                    ? AppColors.primary
                                    : Colors.grey.shade500,
                              ),
                              prefixIcon: Icon(
                                Icons.draw_outlined,
                                color: _signatureEnabled
                                    ? AppColors.primary
                                    : Colors.grey.shade400,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 14),

                        Row(
                          children: [
                            Expanded(
                              child: ElevatedButton(
                                onPressed: () =>
                                    Navigator.of(context).pop(null),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: AppColors.error,
                                  foregroundColor: Colors.white,
                                  shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(10)),
                                  minimumSize: const Size(0, 44),
                                  elevation: 0,
                                ),
                                child: const Text('Decline'),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: ElevatedButton(
                                onPressed: _signatureEnabled ? _accept : null,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: AppColors.primary,
                                  disabledBackgroundColor: Colors.grey.shade400,
                                  foregroundColor: Colors.white,
                                  shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(10)),
                                  minimumSize: const Size(0, 44),
                                ),
                                child: const Text('I Accept'),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _StatusHint extends StatelessWidget {
  final bool scrolledToBottom;
  final bool timerDone;
  final bool signatureEnabled;
  final int secondsLeft;

  const _StatusHint({
    required this.scrolledToBottom,
    required this.timerDone,
    required this.signatureEnabled,
    required this.secondsLeft,
  });

  @override
  Widget build(BuildContext context) {
    if (signatureEnabled) {
      return Row(
        children: const [
          Icon(Icons.check_circle_rounded, color: AppColors.primary, size: 16),
          SizedBox(width: 6),
          Text(
            'You may now sign below',
            style: TextStyle(
              color: AppColors.primary,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      );
    }

    final List<Widget> hints = [];

    if (!scrolledToBottom) {
      hints.add(Row(
        children: const [
          Icon(Icons.arrow_downward_rounded, size: 14, color: AppColors.error),
          SizedBox(width: 4),
          Text('Scroll to the bottom to continue',
              style: TextStyle(fontSize: 12, color: AppColors.error)),
        ],
      ));
    }

    if (!timerDone) {
      if (hints.isNotEmpty) hints.add(const SizedBox(height: 4));
      hints.add(Row(
        children: [
          const Icon(Icons.timer_outlined, size: 14, color: AppColors.error),
          const SizedBox(width: 4),
          Text(
            'Please wait $secondsLeft second${secondsLeft == 1 ? '' : 's'}',
            style: const TextStyle(fontSize: 12, color: AppColors.error),
          ),
        ],
      ));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: hints,
    );
  }
}

/// The actual terms and conditions text content.
class _TermsContent extends StatelessWidget {
  const _TermsContent();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: const [
        _Section(
          title: '1. About Aarogyan',
          body:
              'Aarogyan is a personal health management application designed to help you '
              'track your medical consultations, monitor your emotional well-being, and '
              'interact with an AI-powered medical assistant. By creating an account, '
              'you agree to these Terms and Conditions in full.',
        ),
        _Section(
          title: '2. Not a Medical Service',
          body:
              'Aarogyan is NOT a licensed medical service, hospital, clinic, or healthcare '
              'provider. The AI Medical Assistant provides general health information only '
              'and does NOT constitute medical advice, diagnosis, or treatment. '
              'Always consult a qualified, licensed healthcare professional for any '
              'medical concerns. In an emergency, call your local emergency services immediately.',
        ),
        _Section(
          title: '3. AI-Generated Content Disclaimer',
          body:
              'Responses from the AI Medical Assistant are generated using large language '
              'models and retrieval from medical reference materials. These responses:\n'
              '  • May contain inaccuracies or be out of date\n'
              '  • Are for informational and educational purposes only\n'
              '  • Must not be used as a substitute for professional clinical judgment\n'
              '  • Are not reviewed or approved by any medical authority\n\n'
              'AI session summaries in exported PDFs are auto-generated and carry the '
              'same disclaimer. Do not share them as official medical records.',
        ),
        _Section(
          title: '4. Health Data & Privacy',
          body:
              'You may store personal health information including symptoms, diagnoses, '
              'medications, doctor notes, and uploaded medical documents. By using '
              'Aarogyan you consent to:\n'
              '  • Storage of your health data on secure cloud servers\n'
              '  • Processing of your data to provide app functionality (AI responses, '
              'PDF generation, emotional analysis)\n'
              '  • Your data being retained until you delete your account\n\n'
              'We do NOT sell, share, or disclose your personal health data to third '
              'parties except as required by law. AI processing is conducted via '
              'third-party API providers under data processing agreements.',
        ),
        _Section(
          title: '5. Emotional Well-Being Feature',
          body:
              'The Emotional Buddy feature analyses your speech and text to provide '
              'empathetic responses and mood tracking. This feature:\n'
              '  • Is not a substitute for mental health therapy or counselling\n'
              '  • Is not monitored by any mental health professional\n'
              '  • Should not be used in crisis situations\n\n'
              'If you are experiencing a mental health crisis or having thoughts of '
              'self-harm, please contact a licensed mental health professional or '
              'crisis helpline immediately.',
        ),
        _Section(
          title: '6. Uploaded Documents',
          body:
              'You may upload medical documents (prescriptions, test reports, etc.) '
              'up to 2 MB per file. You confirm that:\n'
              '  • You own or have the right to upload any document you submit\n'
              '  • Documents may be processed using OCR and AI analysis\n'
              '  • Sensitive documents are stored securely and not shared with others',
        ),
        _Section(
          title: '7. User Responsibilities',
          body: 'You agree to:\n'
              '  • Provide accurate registration information\n'
              '  • Keep your account credentials secure and confidential\n'
              '  • Not use the app for any unlawful or harmful purpose\n'
              '  • Not attempt to reverse-engineer, abuse, or disrupt the service\n'
              '  • Not input false, misleading, or harmful content',
        ),
        _Section(
          title: '8. Account Deletion',
          body:
              'You may delete your account at any time. Upon deletion, your personal '
              'data, health records, consultation history, and uploaded documents '
              'will be permanently removed from our servers.',
        ),
        _Section(
          title: '9. Limitation of Liability',
          body:
              'To the maximum extent permitted by law, Aarogyan and its developers '
              'shall not be liable for any direct, indirect, incidental, or '
              'consequential damages arising from your use of the app, including '
              'but not limited to: reliance on AI-generated health information, '
              'loss of health data, or decisions made based on app content.',
        ),
        _Section(
          title: '10. Changes to Terms',
          body: 'We may update these Terms and Conditions from time to time. '
              'Material changes will be communicated through the app. Continued use '
              'of Aarogyan after changes constitutes acceptance of the updated terms.',
        ),
        _Section(
          title: '11. Contact',
          body:
              'For questions about these terms or your data, please contact the '
              'Aarogyan development team through the app\'s feedback channel.',
        ),
        SizedBox(height: 8),
        Text(
          'Version 1.0  ·  Effective: April 2026',
          style: TextStyle(
            fontSize: 11,
            color: Colors.grey,
            fontStyle: FontStyle.italic,
          ),
        ),
      ],
    );
  }
}

class _Section extends StatelessWidget {
  final String title;
  final String body;
  const _Section({required this.title, required this.body});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 14,
              color: AppColors.primary,
            ),
          ),
          const SizedBox(height: 6),
          Text(body,
              style: const TextStyle(
                  fontSize: 13, height: 1.5, color: AppColors.textPrimary)),
        ],
      ),
    );
  }
}

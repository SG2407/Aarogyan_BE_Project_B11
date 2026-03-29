import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import '../../../../core/theme/app_theme.dart';
import '../../../../core/l10n/app_strings.dart';
import '../../data/assistant_repository.dart';
import '../../../profile/data/profile_repository.dart';

const _sttLocaleMap = {
  'English': 'en-US',
  'Hindi': 'hi-IN',
  'Marathi': 'mr-IN',
};

// Per-conversation chat state: list of message maps
// Each message: {role, content, sources?}
class ChatNotifier
    extends AutoDisposeFamilyAsyncNotifier<List<Map<String, dynamic>>, String> {
  @override
  Future<List<Map<String, dynamic>>> build(String conversationId) async {
    final msgs =
        await ref.read(assistantRepositoryProvider).getMessages(conversationId);
    return msgs.cast<Map<String, dynamic>>();
  }

  Future<void> sendMessage(String text) async {
    final conversationId = arg;
    // Read preferred language from profile (fire-and-forget, default to English)
    String preferredLanguage = 'English';
    try {
      final profile = await ref.read(profileProvider.future);
      preferredLanguage = profile['preferred_language'] as String? ?? 'English';
    } catch (_) {}
    final current = state.valueOrNull ?? [];
    state = AsyncData([
      ...current,
      {'role': 'user', 'content': text}
    ]);
    try {
      final resp = await ref.read(assistantRepositoryProvider).sendMessage(
            conversationId: conversationId,
            message: text,
            preferredLanguage: preferredLanguage,
          );
      final sources = (resp['sources'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .where((s) => s.trim().isNotEmpty)
              .toList() ??
          [];
      state = AsyncData([
        ...state.valueOrNull ?? current,
        {
          'role': 'assistant',
          'content': resp['reply'] ?? resp['message'] ?? '',
          'sources': sources,
        },
      ]);
    } catch (e) {
      state = AsyncData(current);
      rethrow;
    }
  }
}

final chatNotifierProvider = AutoDisposeAsyncNotifierProviderFamily<
    ChatNotifier, List<Map<String, dynamic>>, String>(
  ChatNotifier.new,
);

class ChatScreen extends ConsumerStatefulWidget {
  final String conversationId;
  const ChatScreen({super.key, required this.conversationId});

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  final _msgCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();
  bool _sending = false;

  @override
  void dispose() {
    _msgCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.animateTo(
          _scrollCtrl.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _send() async {
    final text = _msgCtrl.text.trim();
    if (text.isEmpty || _sending) return;
    _msgCtrl.clear();
    setState(() => _sending = true);
    try {
      await ref
          .read(chatNotifierProvider(widget.conversationId).notifier)
          .sendMessage(text);
      _scrollToBottom();
    } catch (e) {
      if (mounted) {
        final msg =
            e.toString().contains('429') || e.toString().contains('busy')
                ? 'AI is busy — please wait a moment and try again.'
                : 'Failed to send message. Please try again.';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(msg)),
        );
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final messagesAsync =
        ref.watch(chatNotifierProvider(widget.conversationId));
    final profileAsync = ref.watch(profileProvider);
    final lang = profileAsync.valueOrNull?['preferred_language'] as String? ?? 'English';
    return Scaffold(
      appBar: AppBar(
        title: Text(appStr(lang, 'assistant_title')),
        elevation: 0,
      ),
      body: Column(
        children: [
          Expanded(
            child: messagesAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('Error: $e')),
              data: (messages) {
                if (messages.isEmpty) {
                  return _WelcomeBanner(lang: lang);
                }
                WidgetsBinding.instance
                    .addPostFrameCallback((_) => _scrollToBottom());
                return ListView.builder(
                  controller: _scrollCtrl,
                  padding:
                      const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
                  itemCount: messages.length,
                  itemBuilder: (_, i) {
                    final msg = messages[i];
                    final sources = (msg['sources'] as List<dynamic>?)
                            ?.map((e) => e.toString())
                            .toList() ??
                        [];
                    return _MessageBubble(
                      role: msg['role'] ?? 'user',
                      content: msg['content'] ?? '',
                      sources: sources,
                    );
                  },
                );
              },
            ),
          ),
          _InputBar(
            controller: _msgCtrl,
            sending: _sending,
            onSend: _send,
            hintText: appStr(lang, 'assistant_hint'),
            lang: lang,
          ),
        ],
      ),
    );
  }
}

class _WelcomeBanner extends StatelessWidget {
  final String lang;
  const _WelcomeBanner({this.lang = 'English'});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.health_and_safety_rounded,
                size: 56, color: AppColors.primary),
            const SizedBox(height: 16),
            Text(appStr(lang, 'welcome_title'),
                style: Theme.of(context).textTheme.headlineSmall,
                textAlign: TextAlign.center),
            const SizedBox(height: 8),
            Text(
              appStr(lang, 'welcome_subtitle'),
              style: Theme.of(context).textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  final String role;
  final String content;
  final List<String> sources;
  const _MessageBubble(
      {required this.role, required this.content, this.sources = const []});

  @override
  Widget build(BuildContext context) {
    final isUser = role == 'user';
    final hasSources = !isUser && sources.isNotEmpty;

    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Column(
        crossAxisAlignment:
            isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          Container(
            constraints: BoxConstraints(
              maxWidth: MediaQuery.of(context).size.width * 0.78,
            ),
            margin: EdgeInsets.only(
              top: 6,
              bottom: hasSources ? 2 : 6,
            ),
            padding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: isUser
                  ? AppColors.primary
                  : Theme.of(context).colorScheme.surface,
              borderRadius: BorderRadius.only(
                topLeft: const Radius.circular(20),
                topRight: const Radius.circular(20),
                bottomLeft: Radius.circular(isUser ? 20 : 4),
                bottomRight: Radius.circular(isUser ? 4 : 20),
              ),
            ),
            child: Text(
              content,
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: isUser
                        ? Colors.white
                        : Theme.of(context).colorScheme.onSurface,
                  ),
            ),
          ),
          if (hasSources)
            Padding(
              padding: const EdgeInsets.only(left: 4, bottom: 6),
              child: _SourcesButton(sources: sources),
            ),
        ],
      ),
    );
  }
}

class _SourcesButton extends StatelessWidget {
  final List<String> sources;
  const _SourcesButton({required this.sources});

  void _showSources(BuildContext context) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Row(
              children: [
                const Icon(Icons.menu_book_rounded,
                    size: 18, color: AppColors.primary),
                const SizedBox(width: 8),
                Text(
                  'Sources',
                  style: Theme.of(ctx).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: AppColors.primary,
                      ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            ...sources.asMap().entries.map(
                  (e) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${e.key + 1}.',
                          style:
                              Theme.of(ctx).textTheme.bodySmall?.copyWith(
                                    fontWeight: FontWeight.w600,
                                    color: AppColors.primary,
                                  ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            e.value,
                            style: Theme.of(ctx).textTheme.bodySmall,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => _showSources(context),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: AppColors.primary.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: AppColors.primary.withValues(alpha: 0.2),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.menu_book_rounded,
                size: 12,
                color: AppColors.primary.withValues(alpha: 0.8)),
            const SizedBox(width: 4),
            Text(
              'Sources',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: AppColors.primary.withValues(alpha: 0.8),
                    fontWeight: FontWeight.w600,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}

class _InputBar extends StatefulWidget {
  final TextEditingController controller;
  final bool sending;
  final VoidCallback onSend;
  final String hintText;
  final String lang;
  const _InputBar({
    required this.controller,
    required this.sending,
    required this.onSend,
    this.hintText = 'Ask a health question…',
    this.lang = 'English',
  });

  @override
  State<_InputBar> createState() => _InputBarState();
}

class _InputBarState extends State<_InputBar> {
  final _speech = stt.SpeechToText();
  bool _speechAvailable = false;
  bool _listening = false;

  @override
  void initState() {
    super.initState();
    _initSpeech();
  }

  Future<void> _initSpeech() async {
    final available = await _speech.initialize(
      onError: (_) => _setListening(false),
      onStatus: (status) {
        if (status == 'done' || status == 'notListening') {
          _setListening(false);
        }
      },
    );
    if (mounted) setState(() => _speechAvailable = available);
  }

  void _setListening(bool val) {
    if (mounted) setState(() => _listening = val);
  }

  Future<void> _toggleListening() async {
    if (_listening) {
      await _speech.stop();
      _setListening(false);
      return;
    }
    if (!_speechAvailable) return;
    final locale = _sttLocaleMap[widget.lang] ?? 'en-US';
    _setListening(true);
    await _speech.listen(
      onResult: (result) {
        if (result.recognizedWords.isNotEmpty) {
          widget.controller.text = result.recognizedWords;
          widget.controller.selection = TextSelection.fromPosition(
            TextPosition(offset: widget.controller.text.length),
          );
        }
      },
      listenFor: const Duration(seconds: 60),
      pauseFor: const Duration(seconds: 5),
      localeId: locale,
      listenOptions: stt.SpeechListenOptions(
        partialResults: true,
        cancelOnError: true,
      ),
    );
  }

  @override
  void dispose() {
    _speech.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 8, 8, 16),
        color: Theme.of(context).colorScheme.surface,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            // Mic button
            Padding(
              padding: const EdgeInsets.only(right: 8, bottom: 2),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _listening
                      ? AppColors.error.withValues(alpha: 0.12)
                      : AppColors.primary.withValues(alpha: 0.1),
                ),
                child: IconButton(
                  icon: Icon(
                    _listening ? Icons.stop_rounded : Icons.mic_rounded,
                    color: _listening ? AppColors.error : AppColors.primary,
                  ),
                  onPressed: _speechAvailable ? _toggleListening : null,
                  tooltip: appStr(widget.lang, _listening ? 'tap_interrupt' : 'start_conversation'),
                ),
              ),
            ),
            Expanded(
              child: TextField(
                controller: widget.controller,
                maxLines: null,
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(
                  hintText: _listening
                      ? appStr(widget.lang, 'listening')
                      : widget.hintText,
                  filled: true,
                  fillColor: Theme.of(context).scaffoldBackgroundColor,
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(24),
                    borderSide: BorderSide.none,
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(24),
                    borderSide: _listening
                        ? BorderSide(
                            color: AppColors.error.withValues(alpha: 0.5),
                            width: 1.5,
                          )
                        : BorderSide.none,
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(24),
                    borderSide: _listening
                        ? BorderSide(
                            color: AppColors.error.withValues(alpha: 0.7),
                            width: 1.5,
                          )
                        : const BorderSide(
                            color: AppColors.primary,
                            width: 1.5,
                          ),
                  ),
                ),
                onSubmitted: (_) => widget.onSend(),
              ),
            ),
            const SizedBox(width: 8),
            Padding(
              padding: const EdgeInsets.only(bottom: 2),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                child: CircleAvatar(
                  radius: 24,
                  backgroundColor: AppColors.primary,
                  child: widget.sending
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white),
                        )
                      : IconButton(
                          icon: const Icon(Icons.send_rounded,
                              color: Colors.white),
                          onPressed: widget.onSend,
                        ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}


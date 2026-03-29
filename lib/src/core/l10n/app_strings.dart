/// Minimal in-app string table for the three supported languages.
/// Keys are plain English identifiers; values are the translated UI strings.
/// Usage:  appStr(preferredLang, 'buddy_title')
const Map<String, Map<String, String>> _strings = {
  // ── English ────────────────────────────────────────────────────────────────
  'English': {
    // Buddy screen
    'buddy_title': 'Orbz — Emotional Buddy',
    'end': 'End',
    'tap_to_begin': 'Tap below to begin',
    'starting': 'Starting…',
    'listening': 'Listening…',
    'thinking': 'Orbz is thinking…',
    'speaking': 'Orbz is speaking…',
    'speak_freely': 'Speak freely — Orbz will respond when you pause',
    'tap_to_interrupt_caption': 'Tap the mic icon below to interrupt',
    'start_conversation': 'Start Conversation',
    'one_tap_hint': 'One tap — then just speak naturally',
    'pause_hint': 'Pause speaking for 2 s to send',
    'tap_interrupt': 'Tap to interrupt',
    'service_starting': 'Service is starting up — please try again in a moment.',
    // Assistant screen
    'assistant_title': 'Health Assistant',
    'assistant_hint': 'Ask a health question…',
    'welcome_title': 'Ask me anything about your health',
    'welcome_subtitle':
        "I'll use your health profile to give you personalised, accurate information.",
  },

  // ── हिंदी — Hindi ──────────────────────────────────────────────────────────
  'Hindi': {
    // Buddy screen
    'buddy_title': 'ऑर्ब्ज़ — भावनात्मक साथी',
    'end': 'समाप्त',
    'tap_to_begin': 'शुरू करने के लिए नीचे दबाएं',
    'starting': 'शुरू हो रहा है…',
    'listening': 'सुन रहा है…',
    'thinking': 'ऑर्ब्ज़ सोच रहा है…',
    'speaking': 'ऑर्ब्ज़ बोल रहा है…',
    'speak_freely': 'खुलकर बोलें — रुकने पर ऑर्ब्ज़ जवाब देगा',
    'tap_to_interrupt_caption': 'बाधित करने के लिए नीचे माइक दबाएं',
    'start_conversation': 'बातचीत शुरू करें',
    'one_tap_hint': 'एक बार दबाएं — फिर स्वाभाविक रूप से बोलें',
    'pause_hint': 'भेजने के लिए 2 सेकंड रुकें',
    'tap_interrupt': 'बाधित करने के लिए दबाएं',
    'service_starting': 'सेवा शुरू हो रही है — कृपया थोड़ी देर बाद पुनः प्रयास करें।',
    // Assistant screen
    'assistant_title': 'स्वास्थ्य सहायक',
    'assistant_hint': 'अपना स्वास्थ्य प्रश्न लिखें…',
    'welcome_title': 'अपने स्वास्थ्य के बारे में कुछ भी पूछें',
    'welcome_subtitle':
        'मैं आपकी स्वास्थ्य प्रोफ़ाइल के आधार पर आपको व्यक्तिगत जानकारी दूंगा।',
  },

  // ── मराठी — Marathi ────────────────────────────────────────────────────────
  'Marathi': {
    // Buddy screen
    'buddy_title': 'ऑर्ब्ज — भावनिक मित्र',
    'end': 'संपवा',
    'tap_to_begin': 'सुरू करण्यासाठी खाली दाबा',
    'starting': 'सुरू होत आहे…',
    'listening': 'ऐकत आहे…',
    'thinking': 'ऑर्ब्ज विचार करत आहे…',
    'speaking': 'ऑर्ब्ज बोलत आहे…',
    'speak_freely': 'मोकळेपणाने बोला — थांबल्यावर ऑर्ब्ज उत्तर देईल',
    'tap_to_interrupt_caption': 'व्यत्यय आणण्यासाठी खाली माइक दाबा',
    'start_conversation': 'संवाद सुरू करा',
    'one_tap_hint': 'एकदा दाबा — मग नैसर्गिकपणे बोला',
    'pause_hint': 'पाठवण्यासाठी 2 सेकंड थांबा',
    'tap_interrupt': 'व्यत्यय आणण्यासाठी दाबा',
    'service_starting': 'सेवा सुरू होत आहे — कृपया थोड़ा वेळ थांबून पुन्हा प्रयत्न करा।',
    // Assistant screen
    'assistant_title': 'आरोग्य सहाय्यक',
    'assistant_hint': 'तुमचा आरोग्य प्रश्न लिहा…',
    'welcome_title': 'तुमच्या आरोग्याबद्दल काहीही विचारा',
    'welcome_subtitle':
        'मी तुमच्या आरोग्य प्रोफाइलचा वापर करून तुम्हाला वैयक्तिक माहिती देईन।',
  },
};

/// Returns the translated string for [key] in [lang].
/// Falls back to English when the language or key is not found.
String appStr(String lang, String key) =>
    _strings[lang]?[key] ?? _strings['English']![key] ?? key;

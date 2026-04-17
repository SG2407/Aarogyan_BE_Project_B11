import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tutorial_coach_mark/tutorial_coach_mark.dart';
import 'guided_tour_provider.dart';
import 'screen_keys.dart';
import 'tour_service.dart';

/// A zero-size widget that detects when its [phase] becomes the active
/// tour phase and triggers the corresponding screen tour.
///
/// Drop one instance into each screen's widget tree.
class TourTrigger extends ConsumerStatefulWidget {
  final TourPhase phase;

  const TourTrigger({super.key, required this.phase});

  @override
  ConsumerState<TourTrigger> createState() => _TourTriggerState();
}

class _TourTriggerState extends ConsumerState<TourTrigger> {
  bool _triggered = false;

  @override
  Widget build(BuildContext context) {
    final tourState = ref.watch(guidedTourProvider);

    if (!_triggered &&
        tourState.isActive &&
        tourState.currentPhase == widget.phase &&
        tourState.pendingTourStart) {
      _triggered = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          ref.read(guidedTourProvider.notifier).markTourStarted();
          _startTourForPhase(context, ref, widget.phase);
        }
      });
    }

    return const SizedBox.shrink();
  }

  void _startTourForPhase(BuildContext context, WidgetRef ref, TourPhase phase) {
    final steps = _buildStepsForPhase(ref, phase);
    TourService.showTour(
      context: context,
      ref: ref,
      steps: steps,
      phase: phase,
    );
  }

  List<TourStep> _buildStepsForPhase(WidgetRef ref, TourPhase phase) {
    final lang = ref.read(tourLanguageProvider);
    switch (phase) {
      case TourPhase.home:
        return _homeSteps(ref, lang);
      case TourPhase.profile:
        return _profileSteps(ref, lang);
      case TourPhase.consultations:
        return _consultationsSteps(ref, lang);
      case TourPhase.assistant:
        return _assistantSteps(ref, lang);
      case TourPhase.documents:
        return _documentSteps(ref, lang);
      case TourPhase.buddy:
        return _buddySteps(ref, lang);
      case TourPhase.mentalHealth:
        return _mentalHealthSteps(ref, lang);
      default:
        return [];
    }
  }

  String _t(String lang, String en, String hi, String mr) {
    switch (lang) {
      case 'hi':
        return hi;
      case 'mr':
        return mr;
      default:
        return en;
    }
  }

  // ── Home screen steps ───────────────────────────────────────────────────────
  List<TourStep> _homeSteps(WidgetRef ref, String lang) {
    final keys = ref.read(homeScreenKeysProvider);
    final navKeys = ref.read(bottomNavKeysProvider);
    return [
      TourStep(
        key: keys.headerKey,
        title: 'Welcome to Aarogyan!',
        description:
            'This is your health dashboard. From here you can access all features of the app.',
        ttsText: _t(
          lang,
          'Welcome to Aarogyan! This is your health dashboard. From here you can access all the features of the app.',
          'आरोग्यन में आपका स्वागत है! यह आपका स्वास्थ्य डैशबोर्ड है। यहाँ से आप ऐप की सभी सुविधाएँ इस्तेमाल कर सकते हैं।',
          'आरोग्यनमध्ये आपले स्वागत आहे! हे तुमचे आरोग्य डॅशबोर्ड आहे. येथून तुम्ही ॲपची सर्व वैशिष्ट्ये वापरू शकता.',
        ),
        align: ContentAlign.bottom,
      ),
      TourStep(
        key: keys.askAiKey,
        title: 'Ask AI Health Questions',
        description:
            'Tap here to ask any health-related question. The AI uses your health profile to give personalised answers.',
        ttsText: _t(
          lang,
          'Tap here to ask any health related question. The AI uses your health profile to give personalized answers.',
          'कोई भी स्वास्थ्य संबंधी सवाल पूछने के लिए यहाँ टैप करें। AI आपकी स्वास्थ्य प्रोफ़ाइल के अनुसार जवाब देता है।',
          'कोणताही आरोग्य प्रश्न विचारण्यासाठी येथे टॅप करा. AI तुमच्या आरोग्य प्रोफाइलनुसार उत्तरे देतो.',
        ),
        align: ContentAlign.bottom,
      ),
      TourStep(
        key: keys.scanDocKey,
        title: 'Scan Medical Documents',
        description:
            'Tap here to scan prescriptions, test reports, or any medical document. The AI will explain it in simple words.',
        ttsText: _t(
          lang,
          'Tap here to scan prescriptions, test reports, or any medical document. The AI will explain it in simple words.',
          'प्रिस्क्रिप्शन, टेस्ट रिपोर्ट या कोई भी मेडिकल डॉक्यूमेंट स्कैन करने के लिए यहाँ टैप करें। AI इसे सरल शब्दों में समझाएगा।',
          'प्रिस्क्रिप्शन, चाचणी अहवाल किंवा कोणताही वैद्यकीय कागदपत्र स्कॅन करण्यासाठी येथे टॅप करा. AI ते सोप्या शब्दांत समजावून सांगेल.',
        ),
        align: ContentAlign.bottom,
      ),
      TourStep(
        key: keys.featureCardsKey,
        title: 'Explore Features',
        description:
            'These cards give you quick access to Consultation Tracker, Document Scanner, and Mental Health Tracker.',
        ttsText: _t(
          lang,
          'These cards give you quick access to the Consultation Tracker, Document Scanner, and Mental Health Tracker.',
          'ये कार्ड आपको कंसल्टेशन ट्रैकर, डॉक्यूमेंट स्कैनर और मेंटल हेल्थ ट्रैकर तक जल्दी पहुँचाते हैं।',
          'हे कार्ड तुम्हाला कन्सल्टेशन ट्रॅकर, डॉक्युमेंट स्कॅनर आणि मेंटल हेल्थ ट्रॅकरपर्यंत त्वरित प्रवेश देतात.',
        ),
        align: ContentAlign.top,
      ),
      TourStep(
        key: navKeys[0],
        title: 'Home Tab',
        description: 'This tab brings you back to the home dashboard.',
        ttsText: _t(
          lang,
          'This is the Home tab. It brings you back to the dashboard.',
          'यह होम टैब है। यह आपको डैशबोर्ड पर वापस लाता है।',
          'हा होम टॅब आहे. हे तुम्हाला डॅशबोर्डवर परत आणते.',
        ),
        align: ContentAlign.top,
        shape: ShapeLightFocus.Circle,
      ),
      TourStep(
        key: navKeys[1],
        title: 'Consultation Tracker',
        description:
            'Track your doctor visits, treatments, and medical sessions here.',
        ttsText: _t(
          lang,
          'This is the Consultation Tracker. Track your doctor visits, treatments, and medical sessions here.',
          'यह कंसल्टेशन ट्रैकर है। यहाँ अपने डॉक्टर विज़िट, इलाज और मेडिकल सेशन ट्रैक करें।',
          'हा कन्सल्टेशन ट्रॅकर आहे. येथे तुमच्या डॉक्टर भेटी, उपचार आणि वैद्यकीय सत्रे ट्रॅक करा.',
        ),
        align: ContentAlign.top,
        shape: ShapeLightFocus.Circle,
      ),
      TourStep(
        key: navKeys[2],
        title: 'AI Health Assistant',
        description:
            'Chat with the AI assistant about your health concerns.',
        ttsText: _t(
          lang,
          'This is the AI Health Assistant. Chat with the AI about your health concerns.',
          'यह AI हेल्थ असिस्टेंट है। अपनी स्वास्थ्य चिंताओं के बारे में AI से बात करें।',
          'हा AI हेल्थ असिस्टंट आहे. तुमच्या आरोग्य समस्यांबद्दल AI शी बोला.',
        ),
        align: ContentAlign.top,
        shape: ShapeLightFocus.Circle,
      ),
      TourStep(
        key: navKeys[3],
        title: 'Emotional Buddy (Orbz)',
        description:
            'Your voice-based emotional companion. Speak to Orbz for emotional support and mental health tracking.',
        ttsText: _t(
          lang,
          'This is Orbz, your Emotional Buddy. Speak to Orbz for emotional support and mental health tracking.',
          'यह ऑर्ब्ज़ है, आपका इमोशनल बडी। भावनात्मक सहारे और मानसिक स्वास्थ्य ट्रैकिंग के लिए ऑर्ब्ज़ से बात करें।',
          'हा ऑर्ब्ज आहे, तुमचा इमोशनल बडी. भावनिक आधार आणि मानसिक आरोग्य ट्रॅकिंगसाठी ऑर्ब्जशी बोला.',
        ),
        align: ContentAlign.top,
        shape: ShapeLightFocus.Circle,
      ),
      TourStep(
        key: navKeys[4],
        title: 'Your Profile',
        description:
            'View and edit your health profile, medical history, and app settings.',
        ttsText: _t(
          lang,
          'This is your Profile tab. You can view and edit your health profile, medical history, and app settings.',
          'यह आपकी प्रोफ़ाइल है। यहाँ अपनी स्वास्थ्य प्रोफ़ाइल, मेडिकल हिस्ट्री और ऐप सेटिंग्स देखें और बदलें।',
          'हा तुमचा प्रोफाइल टॅब आहे. येथे तुमची आरोग्य प्रोफाइल, वैद्यकीय इतिहास आणि ॲप सेटिंग्ज पहा आणि बदला.',
        ),
        align: ContentAlign.top,
        shape: ShapeLightFocus.Circle,
      ),
    ];
  }

  // ── Profile screen steps ────────────────────────────────────────────────────
  List<TourStep> _profileSteps(WidgetRef ref, String lang) {
    final keys = ref.read(profileScreenKeysProvider);
    return [
      TourStep(
        key: keys.personalInfoKey,
        title: 'Personal Information',
        description:
            'Fill in your name, date of birth, height, weight, and other details. This helps the AI give better health recommendations.',
        ttsText: _t(
          lang,
          'Fill in your personal information here. This helps the AI give you better health recommendations.',
          'यहाँ अपनी व्यक्तिगत जानकारी भरें। इससे AI आपको बेहतर स्वास्थ्य सलाह दे पाएगा।',
          'येथे तुमची वैयक्तिक माहिती भरा. यामुळे AI तुम्हाला चांगल्या आरोग्य शिफारसी देऊ शकेल.',
        ),
        align: ContentAlign.bottom,
      ),
      TourStep(
        key: keys.medicalHistoryKey,
        title: 'Medical History',
        description:
            'Add your chronic conditions, allergies, past surgeries, and family history. The more you share, the more accurate the AI advice.',
        ttsText: _t(
          lang,
          'Add your medical history here. The more you share, the more accurate and personalized the AI advice will be.',
          'यहाँ अपनी मेडिकल हिस्ट्री जोड़ें। जितना ज़्यादा आप बताएंगे, AI की सलाह उतनी ही सटीक होगी।',
          'येथे तुमचा वैद्यकीय इतिहास जोडा. तुम्ही जितके अधिक सांगाल, AI चा सल्ला तितका अचूक असेल.',
        ),
        align: ContentAlign.bottom,
      ),
      TourStep(
        key: keys.saveButtonKey,
        title: 'Save Your Profile',
        description:
            'After filling in your details, tap this button to save. You can always come back and update it later.',
        ttsText: _t(
          lang,
          'After filling in your details, tap Save Profile. You can always come back and update it later.',
          'अपनी जानकारी भरने के बाद, सेव प्रोफ़ाइल पर टैप करें। आप बाद में कभी भी इसे अपडेट कर सकते हैं।',
          'तुमची माहिती भरल्यानंतर, सेव्ह प्रोफाइल वर टॅप करा. तुम्ही नंतर कधीही ते अपडेट करू शकता.',
        ),
        align: ContentAlign.top,
      ),
      TourStep(
        key: keys.themeToggleKey,
        title: 'Theme Toggle',
        description:
            'Switch between light and dark mode from this button in the top right.',
        ttsText: _t(
          lang,
          'You can switch between light and dark mode from this button.',
          'इस बटन से आप लाइट और डार्क मोड के बीच स्विच कर सकते हैं।',
          'या बटणावरून तुम्ही लाइट आणि डार्क मोडमध्ये बदलू शकता.',
        ),
        align: ContentAlign.bottom,
        shape: ShapeLightFocus.Circle,
      ),
    ];
  }

  // ── Consultations screen steps ──────────────────────────────────────────────
  List<TourStep> _consultationsSteps(WidgetRef ref, String lang) {
    final keys = ref.read(consultationsScreenKeysProvider);
    return [
      TourStep(
        key: keys.consultationListKey,
        title: 'Your Consultations',
        description:
            'All your medical consultations appear here. Each consultation can have multiple sessions and documents.',
        ttsText: _t(
          lang,
          'All your medical consultations appear here. Each consultation can have multiple sessions and documents.',
          'आपकी सभी मेडिकल कंसल्टेशन यहाँ दिखाई देती हैं। हर कंसल्टेशन में कई सेशन और डॉक्यूमेंट हो सकते हैं।',
          'तुमचे सर्व वैद्यकीय कन्सल्टेशन येथे दिसतात. प्रत्येक कन्सल्टेशनमध्ये अनेक सत्रे आणि कागदपत्रे असू शकतात.',
        ),
        align: ContentAlign.bottom,
      ),
      TourStep(
        key: keys.newConsultationFabKey,
        title: 'Create New Consultation',
        description:
            'Tap this button to create a new consultation. Give it a name and optional start date to begin tracking.',
        ttsText: _t(
          lang,
          'Tap this button to create a new consultation. Give it a name and an optional start date to begin tracking.',
          'नई कंसल्टेशन बनाने के लिए इस बटन पर टैप करें। इसे एक नाम दें और ट्रैकिंग शुरू करें।',
          'नवीन कन्सल्टेशन तयार करण्यासाठी या बटणावर टॅप करा. त्याला नाव द्या आणि ट्रॅकिंग सुरू करा.',
        ),
        align: ContentAlign.top,
        shape: ShapeLightFocus.Circle,
      ),
    ];
  }

  // ── Assistant screen steps ──────────────────────────────────────────────────
  List<TourStep> _assistantSteps(WidgetRef ref, String lang) {
    final keys = ref.read(assistantScreenKeysProvider);
    return [
      TourStep(
        key: keys.chatListKey,
        title: 'AI Health Assistant',
        description:
            'This is where your conversations with the AI health assistant are listed. You can ask about symptoms, medicines, test reports, and more.',
        ttsText: _t(
          lang,
          'This is the AI Health Assistant. Your conversations are listed here. You can ask about symptoms, medicines, test reports, and more.',
          'यह AI हेल्थ असिस्टेंट है। आपकी बातचीत यहाँ दिखती हैं। आप लक्षण, दवाइयाँ, टेस्ट रिपोर्ट और बहुत कुछ पूछ सकते हैं।',
          'हा AI हेल्थ असिस्टंट आहे. तुमच्या संभाषणांची यादी येथे दिसते. तुम्ही लक्षणे, औषधे, चाचणी अहवाल आणि बरेच काही विचारू शकता.',
        ),
        align: ContentAlign.bottom,
      ),
      TourStep(
        key: keys.newChatFabKey,
        title: 'Start New Conversation',
        description:
            'Tap this button to start a new health conversation. You can type or use voice input to ask your questions.',
        ttsText: _t(
          lang,
          'Tap this button to start a new conversation. You can type or use voice input to ask your health questions.',
          'नई बातचीत शुरू करने के लिए इस बटन पर टैप करें। आप टाइप कर सकते हैं या वॉइस इनपुट से अपने सवाल पूछ सकते हैं।',
          'नवीन संभाषण सुरू करण्यासाठी या बटणावर टॅप करा. तुम्ही टाइप करू शकता किंवा व्हॉइस इनपुट वापरून प्रश्न विचारू शकता.',
        ),
        align: ContentAlign.top,
        shape: ShapeLightFocus.Circle,
      ),
    ];
  }

  // ── Document screen steps ───────────────────────────────────────────────────
  List<TourStep> _documentSteps(WidgetRef ref, String lang) {
    final keys = ref.read(documentScreenKeysProvider);
    return [
      TourStep(
        key: keys.descriptionKey,
        title: 'Document Scanner',
        description:
            'Upload or photograph any medical document — prescriptions, blood test reports, discharge summaries. The AI will read and explain it in simple language.',
        ttsText: _t(
          lang,
          'This is the Document Scanner. Upload or photograph any medical document. The AI will read and explain it in simple language.',
          'यह डॉक्यूमेंट स्कैनर है। कोई भी मेडिकल डॉक्यूमेंट अपलोड करें या फ़ोटो लें। AI इसे सरल भाषा में पढ़कर समझाएगा।',
          'हा डॉक्युमेंट स्कॅनर आहे. कोणताही वैद्यकीय कागदपत्र अपलोड करा किंवा फोटो काढा. AI ते सोप्या भाषेत वाचून समजावून सांगेल.',
        ),
        align: ContentAlign.bottom,
      ),
      TourStep(
        key: keys.cameraButtonKey,
        title: 'Camera Scan',
        description:
            'Use your phone camera to take a photo of a medical document for instant analysis.',
        ttsText: _t(
          lang,
          'Use the camera button to take a photo of a medical document for instant analysis.',
          'तुरंत विश्लेषण के लिए कैमरा बटन से मेडिकल डॉक्यूमेंट की फ़ोटो लें।',
          'तात्काळ विश्लेषणासाठी कॅमेरा बटण वापरून वैद्यकीय कागदपत्राचा फोटो काढा.',
        ),
        align: ContentAlign.top,
      ),
      TourStep(
        key: keys.uploadButtonKey,
        title: 'Upload File',
        description:
            'Or upload a file from your phone. Supports PDF, JPG, and PNG formats up to 1.5 MB.',
        ttsText: _t(
          lang,
          'Or tap here to upload a file from your phone. Supports PDF, JPG, and PNG formats up to 1.5 megabytes.',
          'या फ़ोन से फ़ाइल अपलोड करें। PDF, JPG और PNG फ़ॉर्मेट सपोर्ट करता है, 1.5 MB तक।',
          'किंवा फोनमधून फाइल अपलोड करा. PDF, JPG आणि PNG फॉरमॅट सपोर्ट करते, 1.5 MB पर्यंत.',
        ),
        align: ContentAlign.top,
      ),
    ];
  }

  // ── Buddy screen steps ──────────────────────────────────────────────────────
  List<TourStep> _buddySteps(WidgetRef ref, String lang) {
    final keys = ref.read(buddyScreenKeysProvider);
    return [
      TourStep(
        key: keys.orbKey,
        title: 'Meet Orbz',
        description:
            'This is Orbz, your emotional companion. The orb animates based on the conversation state — idle, listening, thinking, or speaking.',
        ttsText: _t(
          lang,
          'Meet Orbz, your emotional companion. The orb animates based on whether it is idle, listening, thinking, or speaking.',
          'ऑर्ब्ज़ से मिलिए, आपका भावनात्मक साथी। यह ऑर्ब बातचीत की स्थिति के अनुसार एनिमेट होता है।',
          'ऑर्ब्जला भेटा, तुमचा भावनिक साथी. हा ऑर्ब संभाषणाच्या स्थितीनुसार अॅनिमेट होतो.',
        ),
        align: ContentAlign.bottom,
      ),
      TourStep(
        key: keys.startButtonKey,
        title: 'Start a Conversation',
        description:
            'Tap this button to begin. Just speak naturally — Orbz listens, understands, and responds with voice. Pause for a few seconds to send your message.',
        ttsText: _t(
          lang,
          'Tap this button to begin a conversation. Just speak naturally. Orbz listens, understands, and responds with voice. Pause for a few seconds to send your message.',
          'बातचीत शुरू करने के लिए इस बटन पर टैप करें। बस स्वाभाविक रूप से बोलें। ऑर्ब्ज़ सुनता है, समझता है और आवाज़ से जवाब देता है।',
          'संभाषण सुरू करण्यासाठी या बटणावर टॅप करा. नैसर्गिकपणे बोला. ऑर्ब्ज ऐकतो, समजतो आणि आवाजाने उत्तर देतो.',
        ),
        align: ContentAlign.top,
      ),
      TourStep(
        key: keys.voiceSelectKey,
        title: 'Choose a Voice',
        description:
            'Tap here to choose a different voice for Orbz. You can preview each voice before selecting.',
        ttsText: _t(
          lang,
          'Tap here to choose a different voice for Orbz. You can preview each voice before selecting.',
          'ऑर्ब्ज़ के लिए एक अलग आवाज़ चुनने के लिए यहाँ टैप करें। चुनने से पहले हर आवाज़ सुन सकते हैं।',
          'ऑर्ब्जसाठी वेगळा आवाज निवडण्यासाठी येथे टॅप करा. निवडण्यापूर्वी प्रत्येक आवाज ऐकू शकता.',
        ),
        align: ContentAlign.bottom,
        shape: ShapeLightFocus.Circle,
      ),
      TourStep(
        key: keys.infoButtonKey,
        title: 'Usage Tips',
        description:
            'Tap this icon anytime to see tips on how to get the best experience with Orbz.',
        ttsText: _t(
          lang,
          'Tap this icon anytime to see tips on how to get the best experience with Orbz.',
          'ऑर्ब्ज़ के साथ सबसे अच्छा अनुभव पाने के टिप्स देखने के लिए इस आइकन पर कभी भी टैप करें।',
          'ऑर्ब्जसोबत सर्वोत्तम अनुभव मिळवण्यासाठी टिप्स पाहण्यासाठी या चिन्हावर कधीही टॅप करा.',
        ),
        align: ContentAlign.bottom,
        shape: ShapeLightFocus.Circle,
      ),
    ];
  }

  // ── Mental Health screen steps ──────────────────────────────────────────────
  List<TourStep> _mentalHealthSteps(WidgetRef ref, String lang) {
    final keys = ref.read(mentalHealthScreenKeysProvider);
    return [
      TourStep(
        key: keys.bodyKey,
        title: 'Mental Health Tracker',
        description:
            'This screen shows your mood trends, emotion breakdown, session history, and a mood calendar — all powered by your conversations with Orbz.',
        ttsText: _t(
          lang,
          'This is the Mental Health Tracker. It shows your mood trends, emotion breakdown, and session history. All data comes from your conversations with Orbz.',
          'यह मेंटल हेल्थ ट्रैकर है। यह आपके मूड ट्रेंड, भावनाओं का विश्लेषण और सेशन हिस्ट्री दिखाता है। सारा डेटा ऑर्ब्ज़ से बातचीत से आता है।',
          'हा मेंटल हेल्थ ट्रॅकर आहे. हे तुमचे मूड ट्रेंड, भावनांचे विश्लेषण आणि सत्र इतिहास दाखवते. सर्व डेटा ऑर्ब्जशी संभाषणातून येतो.',
        ),
        align: ContentAlign.bottom,
      ),
      TourStep(
        key: keys.statsKey,
        title: 'Session Statistics',
        description:
            'See your total sessions and average mood score at a glance. Talk to Orbz regularly to build meaningful insights.',
        ttsText: _t(
          lang,
          'Here you can see your total sessions and average mood score. Talk to Orbz regularly to build meaningful insights.',
          'यहाँ आप अपने कुल सेशन और औसत मूड स्कोर देख सकते हैं। सार्थक जानकारी के लिए ऑर्ब्ज़ से नियमित बात करें।',
          'येथे तुम्ही तुमचे एकूण सत्रे आणि सरासरी मूड स्कोअर पाहू शकता. अर्थपूर्ण अंतर्दृष्टीसाठी ऑर्ब्जशी नियमित बोला.',
        ),
        align: ContentAlign.bottom,
      ),
    ];
  }
}

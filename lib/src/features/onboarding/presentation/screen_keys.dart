import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// GlobalKeys for targetable widgets in each screen.
/// Created once via Provider and reused across rebuilds.

class HomeScreenKeys {
  final headerKey = GlobalKey();
  final askAiKey = GlobalKey();
  final scanDocKey = GlobalKey();
  final featureCardsKey = GlobalKey();
}

final homeScreenKeysProvider = Provider<HomeScreenKeys>((_) => HomeScreenKeys());

class ProfileScreenKeys {
  final personalInfoKey = GlobalKey();
  final medicalHistoryKey = GlobalKey();
  final saveButtonKey = GlobalKey();
  final themeToggleKey = GlobalKey();
  final logoutKey = GlobalKey();
}

final profileScreenKeysProvider = Provider<ProfileScreenKeys>((_) => ProfileScreenKeys());

class AssistantScreenKeys {
  final newChatFabKey = GlobalKey();
  final chatListKey = GlobalKey();
}

final assistantScreenKeysProvider = Provider<AssistantScreenKeys>((_) => AssistantScreenKeys());

class ConsultationsScreenKeys {
  final newConsultationFabKey = GlobalKey();
  final consultationListKey = GlobalKey();
}

final consultationsScreenKeysProvider = Provider<ConsultationsScreenKeys>((_) => ConsultationsScreenKeys());

class DocumentScreenKeys {
  final cameraButtonKey = GlobalKey();
  final uploadButtonKey = GlobalKey();
  final descriptionKey = GlobalKey();
}

final documentScreenKeysProvider = Provider<DocumentScreenKeys>((_) => DocumentScreenKeys());

class BuddyScreenKeys {
  final orbKey = GlobalKey();
  final startButtonKey = GlobalKey();
  final voiceSelectKey = GlobalKey();
  final infoButtonKey = GlobalKey();
}

final buddyScreenKeysProvider = Provider<BuddyScreenKeys>((_) => BuddyScreenKeys());

class MentalHealthScreenKeys {
  final statsKey = GlobalKey();
  final bodyKey = GlobalKey();
}

final mentalHealthScreenKeysProvider = Provider<MentalHealthScreenKeys>((_) => MentalHealthScreenKeys());

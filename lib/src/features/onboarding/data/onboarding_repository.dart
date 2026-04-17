import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

class OnboardingRepository {
  static const _keyJustRegistered = 'just_registered';
  static const _keyTourCompleted = 'tour_completed';

  Future<bool> isJustRegistered() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_keyJustRegistered) ?? false;
  }

  Future<void> setJustRegistered(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyJustRegistered, value);
  }

  Future<bool> isTourCompleted() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_keyTourCompleted) ?? false;
  }

  Future<void> setTourCompleted([bool value = true]) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyTourCompleted, value);
  }
}

final onboardingRepositoryProvider = Provider<OnboardingRepository>((ref) {
  return OnboardingRepository();
});

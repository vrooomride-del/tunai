import 'package:shared_preferences/shared_preferences.dart';

/// 최초 실행 웰컴 화면 1회 노출 여부 — 로컬(SharedPreferences)에만 보관.
class OnboardingStorage {
  static const _key = 'has_seen_welcome_v1';

  static Future<bool> hasSeenWelcome() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_key) ?? false;
  }

  static Future<void> markWelcomeSeen() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_key, true);
  }
}

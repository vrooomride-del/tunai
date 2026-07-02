import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'audio_analyzer.dart';

/// "My Tune" 프리셋 바 항목 — 사용자가 저장한 커스텀 튜닝을 로컬(SharedPreferences)에 보관.
/// 클라우드 동기화는 범위 밖 (커뮤니티 공유는 기존 COMMUNITY 업로드 플로우를 그대로 사용).
class MyTuneStorage {
  static const _key = 'my_tune_preset_v1';

  static Future<void> save(List<ResonancePeak> peaks) async {
    final prefs = await SharedPreferences.getInstance();
    final json = jsonEncode({
      'savedAt': DateTime.now().toIso8601String(),
      'peaks': peaks.map((p) => {'frequency': p.frequency, 'gain': p.gain, 'q': p.q}).toList(),
    });
    await prefs.setString(_key, json);
  }

  static Future<List<ResonancePeak>?> load() async {
    final raw = await _rawEntry();
    if (raw == null) return null;
    final list = raw['peaks'] as List;
    return list
        .map((e) => ResonancePeak(
              frequency: (e['frequency'] as num).toDouble(),
              gain: (e['gain'] as num).toDouble(),
              q: (e['q'] as num).toDouble(),
            ))
        .toList();
  }

  static Future<DateTime?> loadSavedAt() async {
    final raw = await _rawEntry();
    if (raw == null) return null;
    return DateTime.tryParse(raw['savedAt'] as String? ?? '');
  }

  static Future<bool> hasSaved() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.containsKey(_key);
  }

  static Future<Map<String, dynamic>?> _rawEntry() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null) return null;
    return jsonDecode(raw) as Map<String, dynamic>;
  }
}

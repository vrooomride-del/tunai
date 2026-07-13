// ── TUNAI Consumer — ADAU1701 Engineering Persistence ───────────────────────
// SharedPreferences-based persistence for candidate state and validation log.
// Does not affect DSP state. Stores verification metadata only.

import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'adau1701_engineering_candidate.dart';

class Adau1701EngineeringPersistence {
  static const _kCandidatesKey = 'tunai_adau1701_eng_candidates_v1';
  static const _kLogKey = 'tunai_adau1701_eng_log_v1';

  static Future<void> saveCandidates(
      List<Adau1701AddressCandidate> candidates) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
        _kCandidatesKey, jsonEncode(candidates.map((c) => c.toJson()).toList()));
  }

  static Future<List<Adau1701AddressCandidate>?> loadCandidates() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kCandidatesKey);
    if (raw == null) return null;
    try {
      final list = jsonDecode(raw) as List<dynamic>;
      return list
          .map((e) => Adau1701AddressCandidate.fromJson(
              Map<String, dynamic>.from(e as Map)))
          .toList();
    } catch (_) {
      return null;
    }
  }

  static Future<void> saveLog(List<Adau1701EngLogEntry> log) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
        _kLogKey, jsonEncode(log.map((e) => e.toJson()).toList()));
  }

  static Future<List<Adau1701EngLogEntry>> loadLog() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kLogKey);
    if (raw == null) return [];
    try {
      final list = jsonDecode(raw) as List<dynamic>;
      return list
          .map((e) => Adau1701EngLogEntry.fromJson(
              Map<String, dynamic>.from(e as Map)))
          .toList();
    } catch (_) {
      return [];
    }
  }

  static Future<void> clearAll() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kCandidatesKey);
    await prefs.remove(_kLogKey);
  }
}

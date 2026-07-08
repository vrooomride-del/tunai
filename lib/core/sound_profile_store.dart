import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _kPrefsKey = 'ui_sound_profiles';

/// UI 전용 Sound Profile 모델 — DSP/BLE 내부 구조 독립
class UiSoundProfile {
  final String id;
  final String name;
  final String roomTypeLabel;     // 한국어
  final String roomTypeLabelEn;   // 영어
  final int? soundScore;
  final DateTime createdAt;
  final bool isApplied;
  final List<Map<String, dynamic>> bands; // AiTuningResult.bands 복사본
  final String? summary;

  const UiSoundProfile({
    required this.id,
    required this.name,
    required this.roomTypeLabel,
    required this.roomTypeLabelEn,
    this.soundScore,
    required this.createdAt,
    this.isApplied = false,
    required this.bands,
    this.summary,
  });

  UiSoundProfile copyWith({
    String? name,
    bool? isApplied,
    String? summary,
  }) => UiSoundProfile(
    id: id,
    name: name ?? this.name,
    roomTypeLabel: roomTypeLabel,
    roomTypeLabelEn: roomTypeLabelEn,
    soundScore: soundScore,
    createdAt: createdAt,
    isApplied: isApplied ?? this.isApplied,
    bands: bands,
    summary: summary ?? this.summary,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'roomTypeLabel': roomTypeLabel,
    'roomTypeLabelEn': roomTypeLabelEn,
    'soundScore': soundScore,
    'createdAt': createdAt.toIso8601String(),
    'isApplied': isApplied,
    'bands': bands,
    'summary': summary,
  };

  factory UiSoundProfile.fromJson(Map<String, dynamic> j) => UiSoundProfile(
    id: j['id'] as String,
    name: j['name'] as String,
    roomTypeLabel: j['roomTypeLabel'] as String? ?? '',
    roomTypeLabelEn: j['roomTypeLabelEn'] as String? ?? '',
    soundScore: j['soundScore'] as int?,
    createdAt: DateTime.parse(j['createdAt'] as String),
    isApplied: j['isApplied'] as bool? ?? false,
    bands: (j['bands'] as List? ?? [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList(),
    summary: j['summary'] as String?,
  );
}

class SoundProfileNotifier extends StateNotifier<List<UiSoundProfile>> {
  SoundProfileNotifier() : super(const []) {
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kPrefsKey);
    if (raw == null) return;
    try {
      final list = jsonDecode(raw) as List;
      state = list
          .map((e) => UiSoundProfile.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList();
    } catch (_) {}
  }

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kPrefsKey, jsonEncode(state.map((p) => p.toJson()).toList()));
  }

  Future<void> add(UiSoundProfile profile) async {
    state = [...state, profile];
    await _persist();
  }

  Future<void> markApplied(String id) async {
    state = state.map((p) => p.copyWith(isApplied: p.id == id)).toList();
    await _persist();
  }

  Future<void> rename(String id, String newName) async {
    state = state.map((p) => p.id == id ? p.copyWith(name: newName) : p).toList();
    await _persist();
  }

  Future<void> delete(String id) async {
    state = state.where((p) => p.id != id).toList();
    await _persist();
  }

  /// 현재 적용된 프로파일 (없으면 null)
  UiSoundProfile? get applied =>
      state.where((p) => p.isApplied).fold<UiSoundProfile?>(null, (_, p) => p);
}

final soundProfileStoreProvider =
    StateNotifierProvider<SoundProfileNotifier, List<UiSoundProfile>>(
        (ref) => SoundProfileNotifier());

/// 현재 적용된 Sound Profile
final appliedProfileProvider = Provider<UiSoundProfile?>((ref) {
  final list = ref.watch(soundProfileStoreProvider);
  return list.where((p) => p.isApplied).fold<UiSoundProfile?>(null, (_, p) => p);
});

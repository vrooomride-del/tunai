import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'room_scan_result.dart';

enum ConsumerProfileStatus { draft, ready, active }

class ConsumerSoundProfile {
  final String id;
  final String name;
  final String roomType;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String micProfileName;
  final String confidence;
  final bool isActive;
  final ConsumerProfileStatus status;
  final List<RoomScanResultCard> resultCards;

  const ConsumerSoundProfile({
    required this.id,
    required this.name,
    required this.roomType,
    required this.createdAt,
    required this.updatedAt,
    required this.micProfileName,
    required this.confidence,
    required this.isActive,
    required this.status,
    required this.resultCards,
  });

  ConsumerSoundProfile copyWith({
    String? name,
    bool? isActive,
    ConsumerProfileStatus? status,
    DateTime? updatedAt,
  }) =>
      ConsumerSoundProfile(
        id: id,
        name: name ?? this.name,
        roomType: roomType,
        createdAt: createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
        micProfileName: micProfileName,
        confidence: confidence,
        isActive: isActive ?? this.isActive,
        status: status ?? this.status,
        resultCards: resultCards,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'roomType': roomType,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
        'micProfileName': micProfileName,
        'confidence': confidence,
        'isActive': isActive,
        'status': status.name,
        'resultCards': resultCards.map((c) => c.toJson()).toList(),
      };

  factory ConsumerSoundProfile.fromJson(Map<String, dynamic> j) =>
      ConsumerSoundProfile(
        id: j['id'] as String,
        name: j['name'] as String,
        roomType: j['roomType'] as String,
        createdAt: DateTime.parse(j['createdAt'] as String),
        updatedAt: DateTime.parse(j['updatedAt'] as String),
        micProfileName: j['micProfileName'] as String,
        confidence: j['confidence'] as String,
        isActive: j['isActive'] as bool,
        status: ConsumerProfileStatus.values.byName(j['status'] as String),
        resultCards: (j['resultCards'] as List)
            .map((c) => RoomScanResultCard.fromJson(c as Map<String, dynamic>))
            .toList(),
      );
}

// ── UI label helpers (stored values are English) ─────────────────────────────

String roomTypeLabelKo(String roomType) => switch (roomType) {
      'Living Room' => '거실',
      'Desk' => '책상 위',
      'Near Wall' => '벽 가까이',
      'Studio' => '작업실',
      'Custom' => '직접 설정',
      _ => roomType,
    };

String micProfileLabelKo(String micProfileName) => switch (micProfileName) {
      'Generic Phone Mic' => '기본 휴대폰 마이크',
      _ => micProfileName,
    };

extension ConsumerSoundProfileLabels on ConsumerSoundProfile {
  String get roomTypeLabel => roomTypeLabelKo(roomType);
  String get roomTypeLabelEn => roomType;
  String micLabel(bool ko) =>
      ko ? micProfileLabelKo(micProfileName) : micProfileName;
}

const _kKey = 'tunai_consumer_sound_profiles';

class ConsumerSoundProfileNotifier
    extends StateNotifier<List<ConsumerSoundProfile>> {
  ConsumerSoundProfileNotifier() : super([]) {
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kKey);
    if (raw != null) {
      try {
        final list = jsonDecode(raw) as List;
        state = list
            .map((e) =>
                ConsumerSoundProfile.fromJson(e as Map<String, dynamic>))
            .toList();
      } catch (_) {}
    }
  }

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
        _kKey, jsonEncode(state.map((p) => p.toJson()).toList()));
  }

  Future<void> add(ConsumerSoundProfile profile) async {
    state = [profile, ...state];
    await _persist();
  }

  Future<void> setActive(String id) async {
    final now = DateTime.now();
    state = state.map((p) {
      if (p.id == id) {
        return p.copyWith(
            isActive: true, status: ConsumerProfileStatus.active, updatedAt: now);
      }
      return p.copyWith(isActive: false, status: ConsumerProfileStatus.ready);
    }).toList();
    await _persist();
  }

  Future<void> deactivateAll() async {
    state = state.map((p) => p.copyWith(isActive: false, status: ConsumerProfileStatus.ready)).toList();
    await _persist();
  }

  Future<void> delete(String id) async {
    state = state.where((p) => p.id != id).toList();
    await _persist();
  }
}

final consumerSoundProfileProvider = StateNotifierProvider<
    ConsumerSoundProfileNotifier, List<ConsumerSoundProfile>>(
  (_) => ConsumerSoundProfileNotifier(),
);

final activeConsumerProfileProvider = Provider<ConsumerSoundProfile?>((ref) {
  final profiles = ref.watch(consumerSoundProfileProvider);
  try {
    return profiles.firstWhere((p) => p.isActive);
  } catch (_) {
    return null;
  }
});

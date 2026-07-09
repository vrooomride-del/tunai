import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Consumer-facing result after a Room Scan completes.
/// No DSP/PEQ/frequency graph data is exposed here.
class RoomScanResultCard {
  final String id;
  final String labelEn;
  final String labelKo;
  final String descriptionEn;
  final String descriptionKo;

  const RoomScanResultCard({
    required this.id,
    required this.labelEn,
    required this.labelKo,
    required this.descriptionEn,
    required this.descriptionKo,
  });

  String label({bool ko = false}) => ko ? labelKo : labelEn;
  String description({bool ko = false}) => ko ? descriptionKo : descriptionEn;

  Map<String, dynamic> toJson() => {
    'id': id, 'labelEn': labelEn, 'labelKo': labelKo,
    'descriptionEn': descriptionEn, 'descriptionKo': descriptionKo,
  };
  factory RoomScanResultCard.fromJson(Map<String, dynamic> j) => RoomScanResultCard(
    id: j['id'] as String,
    labelEn: j['labelEn'] as String,
    labelKo: j['labelKo'] as String,
    descriptionEn: j['descriptionEn'] as String,
    descriptionKo: j['descriptionKo'] as String,
  );
}

/// Placeholder result cards shown after every Room Scan.
/// Content may be updated by the analysis engine in a future phase.
const kDefaultResultCards = [
  RoomScanResultCard(
    id: 'balance',
    labelEn: 'Room Balance',
    labelKo: '공간 밸런스',
    descriptionEn: 'Left and right listening balance adjusted for your position.',
    descriptionKo: '청취 위치에 맞게 좌우 청취 균형이 조정되었습니다.',
  ),
  RoomScanResultCard(
    id: 'bass',
    labelEn: 'Bass Control',
    labelKo: '저역 정리',
    descriptionEn: 'Room reflections that affect bass have been identified.',
    descriptionKo: '저역에 영향을 주는 공간 반사가 파악되었습니다.',
  ),
  RoomScanResultCard(
    id: 'voice',
    labelEn: 'Voice Clarity',
    labelKo: '보컬 선명도',
    descriptionEn: 'Mid-range presence has been optimised for your room.',
    descriptionKo: '공간에 맞게 중음역 선명도가 최적화되었습니다.',
  ),
  RoomScanResultCard(
    id: 'comfort',
    labelEn: 'Listening Comfort',
    labelKo: '청취 편안함',
    descriptionEn: 'Harshness and fatigue factors identified in your space.',
    descriptionKo: '공간의 피로감 요인이 파악되어 편안한 소리로 조정됩니다.',
  ),
];

class RoomScanResult {
  final String roomType;
  final String micProfileName;
  final DateTime completedAt;
  final String confidence;
  final List<RoomScanResultCard> cards;

  const RoomScanResult({
    required this.roomType,
    required this.micProfileName,
    required this.completedAt,
    required this.confidence,
    required this.cards,
  });

  Map<String, dynamic> toJson() => {
    'roomType': roomType,
    'micProfileName': micProfileName,
    'completedAt': completedAt.toIso8601String(),
    'confidence': confidence,
    'cards': cards.map((c) => c.toJson()).toList(),
  };

  factory RoomScanResult.fromJson(Map<String, dynamic> j) => RoomScanResult(
    roomType: j['roomType'] as String,
    micProfileName: j['micProfileName'] as String,
    completedAt: DateTime.parse(j['completedAt'] as String),
    confidence: j['confidence'] as String,
    cards: (j['cards'] as List)
        .map((c) => RoomScanResultCard.fromJson(c as Map<String, dynamic>))
        .toList(),
  );
}

// ── Riverpod store ────────────────────────────────────────────────────────────
const _kKey = 'tunai_room_scan_result';

class RoomScanResultNotifier extends StateNotifier<RoomScanResult?> {
  RoomScanResultNotifier() : super(null) {
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kKey);
    if (raw != null) {
      try {
        state = RoomScanResult.fromJson(jsonDecode(raw) as Map<String, dynamic>);
      } catch (_) {}
    }
  }

  Future<void> saveResult(RoomScanResult result) async {
    state = result;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kKey, jsonEncode(result.toJson()));
  }

  Future<void> clear() async {
    state = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kKey);
  }
}

final roomScanResultProvider =
    StateNotifierProvider<RoomScanResultNotifier, RoomScanResult?>(
        (_) => RoomScanResultNotifier());

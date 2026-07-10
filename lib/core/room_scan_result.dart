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

const kDefaultResultCards = [
  RoomScanResultCard(
    id: 'balance',
    labelEn: 'Room Balance',
    labelKo: '공간 밸런스',
    descriptionEn:
        'TUNAI checked how your room shapes the sound at your listening position.'
        '\n→ The sound was refined for better overall balance.',
    descriptionKo:
        'TUNAI가 청취 위치에서 공간의 울림을 확인했습니다.'
        '\n→ 더 균형 잡힌 소리로 정리했습니다.',
  ),
  RoomScanResultCard(
    id: 'bass',
    labelEn: 'Bass Control',
    labelKo: '저역 정리',
    descriptionEn:
        'Nearby surfaces can make bass feel heavier than intended.'
        '\n→ Bass was tightened for a clearer, more controlled sound.',
    descriptionKo:
        '벽과 책상 주변의 영향으로 저역이 부풀 수 있습니다.'
        '\n→ 저역이 더 단단하고 또렷하게 들리도록 정리했습니다.',
  ),
  RoomScanResultCard(
    id: 'voice',
    labelEn: 'Vocal Clarity',
    labelKo: '보컬 선명도',
    descriptionEn:
        'Room reflections can blur vocal presence.'
        '\n→ Vocals were adjusted to sound more natural and focused.',
    descriptionKo:
        '보컬 대역이 공간 반사로 흐려질 수 있습니다.'
        '\n→ 목소리가 더 자연스럽게 앞으로 나오도록 조정했습니다.',
  ),
  RoomScanResultCard(
    id: 'comfort',
    labelEn: 'Listening Comfort',
    labelKo: '청취 편안함',
    descriptionEn:
        'TUNAI checked the balance for longer listening.'
        '\n→ The sound was refined to feel more comfortable over time.',
    descriptionKo:
        '오래 들을 때 피로감을 줄이는 방향을 확인했습니다.'
        '\n→ 더 편안하게 들을 수 있도록 소리의 균형을 다듬었습니다.',
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

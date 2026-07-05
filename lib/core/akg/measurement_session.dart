import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

/// AKG(Acoustic Knowledge Graph)-ready 노드 — 측정 1회의 메타데이터.
///
/// 지금은 그래프 DB가 없어 로컬(SharedPreferences)에 append-only 리스트로
/// 쌓아두기만 한다. [deviceId]/[userId]/[spaceType]은 다른 노드(Device/User/
/// SpaceProfile)를 ID로 참조하는 필드일 뿐 — 나중에 실제 그래프 DB로 옮길 때
/// 그대로 엣지(관계)가 된다. 지금 당장은 아무도 이 데이터를 분석하지 않고
/// AIE(지능엔진)가 참조할 수 있도록 저장만 해둔다.
class MeasurementSession {
  final String id;
  final DateTime timestamp;
  final String? deviceId;   // TunaiDevice.serial(device_service.dart) 참조
  final int? userId;        // AuthState.userId 참조
  final String? spaceType;  // InstallLocation.name 참조 — SpaceProfile 노드가 생기기 전 임시
  final int peakCount;
  final int? iterations;         // Closed Loop 반복 횟수(있으면)
  final double? residualErrorDb; // Closed Loop 수렴 잔류오차(있으면)
  final bool converged;

  const MeasurementSession({
    required this.id,
    required this.timestamp,
    this.deviceId,
    this.userId,
    this.spaceType,
    required this.peakCount,
    this.iterations,
    this.residualErrorDb,
    this.converged = false,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'timestamp': timestamp.toIso8601String(),
        'deviceId': deviceId,
        'userId': userId,
        'spaceType': spaceType,
        'peakCount': peakCount,
        'iterations': iterations,
        'residualErrorDb': residualErrorDb,
        'converged': converged,
      };

  factory MeasurementSession.fromJson(Map<String, dynamic> j) => MeasurementSession(
        id: j['id'] as String,
        timestamp: DateTime.parse(j['timestamp'] as String),
        deviceId: j['deviceId'] as String?,
        userId: j['userId'] as int?,
        spaceType: j['spaceType'] as String?,
        peakCount: j['peakCount'] as int? ?? 0,
        iterations: j['iterations'] as int?,
        residualErrorDb: (j['residualErrorDb'] as num?)?.toDouble(),
        converged: j['converged'] as bool? ?? false,
      );
}

/// 로컬 측정 이력 저장소 — 최근 [_maxEntries]개까지만 보관(무한 성장 방지).
class MeasurementSessionStore {
  static const _key = 'akg_measurement_sessions_v1';
  static const _maxEntries = 200;

  static Future<void> append(MeasurementSession session) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_key) ?? <String>[];
    raw.add(jsonEncode(session.toJson()));
    final trimmed =
        raw.length > _maxEntries ? raw.sublist(raw.length - _maxEntries) : raw;
    await prefs.setStringList(_key, trimmed);
  }

  static Future<List<MeasurementSession>> loadAll() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_key) ?? <String>[];
    final out = <MeasurementSession>[];
    for (final s in raw) {
      try {
        out.add(MeasurementSession.fromJson(jsonDecode(s) as Map<String, dynamic>));
      } catch (_) {
        // 손상된 항목은 건너뜀
      }
    }
    return out;
  }
}

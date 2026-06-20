import 'dart:math';

/// FRD 포인트 (주파수 + SPL dB + 위상 도)
class FrdPoint {
  final double frequency;
  final double spl;
  final double phase;
  const FrdPoint({required this.frequency, required this.spl, this.phase = 0.0});
}

/// FRD 파일 파싱 + 크로스오버 추천 유틸리티
///
/// 지원 형식: "주파수 SPL [위상]" (공백/탭 구분, # 또는 * 주석)
/// 모바일용 — ZMA/T/S 역산은 포함하지 않음
class FrdParser {
  /// FRD 텍스트 파싱
  static List<FrdPoint> parseFrd(String content) {
    final points = <FrdPoint>[];
    for (final line in content.split('\n')) {
      final trimmed = line.trim();
      if (trimmed.isEmpty || trimmed.startsWith('#') || trimmed.startsWith('*')) continue;
      final parts = trimmed.split(RegExp(r'[\s,\t]+'));
      if (parts.length < 2) continue;
      final freq = double.tryParse(parts[0]);
      final spl  = double.tryParse(parts[1]);
      if (freq == null || spl == null) continue;
      final phase = parts.length >= 3 ? (double.tryParse(parts[2]) ?? 0.0) : 0.0;
      points.add(FrdPoint(frequency: freq, spl: spl, phase: phase));
    }
    points.sort((a, b) => a.frequency.compareTo(b.frequency));
    return points;
  }

  /// 감도 계산 (300Hz~3kHz 평균 SPL)
  static double calculateSensitivity(List<FrdPoint> frd) {
    final band = frd.where((p) => p.frequency >= 300 && p.frequency <= 3000).toList();
    if (band.isEmpty) return 85.0;
    return band.map((p) => p.spl).reduce((a, b) => a + b) / band.length;
  }

  /// 크로스오버 주파수 추천 — 우퍼 고역 -6dB / 트위터 저역 -6dB 기하평균
  ///
  /// 단채널(우퍼만)일 때는 우퍼 -6dB 롤오프 단독 사용.
  static double recommendCrossover(
    List<FrdPoint> wooferFrd, {
    List<FrdPoint>? tweeterFrd,
  }) {
    final wooferSens = calculateSensitivity(wooferFrd);

    double? wooferRolloff;
    for (int i = wooferFrd.length - 1; i >= 0; i--) {
      if (wooferFrd[i].spl >= wooferSens - 6) {
        wooferRolloff = wooferFrd[i].frequency;
        break;
      }
    }

    if (tweeterFrd != null && tweeterFrd.isNotEmpty) {
      final tweeterSens = calculateSensitivity(tweeterFrd);
      double? tweeterLow;
      for (final p in tweeterFrd) {
        if (p.spl >= tweeterSens - 6) {
          tweeterLow = p.frequency;
          break;
        }
      }
      if (wooferRolloff != null && tweeterLow != null) {
        return sqrt(wooferRolloff * tweeterLow);
      }
    }

    return (wooferRolloff ?? 2500.0).clamp(800.0, 5000.0);
  }

  /// FRD에서 특정 주파수 SPL 보간
  static double interpolateSpl(List<FrdPoint> frd, double frequency) {
    if (frd.isEmpty) return 0.0;
    if (frequency <= frd.first.frequency) return frd.first.spl;
    if (frequency >= frd.last.frequency) return frd.last.spl;
    for (int i = 0; i < frd.length - 1; i++) {
      if (frd[i].frequency <= frequency && frd[i + 1].frequency >= frequency) {
        final t = (frequency - frd[i].frequency) / (frd[i + 1].frequency - frd[i].frequency);
        return frd[i].spl + t * (frd[i + 1].spl - frd[i].spl);
      }
    }
    return 0.0;
  }
}

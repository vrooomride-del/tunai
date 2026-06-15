import 'dart:typed_data';

/// BLE 프레임을 직접 쓰는 콜백 타입
typedef RawWriteFn = Future<void> Function(Uint8List frame);

class BiquadCoeffs {
  final double b0, b1, b2, a1, a2;
  const BiquadCoeffs({
    required this.b0, required this.b1, required this.b2,
    required this.a1, required this.a2,
  });
}

enum CrossoverType { lpf, hpf }
enum CrossoverSlope { lr2, lr4, bw2, bw4 }

class CrossoverConfig {
  final CrossoverType type;
  final double freqHz;
  final CrossoverSlope slope;
  const CrossoverConfig({required this.type, required this.freqHz, this.slope = CrossoverSlope.lr4});
}

class DspState {
  final Map<String, dynamic> raw;
  const DspState({required this.raw});
}

/// DSP 칩별 통신 추상화 — 채널/밴드 단위 고수준 API
abstract class DspAdapter {
  /// PEQ 밴드 1개의 Biquad 계수를 DSP에 기록
  Future<void> writeBiquad(int channelIndex, int bandIndex, BiquadCoeffs coeffs);

  /// 크로스오버 (LPF/HPF) 계수 기록
  Future<void> writeCrossover(int channelIndex, CrossoverConfig config);

  /// 채널 딜레이 기록 (위상 정렬용)
  Future<void> writeDelay(int channelIndex, double delayMs);

  /// 채널 게인/레벨 기록
  Future<void> writeGain(int channelIndex, double gainDb);

  /// 서브소닉 HPF (Xmax 보호)
  Future<void> writeSubsonicFilter(int channelIndex, double freqHz);

  /// 현재 적용된 설정 읽기 (옵션 — 미지원 칩은 빈 DspState 반환)
  Future<DspState> readCurrentState();
}

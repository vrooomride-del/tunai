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

/// HP / LP 방향
enum FilterSide { lpf, hpf }

/// 크로스오버 기울기
/// bypass: 비활성
/// bw2/bw4: 2차/4차 Butterworth (12/24 dB/oct)
/// lr2/lr4: 2차/4차 Linkwitz-Riley (12/24 dB/oct)
/// lr8: 8차 Linkwitz-Riley (48 dB/oct)
enum CrossoverSlope { bypass, bw2, bw4, lr2, lr4, lr8 }

class CrossoverConfig {
  final FilterSide side;
  final double freqHz;
  final CrossoverSlope slope;
  const CrossoverConfig({
    required this.side,
    required this.freqHz,
    this.slope = CrossoverSlope.lr4,
  });
}

class DspState {
  final Map<String, dynamic> raw;
  const DspState({required this.raw});
}

abstract class DspAdapter {
  Future<void> writeBiquad(int channelIndex, int bandIndex, BiquadCoeffs coeffs);
  Future<void> writeCrossover(int channelIndex, CrossoverConfig config);
  Future<void> writeDelay(int channelIndex, double delayMs);
  Future<void> writeGain(int channelIndex, double gainDb);
  Future<void> writeSubsonicFilter(int channelIndex, double freqHz);
  Future<DspState> readCurrentState();
}

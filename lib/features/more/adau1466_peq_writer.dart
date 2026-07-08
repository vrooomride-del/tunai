import 'dart:math';
import '../../core/dsp/transport/dsp_transport.dart';
import 'dsp_unlock_flags.dart';

/// ADAU1466 biquad PEQ 係数 write — BLE transport 経由, 5.27 固定小数点.
///
/// ADAU1466 係数順序: B2 / B1 / B0 / A2 / A1 (5ワード).
/// [DspUnlockFlags.peqWriteUnlocked] = false 동안 실제 write 차단.
class Adau1466PeqWriter {
  final DspTransport transport;

  static const double kFs = 48000.0;

  Adau1466PeqWriter(this.transport);

  /// 단일 PEQ 밴드를 write.
  ///
  /// [baseAddr] : 채널의 PEQ 기준 주소 (예: Global L = 0x69).
  /// [bandIndex] : 0~19.
  /// [gainDb]   : -24.0 ~ +24.0 dB.
  /// [freq]     : 20 ~ 20000 Hz.
  /// [q]        : Q 값 (0.1 ~ 16).
  Future<void> writePeqBand(
    int baseAddr,
    int bandIndex,
    double gainDb,
    double freq,
    double q,
  ) async {
    if (!DspUnlockFlags.peqWriteUnlocked) return;

    final coeffs = _calcPeakingBiquad(gainDb: gainDb, freq: freq, q: q);
    final startAddr = baseAddr + bandIndex * 5;

    // ADAU1466 순서: B2/B1/B0/A2/A1
    for (var i = 0; i < 5; i++) {
      final fixed = _toFixed527(coeffs[i]);
      await transport.writeParameter(startAddr + i, _toBytes4(fixed));
    }
  }

  /// Peaking EQ biquad 계수 계산 (Audio EQ Cookbook).
  /// 반환 순서: [B2, B1, B0, A2, A1] — a0으로 정규화.
  static List<double> _calcPeakingBiquad({
    required double gainDb,
    required double freq,
    required double q,
  }) {
    final w0 = 2.0 * pi * freq / kFs;
    final cosW0 = cos(w0);
    final sinW0 = sin(w0);
    final alpha = sinW0 / (2.0 * q);
    final A = pow(10.0, gainDb / 40.0).toDouble();

    final b0 = 1.0 + alpha * A;
    final b1 = -2.0 * cosW0;
    final b2 = 1.0 - alpha * A;
    final a0 = 1.0 + alpha / A;
    final a1 = -2.0 * cosW0;
    final a2 = 1.0 - alpha / A;

    return [b2 / a0, b1 / a0, b0 / a0, a2 / a0, a1 / a0];
  }

  /// double → 5.27 fixed-point. dbToFixed824() 사용 금지 (Q8.24 ≠ 5.27).
  static int _toFixed527(double v) => (v * (1 << 27)).round();

  static List<int> _toBytes4(int v) => [
        (v >> 24) & 0xFF,
        (v >> 16) & 0xFF,
        (v >> 8) & 0xFF,
        v & 0xFF,
      ];
}

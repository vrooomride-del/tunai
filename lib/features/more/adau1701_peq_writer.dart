import 'dart:math';
import '../../core/dsp/transport/dsp_transport.dart';
import 'dsp_unlock_flags.dart';

/// ADAU1701 biquad PEQ 係数 write — BLE transport 経由, 5.23 固定小数点.
///
/// ADAU1701 係数順序: B0 / B1 / B2 / A0 / A1 (5ワード).
/// A0 = 1.0 (정규화 값), A1은 피드백 계수 (Audio EQ Cookbook의 -a1/a0).
/// [DspUnlockFlags.peqWriteUnlocked] = false 동안 실제 write 차단.
class Adau1701PeqWriter {
  final DspTransport transport;

  static const double kFs = 48000.0;

  Adau1701PeqWriter(this.transport);

  /// 단일 PEQ 밴드를 write.
  ///
  /// [baseAddr] : 밴드 기준 주소.
  /// [bandIndex] : 0~9 (ADAU1701 최대 10밴드).
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

    // ADAU1701 순서: B0/B1/B2/A0/A1
    for (var i = 0; i < 5; i++) {
      final fixed = _toFixed523(coeffs[i]);
      await transport.writeParameter(startAddr + i, _toBytes4(fixed));
    }
  }

  /// Peaking EQ biquad 계수 계산 (Audio EQ Cookbook).
  /// 반환 순서: [B0, B1, B2, A0(=1.0), A1] — a0으로 정규화.
  /// ADAU1701 is DSP feedback-form: H = (B0 + B1*z^-1 + B2*z^-2) / (A0 - A1*z^-1 - A2*z^-2)
  /// A2는 5번째 슬롯이 없으므로 0 처리(단일 이극 biquad 근사 — 실기기 검증 필요).
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
    final a0raw = 1.0 + alpha / A;
    final a1raw = -2.0 * cosW0;

    // 정규화 (a0raw로 나눔), ADAU1701 A0 슬롯에는 정규화 후 1.0
    return [
      b0 / a0raw,     // B0
      b1 / a0raw,     // B1
      b2 / a0raw,     // B2
      1.0,            // A0 (정규화됨)
      a1raw / a0raw,  // A1
    ];
  }

  /// double → 5.23 fixed-point.
  static int _toFixed523(double v) => (v * (1 << 23)).round();

  static List<int> _toBytes4(int v) => [
        (v >> 24) & 0xFF,
        (v >> 16) & 0xFF,
        (v >> 8) & 0xFF,
        v & 0xFF,
      ];
}

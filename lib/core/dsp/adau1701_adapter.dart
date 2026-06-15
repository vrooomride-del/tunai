import 'dart:math';
import 'dsp_adapter.dart';
import '../../features/dsp/dsp_compiler.dart';

/// ADAU1701 (TUNAI ONE / JAB4) 어댑터
///
/// 기존 DspCompiler + BLE 27바이트 프레임 로직을 그대로 재사용.
/// PRAM 주소 레이아웃:
///   채널 0 (Woofer)  밴드 0–7 → 0x0010 + band * 5
///   채널 1 (Tweeter) 밴드 0–7 → 0x0050 + band * 5
///
/// [0xAA][Addr 2B][Data 20B][XOR Checksum][0x55]
class Adau1701Adapter implements DspAdapter {
  final RawWriteFn _writeRaw;

  static const int _basePramWoofer  = 0x0010;
  static const int _basePramTweeter = 0x0050;
  static const int _bandsPerChannel = 8;

  Adau1701Adapter({required RawWriteFn writeRaw}) : _writeRaw = writeRaw;

  int _pramAddr(int channelIndex, int bandIndex) {
    assert(bandIndex < _bandsPerChannel);
    final base = channelIndex == 0 ? _basePramWoofer : _basePramTweeter;
    return base + bandIndex * 5;
  }

  @override
  Future<void> writeBiquad(int channelIndex, int bandIndex, BiquadCoeffs coeffs) async {
    final addr = _pramAddr(channelIndex, bandIndex);
    final bytes = <int>[];
    for (final c in [coeffs.b0, coeffs.b1, coeffs.b2, coeffs.a1, coeffs.a2]) {
      bytes.addAll(DspCompiler.toBytes4(DspCompiler.toFixed523(c)));
    }
    final packet = RegisterPacket(pramTargetAddr: addr, coeffBytes: bytes);
    await _writeRaw(DspCompiler.buildBleFrame(packet));
  }

  @override
  Future<void> writeCrossover(int channelIndex, CrossoverConfig config) async {
    // ADAU1701: 크로스오버를 HPF/LPF Biquad로 구현
    final coeffs = config.type == CrossoverType.hpf
        ? _buildHpf(config.freqHz)
        : _buildLpf(config.freqHz);
    // 크로스오버는 밴드 7번(마지막 슬롯) 사용
    await writeBiquad(channelIndex, _bandsPerChannel - 1, coeffs);
  }

  @override
  Future<void> writeDelay(int channelIndex, double delayMs) async {
    // TODO: ADAU1701 딜레이 레지스터 주소 확인 후 구현
    // 현재 TUNAI ONE은 딜레이 미사용
  }

  @override
  Future<void> writeGain(int channelIndex, double gainDb) async {
    // TODO: ADAU1701 게인 셀 주소 확인 후 구현
  }

  @override
  Future<void> writeSubsonicFilter(int channelIndex, double freqHz) async {
    final coeffs = _buildHpf(freqHz);
    await writeBiquad(channelIndex, _bandsPerChannel - 2, coeffs);
  }

  @override
  Future<DspState> readCurrentState() async {
    // ADAU1701: 읽기 미지원 (write-only BLE 프로토콜)
    return const DspState(raw: {});
  }

  // ── 내부 유틸 ─────────────────────────────────────────────

  static BiquadCoeffs _buildHpf(double freq) {
    final raw = DspCompilerSafety.calculateHpf(freq);
    return BiquadCoeffs(b0: raw.b0, b1: raw.b1, b2: raw.b2, a1: raw.a1, a2: raw.a2);
  }

  static BiquadCoeffs _buildLpf(double freq) {
    final w0 = 2 * pi * freq / DspCompiler.sampleRate;
    const q = 0.7071;
    final alpha = sin(w0) / (2 * q);
    final cosW = cos(w0);

    final b0 = (1 - cosW) / 2;
    final b1 = 1 - cosW;
    final b2 = (1 - cosW) / 2;
    final a0 = 1 + alpha;
    final a1 = -2 * cosW;
    final a2 = 1 - alpha;

    return BiquadCoeffs(
      b0: b0 / a0, b1: b1 / a0, b2: b2 / a0,
      a1: -(a1 / a0), a2: -(a2 / a0),
    );
  }
}

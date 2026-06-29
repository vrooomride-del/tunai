import 'dart:math';
import 'dart:typed_data';
import 'dsp_adapter.dart';
import '../../features/dsp/dsp_compiler.dart';

/// ADAU1701 (TUNAI ONE / JAB4) BLE 어댑터 — 스테레오 4채널
///
/// 채널 인덱스 (SystemProfile.channels 순서와 일치):
///   0: Woofer  L  1: Woofer  R
///   2: Tweeter L  3: Tweeter R
///
/// PRAM 레이아웃 (TODO: SigmaStudio export 후 정확한 주소로 교체):
///   ch0 WooferL  PEQ: 0x0010,  ch1 WooferR  PEQ: 0x0030 (estimate)
///   ch2 TweeterL PEQ: 0x0050,  ch3 TweeterR PEQ: 0x0070 (estimate)
///
/// Gain 레지스터 (SigmaStudio IC Memory Map 확인 2026-06-20):
///   ch0 WooferL = addr 7 (확정), ch1 WooferR = addr 5 (estimate)
///   ch2 TweeterL = addr 6 (확정), ch3 TweeterR = addr 4 (estimate)
class Adau1701Adapter implements DspAdapter {
  final RawWriteFn _writeRaw;

  static const int _peqBands = 6; // 채널당 PEQ 슬롯 수
  static const int _xoSlotsPerSide = 4; // LR48 최대 4 biquad

  // 채널별 PRAM 베이스 (ch0~ch3)
  static const List<int> _pramBase = [0x0010, 0x0030, 0x0050, 0x0070];

  // 채널별 XO 베이스 = PRAM 베이스 + PEQ 슬롯 수 × 5
  static int _xoBase(int channelIndex) =>
      _pramBase[channelIndex] + _peqBands * 5;

  // 채널별 Gain 레지스터 주소
  // ch0 WooferL=7, ch1 WooferR=5(est), ch2 TweeterL=6, ch3 TweeterR=4(est)
  static const List<int> _gainAddr = [7, 5, 6, 4];

  // 채널별 Delay 레지스터 주소 (TODO: 미확정)
  static const List<int> _delayAddr = [0x0000, 0x0000, 0x0000, 0x0000];

  Adau1701Adapter({required RawWriteFn writeRaw}) : _writeRaw = writeRaw;

  // ── PEQ 밴드 ─────────────────────────────────────────────────
  @override
  Future<void> writeBiquad(int channelIndex, int bandIndex, BiquadCoeffs coeffs) async {
    assert(bandIndex < _peqBands);
    final addr = _pramBase[channelIndex] + bandIndex * 5;
    await _writeRaw(_buildFrame(addr, [
      coeffs.b0, coeffs.b1, coeffs.b2, coeffs.a1, coeffs.a2,
    ]));
  }

  // ── 크로스오버 ───────────────────────────────────────────────
  @override
  Future<void> writeCrossover(int channelIndex, CrossoverConfig config) async {
    final xoType = _mapSlope(config.slope);
    if (xoType == null) return;

    final isHpf = config.side == FilterSide.hpf;
    final biquads = _calculateCrossoverBiquads(config.freqHz, isHpf, xoType);

    final xoBase = _xoBase(channelIndex);
    final slotBase = isHpf ? 0 : _xoSlotsPerSide;

    for (var i = 0; i < biquads.length; i++) {
      final addr = xoBase + (slotBase + i) * 5;
      await _writeRaw(_buildFrame(addr, [
        biquads[i].b0, biquads[i].b1, biquads[i].b2,
        biquads[i].a1, biquads[i].a2,
      ]));
    }
    // 남은 슬롯 → passthrough
    for (var i = biquads.length; i < _xoSlotsPerSide; i++) {
      final addr = xoBase + (slotBase + i) * 5;
      await _writeRaw(_buildFrame(addr, [1.0, 0.0, 0.0, 0.0, 0.0]));
    }
  }

  // ── Gain ─────────────────────────────────────────────────────
  @override
  Future<void> writeGain(int channelIndex, double gainDb) async {
    final addr = _gainAddr[channelIndex];
    if (addr == 0x0000) return; // TODO: 주소 미확정
    final linear = pow(10.0, gainDb / 20.0).toDouble();
    await _writeRaw(_buildFrame(addr, [linear, 0.0, 0.0, 0.0, 0.0]));
  }

  // ── Delay ────────────────────────────────────────────────────
  @override
  Future<void> writeDelay(int channelIndex, double delayMs) async {
    final addr = _delayAddr[channelIndex];
    if (addr == 0x0000) return; // TODO: 주소 미확정
    final samples = (delayMs / 1000.0 * DspCompiler.sampleRate).round();
    await _writeRaw(_buildRawFrame(addr, [
      DspCompiler.toBytes4(samples), [0, 0, 0, 0], [0, 0, 0, 0],
      [0, 0, 0, 0], [0, 0, 0, 0],
    ]));
  }

  // ── 서브소닉 HPF ─────────────────────────────────────────────
  @override
  Future<void> writeSubsonicFilter(int channelIndex, double freqHz) async {
    final biquads = _calculateCrossoverBiquads(freqHz, true, _XoType.bw2);
    // XO HP 슬롯의 마지막 슬롯(슬롯 3)을 서브소닉 전용 사용
    final addr = _xoBase(channelIndex) + (_xoSlotsPerSide - 1) * 5;
    final c = biquads[0];
    await _writeRaw(_buildFrame(addr, [c.b0, c.b1, c.b2, c.a1, c.a2]));
  }

  @override
  Future<DspState> readCurrentState() async => const DspState(raw: {});

  // ── 크로스오버 biquad 계산 ───────────────────────────────────
  static List<_BQ> _calculateCrossoverBiquads(
      double freqHz, bool isHpf, _XoType type) {
    switch (type) {
      case _XoType.bw2:
        return [_xoBiquad(freqHz, isHpf, 0.7071)];
      case _XoType.bw4:
        return [_xoBiquad(freqHz, isHpf, 0.5412),
                _xoBiquad(freqHz, isHpf, 1.3066)];
      case _XoType.lr2:
        return [_xoBiquad(freqHz, isHpf, 0.5)];
      case _XoType.lr4:
        return [_xoBiquad(freqHz, isHpf, 0.7071),
                _xoBiquad(freqHz, isHpf, 0.7071)];
      case _XoType.lr8:
        return [_xoBiquad(freqHz, isHpf, 0.5412),
                _xoBiquad(freqHz, isHpf, 1.3066),
                _xoBiquad(freqHz, isHpf, 0.5412),
                _xoBiquad(freqHz, isHpf, 1.3066)];
    }
  }

  static _BQ _xoBiquad(double freqHz, bool isHpf, double q) {
    final w0 = 2 * pi * freqHz / DspCompiler.sampleRate;
    final alpha = sin(w0) / (2 * q);
    final cosW = cos(w0);
    double b0, b1, b2;
    if (isHpf) {
      b0 = (1 + cosW) / 2; b1 = -(1 + cosW); b2 = (1 + cosW) / 2;
    } else {
      b0 = (1 - cosW) / 2; b1 = 1 - cosW;    b2 = (1 - cosW) / 2;
    }
    final a0 = 1 + alpha;
    final a1 = -2 * cosW;
    final a2 = 1 - alpha;
    return _BQ(b0/a0, b1/a0, b2/a0, -(a1/a0), -(a2/a0));
  }

  // ── 프레임 빌더 ──────────────────────────────────────────────
  Uint8List _buildFrame(int addr, List<double> coeffs5) {
    final bytes = <int>[];
    for (final c in coeffs5) {
      bytes.addAll(DspCompiler.toBytes4(DspCompiler.toFixed523(c)));
    }
    final packet = RegisterPacket(pramTargetAddr: addr, coeffBytes: bytes);
    return DspCompiler.buildBleFrame(packet);
  }

  Uint8List _buildRawFrame(int addr, List<List<int>> words5) {
    final bytes = <int>[];
    for (final w in words5) { bytes.addAll(w); }
    final packet = RegisterPacket(pramTargetAddr: addr, coeffBytes: bytes);
    return DspCompiler.buildBleFrame(packet);
  }

  static _XoType? _mapSlope(CrossoverSlope slope) {
    switch (slope) {
      case CrossoverSlope.bypass: return null;
      case CrossoverSlope.bw2:   return _XoType.bw2;
      case CrossoverSlope.bw4:   return _XoType.bw4;
      case CrossoverSlope.lr2:   return _XoType.lr2;
      case CrossoverSlope.lr4:   return _XoType.lr4;
      case CrossoverSlope.lr8:   return _XoType.lr8;
    }
  }
}

// 로컬 biquad 계수 레코드
class _BQ {
  final double b0, b1, b2, a1, a2;
  const _BQ(this.b0, this.b1, this.b2, this.a1, this.a2);
}

enum _XoType { bw2, bw4, lr2, lr4, lr8 }

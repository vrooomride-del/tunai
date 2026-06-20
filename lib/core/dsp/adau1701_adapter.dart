import 'dart:math';
import 'dart:typed_data';
import 'dsp_adapter.dart';
import '../../features/dsp/dsp_compiler.dart';

/// ADAU1701 (TUNAI ONE / JAB4) BLE 어댑터
///
/// PRAM 레이아웃 (TODO: SigmaStudio export 후 정확한 주소로 교체):
///   Woofer  밴드 0–5 → 0x0010 + band * 5
///   Tweeter 밴드 0–5 → 0x0050 + band * 5
///   크로스오버 HP/LP  → PEQ 직후 슬롯 (TODO: 주소 미확정)
///   Gain              → TODO
///   Delay             → TODO
class Adau1701Adapter implements DspAdapter {
  final RawWriteFn _writeRaw;

  static const int _basePramWoofer  = 0x0010;
  static const int _basePramTweeter = 0x0050;
  static const int _peqBands        = 6; // 채널당 PEQ 슬롯 수

  // XO: PEQ 뒤에 채널당 [HP×4슬롯][LP×4슬롯]
  // Woofer  XO base: 0x0010 + 6*5 = 0x003A
  // Tweeter XO base: 0x0050 + 6*5 = 0x007A
  static const int _xoWooferBase  = _basePramWoofer  + _peqBands * 5;
  static const int _xoTweeterBase = _basePramTweeter + _peqBands * 5;
  static const int _xoSlotsPerSide = 4; // LR48 최대 4 biquad

  // SigmaStudio IC Memory Map 확인 (2026-06-20)
  // Vol(ch0 Woofer) = addr 7, Vol_2(ch1 Tweeter) = addr 6
  static const int _gainWoofer  = 7;
  static const int _gainTweeter = 6;
  static const int _delayWoofer  = 0x0000; // ← TODO
  static const int _delayTweeter = 0x0000; // ← TODO

  Adau1701Adapter({required RawWriteFn writeRaw}) : _writeRaw = writeRaw;

  // ── PEQ 밴드 ─────────────────────────────────────────────────
  @override
  Future<void> writeBiquad(int channelIndex, int bandIndex, BiquadCoeffs coeffs) async {
    assert(bandIndex < _peqBands);
    final base = channelIndex == 0 ? _basePramWoofer : _basePramTweeter;
    final addr = base + bandIndex * 5;
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

    final xoBase = channelIndex == 0 ? _xoWooferBase : _xoTweeterBase;
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
    final addr = channelIndex == 0 ? _gainWoofer : _gainTweeter;
    if (addr == 0x0000) return; // TODO: 주소 미확정
    final linear = pow(10.0, gainDb / 20.0).toDouble();
    await _writeRaw(_buildFrame(addr, [linear, 0.0, 0.0, 0.0, 0.0]));
  }

  // ── Delay ────────────────────────────────────────────────────
  @override
  Future<void> writeDelay(int channelIndex, double delayMs) async {
    final addr = channelIndex == 0 ? _delayWoofer : _delayTweeter;
    if (addr == 0x0000) return; // TODO: 주소 미확정
    final samples = (delayMs / 1000.0 * DspCompiler.sampleRate).round();
    // 샘플 카운트를 5.23 고정소수점으로 인코딩 (정수값)
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
    final xoBase = channelIndex == 0 ? _xoWooferBase : _xoTweeterBase;
    final addr = xoBase + (_xoSlotsPerSide - 1) * 5;
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

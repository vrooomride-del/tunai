import 'dart:math';
import 'dart:typed_data';
import 'dsp_adapter.dart';
import '../../features/dsp/dsp_compiler.dart';

/// ADAU1466 + CS42448 어댑터 (tunai mobile)
///
/// 채널 인덱스 (SystemProfile.channels 순서와 일치):
///   0: TWE L  1: TWE R  2: MID L  3: MID R  4: WOO L  5: WOO R
///
/// SigmaStudio PRAM 주소 (2026-07-01):
///   Volume : 545, 548, 551, 554, 557, 560  — SPI 쓰기 검증 완료 ✓
///   Delay  : 562, 563, 564, 565, 566, 567  — 채널 묶음 패턴 추정, 실기기 미확인
///   PEQ/XO : 미확정 — SigmaStudio .dspproj export 후 ParameterRAM.dat 확인 필요
///
/// 고정소수점: ADAU1466 = 5.27 (ADAU1701의 5.23과 다름)
class Adau1466Adapter implements DspAdapter {
  final RawWriteFn _writeRaw;

  static const int _peqBands       = 20;
  static const int _xoSlotsPerSide = 4; // LR48 최대 4 biquad

  // ── Volume 셀 PRAM 주소 (ch0~ch5) ─────────────────────────────
  // SigmaStudio SPI 쓰기 검증 완료 (2026-07-01) ✓
  static const List<int> _gainAddr = [545, 548, 551, 554, 557, 560];

  // ── Delay 셀 PRAM 주소 (ch0~ch5) ──────────────────────────────
  // 채널 묶음의 연속 배치 패턴으로 추정 — 실기기 확인 필요 (2026-07-01)
  static const List<int> _delayAddr = [562, 563, 564, 565, 566, 567];

  // ── PEQ / XO 주소 ─────────────────────────────────────────────
  // TODO: SigmaStudio .dspproj export → ParameterRAM.dat 확인 후 교체
  // 현재값은 ADAU1701 패턴 기반 추정치 — 실기기 미확인
  static const int _peqBase     = 0x0100; // 추정 — 미확정
  static const int _peqChStride = _peqBands * 5; // ch당 100 워드
  static const int _xoBase      = _peqBase + 6 * _peqChStride; // 추정
  static const int _xoChStride  = _xoSlotsPerSide * 2 * 5; // (HP+LP) × 5워드

  Adau1466Adapter({required RawWriteFn writeRaw}) : _writeRaw = writeRaw;

  // ── PEQ 밴드 ─────────────────────────────────────────────────
  // 5.27 biquad — PEQ 주소 미확정
  @override
  Future<void> writeBiquad(int channelIndex, int bandIndex, BiquadCoeffs coeffs) async {
    assert(bandIndex < _peqBands);
    final addr = _peqBase + channelIndex * _peqChStride + bandIndex * 5;
    await _writeRaw(_buildFrame527(addr, [
      coeffs.b0, coeffs.b1, coeffs.b2, coeffs.a1, coeffs.a2,
    ]));
  }

  // ── 크로스오버 ───────────────────────────────────────────────
  // XO 주소 미확정 — SigmaStudio export 후 갱신 필요
  @override
  Future<void> writeCrossover(int channelIndex, CrossoverConfig config) async {
    final xoType = _mapSlope(config.slope);
    if (xoType == null) return;

    final isHpf = config.side == FilterSide.hpf;
    final biquads = _calculateCrossoverBiquads(config.freqHz, isHpf, xoType);

    final chBase   = _xoBase + channelIndex * _xoChStride;
    final slotBase = isHpf ? 0 : _xoSlotsPerSide;

    for (var i = 0; i < biquads.length; i++) {
      final addr = chBase + (slotBase + i) * 5;
      await _writeRaw(_buildFrame527(addr, [
        biquads[i].b0, biquads[i].b1, biquads[i].b2,
        biquads[i].a1, biquads[i].a2,
      ]));
    }
    for (var i = biquads.length; i < _xoSlotsPerSide; i++) {
      await _writeRaw(_buildFrame527(
          chBase + (slotBase + i) * 5, [1.0, 0.0, 0.0, 0.0, 0.0]));
    }
  }

  // ── Gain ─────────────────────────────────────────────────────
  // Volume 셀: 5.27 선형값 1워드 — 검증됨 ✓
  @override
  Future<void> writeGain(int channelIndex, double gainDb) async {
    if (channelIndex >= _gainAddr.length) return;
    final linear = pow(10.0, gainDb / 20.0).toDouble();
    await _writeRaw(_buildFrame527(_gainAddr[channelIndex],
        [linear, 0.0, 0.0, 0.0, 0.0]));
  }

  // ── Delay ────────────────────────────────────────────────────
  // 28.0 샘플 카운트 — 주소 추정값, 실기기 확인 필요
  @override
  Future<void> writeDelay(int channelIndex, double delayMs) async {
    if (channelIndex >= _delayAddr.length) return;
    final samples = (delayMs / 1000.0 * DspCompiler.sampleRate).round();
    await _writeRaw(_buildRawFrame(_delayAddr[channelIndex], [
      DspCompiler.toBytes4(samples), [0, 0, 0, 0], [0, 0, 0, 0],
      [0, 0, 0, 0], [0, 0, 0, 0],
    ]));
  }

  // ── 서브소닉 HPF ─────────────────────────────────────────────
  // XO HP 슬롯 마지막(슬롯 3)을 서브소닉 전용 사용 — 주소 미확정
  @override
  Future<void> writeSubsonicFilter(int channelIndex, double freqHz) async {
    final biquads = _calculateCrossoverBiquads(freqHz, true, _XoType.bw2);
    final addr = _xoBase + channelIndex * _xoChStride + (_xoSlotsPerSide - 1) * 5;
    final c = biquads[0];
    await _writeRaw(_buildFrame527(addr, [c.b0, c.b1, c.b2, c.a1, c.a2]));
  }

  @override
  Future<DspState> readCurrentState() async => const DspState(raw: {});

  // ── 프레임 빌더 (5.27) ──────────────────────────────────────
  Uint8List _buildFrame527(int addr, List<double> coeffs5) {
    final bytes = <int>[];
    for (final c in coeffs5) {
      bytes.addAll(DspCompiler.toBytes4(DspCompiler.toFixed527(c)));
    }
    return DspCompiler.buildBleFrame(
        RegisterPacket(pramTargetAddr: addr, coeffBytes: bytes));
  }

  Uint8List _buildRawFrame(int addr, List<List<int>> words5) {
    final bytes = <int>[];
    for (final w in words5) { bytes.addAll(w); }
    return DspCompiler.buildBleFrame(
        RegisterPacket(pramTargetAddr: addr, coeffBytes: bytes));
  }

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

class _BQ {
  final double b0, b1, b2, a1, a2;
  const _BQ(this.b0, this.b1, this.b2, this.a1, this.a2);
}

enum _XoType { bw2, bw4, lr2, lr4, lr8 }

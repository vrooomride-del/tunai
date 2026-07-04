import 'dart:math';
import 'dart:typed_data';
import 'dsp_adapter.dart';
import '../../features/dsp/dsp_compiler.dart';

/// ADAU1466 + CS42448 어댑터 (tunai mobile)
///
/// 채널 인덱스 (SystemProfile.channels 순서와 일치):
///   0: TWE L  1: TWE R  2: MID L  3: MID R  4: WOO L  5: WOO R
///
/// SigmaStudio PRAM 주소 (1466_cs42448_18out_eng 실제 export 대조 확정, 2026-07-04):
///   Volume : 545, 548, 551, 554, 557, 560 (slew_mode = target+1) — 8.24 fixed, BE.
///            SPI 쓰기 검증 완료 — 변경 없음
///   Delay  : 562, 567, 563, 566, 564, 565 (ch0~5) — 정수 샘플(ms×48000/1000).
///            채널 순서는 Volume과 동일 CH0~5로 가정 — 실기기에서 채널별로 값을
///            넣어 소리로 확인 필요
///   PEQ    : base=410, 밴드n(0~14) = 410+n×5, 15밴드, addr 410~484.
///            계수 순서 B2,B1,B0,A2,A1 (ADAU1701 신 펌웨어의 B0,B1,B2,A0,A1과
///            다르니 주의). 채널별 스트라이드는 이번 export에 없음 — 현재는
///            모든 채널이 410 기준 단일 15밴드를 공유하는 것으로 처리(확인된
///            정보 그대로). 채널별 개별 PEQ가 필요하면 추가 확인 필요
///   HPF/LPF: 신규 발견 — PEQ/Delay와 구조가 전혀 다름, SafeLoad 방식 필요
///            HPF target=24873~24877(5워드), slewMode=401
///            LPF target=24878~24882(5워드), slewMode=407
///            SafeLoad 레지스터 영역 24576~24583과 인접 — 일반 write가 아니라
///            SigmaStudio SafeLoad 프로토콜(데이터→SAFELOAD_DATA0~4, 주소→
///            SAFELOAD_ADDRESS, 개수→SAFELOAD_NUM 순으로 써서 트리거)이 필요할
///            가능성이 높다. **불확실 — 실기기 테스트로 검증 전까지
///            [experimentalXoWriteEnabled]는 항상 false로 유지할 것.**
///   Mute   : 16채널, addr 1081~1096 (참고용, 미구현)
///   Compressor: addr 489~542 (범위만 확인, 세부 미매핑, 참고용)
///
/// 고정소수점: ADAU1466 = 5.27 (ADAU1701의 5.23과 다름)
class Adau1466Adapter implements DspAdapter {
  final RawWriteFn _writeRaw;

  /// HPF/LPF는 SafeLoad 프로토콜이 실기기 검증되지 않았다 — 항상 false로 유지할 것.
  /// true로 바꾸면 미검증 SafeLoad 시퀀스가 그대로 전송된다.
  static bool experimentalXoWriteEnabled = false;

  static const int _peqBands = 15;
  static const int _peqBase  = 410; // 확정 — 채널별 스트라이드 미확인

  // ── Volume 셀 PRAM 주소 (ch0~ch5) ─────────────────────────────
  // SigmaStudio SPI 쓰기 검증 완료 — 변경 없음
  static const List<int> _gainAddr = [545, 548, 551, 554, 557, 560];

  // ── Delay 셀 PRAM 주소 (ch0~ch5, 확정) ─────────────────────────
  // Volume과 동일 CH0~5 순서로 가정 — 실기기에서 채널별 소리 확인 필요
  static const List<int> _delayAddr = [562, 567, 563, 566, 564, 565];

  // ── HPF/LPF SafeLoad 대상 주소 (신규 발견, 미검증) ─────────────
  static const int _hpfTargetAddr = 24873; // 5워드, slewMode=401
  static const int _lpfTargetAddr = 24878; // 5워드, slewMode=407

  // SafeLoad 레지스터 배치 — 표준 ADI SafeLoad 규약(DATA0~4/ADDRESS/NUM)을
  // 가정한 것일 뿐, 이 프로젝트의 실제 24576~24583 배치와 일치하는지는
  // 실기기로 확인되지 않았다.
  static const int _safeloadData0   = 24576; // SAFELOAD_DATA0~4 (24576~24580, 가정)
  static const int _safeloadAddress = 24581; // 목표 주소 레지스터 (가정)
  static const int _safeloadNum     = 24582; // 개수 레지스터 — 쓰면 트리거 (가정)

  Adau1466Adapter({required RawWriteFn writeRaw}) : _writeRaw = writeRaw;

  // ── PEQ 밴드 (확정 주소, 채널 스트라이드 미확인) ────────────────
  @override
  Future<void> writeBiquad(int channelIndex, int bandIndex, BiquadCoeffs coeffs) async {
    assert(bandIndex < _peqBands);
    // TODO: 채널별 PEQ 오프셋 미확인 — 현재 모든 채널이 410 기준 단일 15밴드를 공유
    final addr = _peqBase + bandIndex * 5;
    await _writeRaw(_buildFrame527(addr, [
      coeffs.b2, coeffs.b1, coeffs.b0, coeffs.a2, coeffs.a1,
    ]));
  }

  // ── 크로스오버 (SafeLoad 스텁 — 기본 잠금) ──────────────────────
  // SafeLoad 프로토콜이 실기기 검증되지 않아 experimentalXoWriteEnabled가
  // false인 동안은 계산만 하고 아무 것도 전송하지 않는다.
  @override
  Future<void> writeCrossover(int channelIndex, CrossoverConfig config) async {
    if (!experimentalXoWriteEnabled) return; // TODO: SafeLoad 실기기 검증 전까지 잠금

    final xoType = _mapSlope(config.slope);
    if (xoType == null) return;

    final isHpf = config.side == FilterSide.hpf;
    final biquads = _calculateCrossoverBiquads(config.freqHz, isHpf, xoType);
    if (biquads.length != 1) return; // target당 5워드(1스테이지)뿐 — 이상 슬로프 미지원

    final targetAddr = isHpf ? _hpfTargetAddr : _lpfTargetAddr;
    final c = biquads[0];
    // PEQ와 동일한 계수 순서(B2,B1,B0,A2,A1)를 가정 — XO 자체는 별도 확인 안 됨
    await _writeSafeload(targetAddr, [c.b2, c.b1, c.b0, c.a2, c.a1]);
  }

  // ── Gain ─────────────────────────────────────────────────────
  // Volume 셀: 5.27 선형값 1워드 — 검증됨, 변경 없음
  @override
  Future<void> writeGain(int channelIndex, double gainDb) async {
    if (channelIndex >= _gainAddr.length) return;
    final linear = pow(10.0, gainDb / 20.0).toDouble();
    await _writeRaw(_buildFrame527(_gainAddr[channelIndex],
        [linear, 0.0, 0.0, 0.0, 0.0]));
  }

  // ── Delay ────────────────────────────────────────────────────
  // 28.0 샘플 카운트 — 주소 확정, 채널 순서는 Volume과 동일 가정(실기기 확인 필요)
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
  // 신 XO 구조엔 채널당 여분 슬롯이 없음(HPF target 하나뿐, 그마저 SafeLoad
  // 미검증) — 별도 subsonic 슬롯 없이 no-op 유지
  @override
  Future<void> writeSubsonicFilter(int channelIndex, double freqHz) async {}

  @override
  Future<DspState> readCurrentState() async => const DspState(raw: {});

  // ── SafeLoad 쓰기 (표준 ADI SafeLoad 레지스터 배치 가정 — 미검증) ──
  // SAFELOAD_DATA0~4에 계수 5워드, SAFELOAD_ADDRESS에 목표 주소, SAFELOAD_NUM에
  // 개수(5)를 쓰면 하드웨어가 원자적으로 타겟에 반영한다는 것이 일반적인 ADI
  // SafeLoad 동작이나, 이 프로젝트의 실제 레지스터 배치와 정확히 일치하는지는
  // 실기기로 확인되지 않았다.
  Future<void> _writeSafeload(int targetAddr, List<double> coeffs5) async {
    for (var i = 0; i < coeffs5.length; i++) {
      await _writeRaw(_buildFrame527(_safeloadData0 + i, [coeffs5[i], 0.0, 0.0, 0.0, 0.0]));
    }
    await _writeRaw(_buildRawFrame(_safeloadAddress, [
      DspCompiler.toBytes4(targetAddr), [0, 0, 0, 0], [0, 0, 0, 0],
      [0, 0, 0, 0], [0, 0, 0, 0],
    ]));
    await _writeRaw(_buildRawFrame(_safeloadNum, [
      DspCompiler.toBytes4(coeffs5.length), [0, 0, 0, 0], [0, 0, 0, 0],
      [0, 0, 0, 0], [0, 0, 0, 0],
    ]));
  }

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

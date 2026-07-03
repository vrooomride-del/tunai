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
/// XO 필터 구조 (SigmaStudio 스키매틱 직접 확인, 2026-07-04):
/// 2웨이 크로스오버, 물리 DAC 4채널 각각 HPF 블록 → LPF 블록 순으로 캐스케이드:
///
///   DAC0 (Tweeter A): Filter1_4  (14~111,  HPF) → Filter1_11 (310~407, LPF@20kHz≈통과)
///   DAC1 (Tweeter B): Filter1_9  (112~209, HPF) → Filter1_10 (212~309, LPF@20kHz≈통과)
///   DAC2 (Woofer A):  Filter1_5  (408~505, HPF@150Hz≈무시) → Filter1_6 (604~701, LPF)
///   DAC3 (Woofer B):  Filter1_8  (506~603, HPF@150Hz≈무시) → Filter1_7 (702~799, LPF)
///
/// 즉 트위터 체인은 HPF가, 우퍼 체인은 LPF가 실질적 크로스오버 지점이다(반대쪽은
/// 스키매틱 기본값이 사실상 통과/무시로 설정돼 있을 뿐, 실제로 쓸 수 있는 필터임).
/// ch(0/1=Woofer, 2/3=Tweeter) ↔ DAC(0~3) 매핑은 아래 _xoBlockBase 참고.
/// 2XMixer1_3(210~211)은 참고용(미사용) — 현재 writeCrossover 대상 아님.
///
/// **각 98워드 블록 내부의 정확한 스테이지 오프셋(주파수/Q가 몇 번째 워드인지)과
/// 계수 fixed-point 포맷은 실측 write 캡처로 검증되지 않았다.** 아래 구현은
/// "블록 시작 = 1번째 스테이지(B2,B1,B0,A2,A1 5워드)"라는 가장 보수적인 가정을
/// 사용하며, 실기기 검증 전까지 [experimentalXoWriteEnabled]가 기본 false라
/// 실제로는 아무 것도 전송되지 않는다. 상위 레이어에서 "실험적 기능" 동의를
/// 받은 뒤에만 명시적으로 true로 설정할 것.
///
///   writeBiquad(PEQ)는 no-op 유지 — 이 스키매틱엔 PEQ 모듈이 안 보인다. 단,
///   Miumax 공식 PC UI 화면에는 채널별 10-Band EQ가 표시돼 있어 다른 펌웨어
///   버전이 존재할 가능성이 있음 — 미해결로 남김(HANDOFF.md 참고)
///   writeDelay는 no-op 유지 — 이 스키매틱엔 Delay 블록이 안 보인다(Miumax UI엔
///   있었음 — 별도 확인 필요, HANDOFF.md 참고)
///
///   참고용(미사용): SW vol1=800, Gain3/Gain1=801~804, Inv1_10/Inv1_9(극성)=810/811
///
/// Gain 레지스터 (SigmaStudio IC Memory Map 확정, 변경 없음):
///   Vol(우퍼, 스테레오 링크) = addr 7 → ch0/ch1 공유
///   Vol_2(트위터, 스테레오 링크) = addr 6 → ch2/ch3 공유
///
/// Mute 레지스터 (확정, 변경 없음):
///   채널(밴드) 뮤트 — Woofer=11, Tweeter=12 (스테레오 링크)
///   출력 뮤트 — 물리 출력 채널별 개별: ch0=805, ch1=806, ch2=807, ch3=808
class Adau1701Adapter implements DspAdapter {
  final RawWriteFn _writeRaw;

  /// 실기기 write 캡처로 위 오프셋/포맷을 검증하기 전까지 안전장치로 기본 false.
  /// true가 되기 전엔 writeCrossover가 계산만 하고 아무 것도 전송하지 않는다.
  /// UI 쪽 "실험적 기능" 동의 토글은 이번 세션 스코프 밖 — 상위 레이어에서 옵트인할 것.
  static bool experimentalXoWriteEnabled = false;

  // 채널(0/1=Woofer, 2/3=Tweeter) → (HPF 블록, LPF 블록) 주소.
  // ch0 WooferL=DAC2, ch1 WooferR=DAC3, ch2 TweeterL=DAC0, ch3 TweeterR=DAC1
  // (L/R ↔ A/B 대응은 임의 — 동일 그룹 내에서는 같은 크로스오버 설정을 쓰므로 무관)
  static const List<({int hpf, int lpf})> _xoBlockBase = [
    (hpf: 408, lpf: 604), // ch0 WooferL  = DAC2 WooferA:  Filter1_5 → Filter1_6
    (hpf: 506, lpf: 702), // ch1 WooferR  = DAC3 WooferB:  Filter1_8 → Filter1_7
    (hpf: 14,  lpf: 310), // ch2 TweeterL = DAC0 TweeterA: Filter1_4 → Filter1_11
    (hpf: 112, lpf: 212), // ch3 TweeterR = DAC1 TweeterB: Filter1_9 → Filter1_10
  ];

  static int _xoBlockAddr(int channelIndex, FilterSide side) {
    final entry = _xoBlockBase[channelIndex];
    return side == FilterSide.hpf ? entry.hpf : entry.lpf;
  }

  // 채널별 Gain 레지스터 주소 — Vol(우퍼)=7, Vol_2(트위터)=6, 스테레오 링크라 L/R 공유 (변경 없음)
  static const List<int> _gainAddr = [7, 7, 6, 6];

  // 채널(밴드) 뮤트 주소 — Woofer=11, Tweeter=12, 스테레오 링크라 L/R 공유 (변경 없음)
  static const List<int> _channelMuteAddr = [11, 11, 12, 12];

  // 출력 뮤트 주소 — 물리 출력 채널별 개별 (변경 없음)
  static const List<int> _outputMuteAddr = [805, 806, 807, 808];

  // 채널별 Delay 레지스터 주소 — 펌웨어 미구현, no-op 유지 (변경 없음)
  static const List<int> _delayAddr = [0x0000, 0x0000, 0x0000, 0x0000];

  Adau1701Adapter({required RawWriteFn writeRaw}) : _writeRaw = writeRaw;

  // ── PEQ ──────────────────────────────────────────────────────
  // 이 스키매틱엔 PEQ 모듈이 없음 — no-op. (Miumax UI의 10-Band EQ 표시는
  // 별도 펌웨어 버전 가능성이 있어 미해결로 남김 — HANDOFF.md 참고)
  @override
  Future<void> writeBiquad(int channelIndex, int bandIndex, BiquadCoeffs coeffs) async {}

  // ── 크로스오버 ───────────────────────────────────────────────
  @override
  Future<void> writeCrossover(int channelIndex, CrossoverConfig config) async {
    if (!experimentalXoWriteEnabled) return; // TODO: 실기기 검증 후 기본값 재검토

    final xoType = _mapSlope(config.slope);
    if (xoType == null) return; // bypass

    final isHpf = config.side == FilterSide.hpf;
    final biquads = _calculateCrossoverBiquads(config.freqHz, isHpf, xoType);
    final base = _xoBlockAddr(channelIndex, config.side);

    for (var i = 0; i < biquads.length; i++) {
      final addr = base + i * 5;
      final c = biquads[i];
      // SigmaStudio 2nd-order filter 표준 계수 순서: B2,B1,B0,A2,A1 (fixed-point
      // 포맷은 기존 5.23 가정 유지 — 재확인 필요)
      await _writeRaw(_buildFrame(addr, [c.b2, c.b1, c.b0, c.a2, c.a1]));
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

  // ── Mute (확정 주소, DspAdapter 인터페이스 밖 — Adau1701 전용 부가 기능) ──
  /// 채널(밴드) 단위 뮤트 — Woofer/Tweeter 스테레오 링크 블록이라 L/R 공유
  Future<void> writeChannelMute(int channelIndex, bool muted) async {
    final addr = _channelMuteAddr[channelIndex];
    await _writeRaw(_buildFrame(addr, [muted ? 0.0 : 1.0, 0.0, 0.0, 0.0, 0.0]));
  }

  /// 출력 단위 뮤트 — 물리 출력 채널 개별
  Future<void> writeOutputMute(int channelIndex, bool muted) async {
    final addr = _outputMuteAddr[channelIndex];
    await _writeRaw(_buildFrame(addr, [muted ? 0.0 : 1.0, 0.0, 0.0, 0.0, 0.0]));
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
  // 이 구조엔 별도 subsonic 개념이 없음(Woofer 채널의 HPF 블록이 150Hz 부근
  // 사실상 무시 상태로 확인됐지만, 정확한 오프셋/기본값이 실측 검증되지 않아
  // 이번 세션에선 그대로 no-op 유지)
  @override
  Future<void> writeSubsonicFilter(int channelIndex, double freqHz) async {}

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

// 로컬 biquad 계수 레코드 (b0,b1,b2,a1,a2 — 계산 편의상 표준 순서, 실제 write
// 시점에 [b2,b1,b0,a2,a1]로 재배열됨)
class _BQ {
  final double b0, b1, b2, a1, a2;
  const _BQ(this.b0, this.b1, this.b2, this.a1, this.a2);
}

enum _XoType { bw2, bw4, lr2, lr4, lr8 }

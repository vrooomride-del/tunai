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
/// XO 필터 구조 — 신 펌웨어(2026-07-04 재컴파일, 실제 export .h 기준 확정):
/// 기존 "General 2nd Order w var Param/Lookup/Slew"(96워드 lookup) 필터를 표준
/// "General (2nd order)"(5워드 biquad) 필터로 교체. 2웨이 크로스오버, 물리 DAC
/// 4채널 각각 HPF 블록 → LPF 블록(각 5워드, B0/B1/B2/A0/A1):
///
///   DAC0 (Tweeter A): GenFilter1   (41~45, HPF) → GenFilter1_5 (46~50, LPF)
///   DAC1 (Tweeter B): GenFilter1_2 (16~20, HPF) → GenFilter1_6 (26~30, LPF)
///   DAC2 (Woofer A):  GenFilter1_3 (21~25, HPF) → GenFilter1_7 (31~35, LPF)
///   DAC3 (Woofer B):  GenFilter1_4 (36~40, HPF) → GenFilter1_8 (51~55, LPF)
///
/// 트위터 체인은 HPF가, 우퍼 체인은 LPF가 실질적 크로스오버 지점이다. ch(0/1=Woofer,
/// 2/3=Tweeter) ↔ DAC(0~3) 매핑은 아래 _xoBlockBase 참고.
///
/// **각 필터 블록은 정확히 5워드(2차 biquad 1스테이지)뿐이다** — 이전 펌웨어의
/// 98워드 cascade와 달리 스테이지가 하나뿐이라, 다단 cascade가 필요한 슬로프
/// (bw4/lr4/lr8, 24dB/oct 이상)는 이 하드웨어로 구현 불가하다. 지원 가능한
/// 최대 슬로프는 bw2/lr2(12dB/oct, 1스테이지)뿐 — writeCrossover는 슬로프가
/// 2스테이지 이상을 요구하면 잘못된(더 얕은) 응답을 보내는 대신 아무 것도
/// 쓰지 않는다.
///
/// 계수 순서는 B0,B1,B2,A0,A1(SigmaStudio "General 2nd order filter" 표준
/// 파라미터명 — A0/A1은 우리 내부 표기의 a1/a2와 동일한 자리, 0-index 명명
/// 차이일 뿐) — 내부 _BQ(b0,b1,b2,a1,a2) 순서 그대로 write하면 된다(재배열 불필요).
/// Fixed-point는 ADAU1701 표준 5.23 가정 유지 — 이번 세션에서 실측 재확인은
/// 안 됐으니 실기기 테스트 시 저볼륨으로 시작할 것.
///
/// [experimentalXoWriteEnabled] 기본 true로 전환(신 펌웨어 주소/포맷이 실측
/// export .h 기준으로 확정됐다고 판단) — 단 **이 신 펌웨어가 아직 실기기에
/// 플래시되지 않았을 수 있다.** 실기기 테스트 전 반드시 SigmaStudio로 신
/// 펌웨어를 보드에 플래시할 것(HANDOFF.md 참고).
///
///   writeBiquad(PEQ)는 no-op 유지 — 이 신 펌웨어에도 PEQ 모듈이 없다(Miumax
///   UI의 EQ 표시는 별도 펌웨어 버전 얘기로 남겨둠 — HANDOFF.md 참고)
///   writeDelay는 no-op 유지 — 이 펌웨어에 Delay 블록이 없다
///
///   참고용(미사용): I2C 주소=0x34, Inv1_10/Inv1_9(극성)=810/811
///
/// Gain 레지스터 (변경 없음):
///   Vol(우퍼, 스테레오 링크) = addr 7 → ch0/ch1 공유
///   Vol_2(트위터, 스테레오 링크) = addr 6 → ch2/ch3 공유
///
/// Mute 레지스터 (변경 없음):
///   채널(밴드) 뮤트 — Woofer on/off=11, step=12 (스테레오 링크)
///   출력 뮤트 — Mute1=805~806, Mute0=807~808
class Adau1701Adapter implements DspAdapter {
  final RawWriteFn _writeRaw;

  /// 신 펌웨어(GenFilter, 5워드 표준 biquad) 주소맵이 실제 export .h 기준으로
  /// 확정돼 기본 true로 전환. 신 펌웨어가 보드에 아직 플래시되지 않았다면
  /// writeCrossover가 잘못된 주소에 값을 쓰게 되므로, 실기기 테스트 전 반드시
  /// SigmaStudio로 신 펌웨어를 플래시할 것.
  static bool experimentalXoWriteEnabled = true;

  // 채널(0/1=Woofer, 2/3=Tweeter) → (HPF 블록, LPF 블록) 주소.
  // ch0 WooferL=DAC2, ch1 WooferR=DAC3, ch2 TweeterL=DAC0, ch3 TweeterR=DAC1
  // (L/R ↔ A/B 대응은 임의 — 동일 그룹 내에서는 같은 크로스오버 설정을 쓰므로 무관)
  static const List<({int hpf, int lpf})> _xoBlockBase = [
    (hpf: 21, lpf: 31), // ch0 WooferL  = DAC2 WooferA:  GenFilter1_3 → GenFilter1_7
    (hpf: 36, lpf: 51), // ch1 WooferR  = DAC3 WooferB:  GenFilter1_4 → GenFilter1_8
    (hpf: 41, lpf: 46), // ch2 TweeterL = DAC0 TweeterA: GenFilter1   → GenFilter1_5
    (hpf: 16, lpf: 26), // ch3 TweeterR = DAC1 TweeterB: GenFilter1_2 → GenFilter1_6
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
  // 이 신 펌웨어에도 PEQ 모듈이 없음 — no-op. (Miumax UI의 10-Band EQ 표시는
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
    // 블록당 1스테이지(5워드)뿐 — 2스테이지 이상 필요한 슬로프(bw4/lr4/lr8)는
    // 얕은(잘못된) 응답을 보내는 대신 아무 것도 쓰지 않는다.
    if (biquads.length != 1) return;

    final addr = _xoBlockAddr(channelIndex, config.side);
    final c = biquads[0];
    // SigmaStudio "General 2nd order filter" 표준 파라미터 순서: B0,B1,B2,A0,A1
    // (A0/A1은 내부 a1/a2와 동일 자리 — 재배열 불필요)
    await _writeRaw(_buildFrame(addr, [c.b0, c.b1, c.b2, c.a1, c.a2]));
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
  // 이 구조엔 별도 subsonic 개념이 없음 — no-op 유지
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

// 로컬 biquad 계수 레코드 (b0,b1,b2,a1,a2)
class _BQ {
  final double b0, b1, b2, a1, a2;
  const _BQ(this.b0, this.b1, this.b2, this.a1, this.a2);
}

enum _XoType { bw2, bw4, lr2, lr4, lr8 }

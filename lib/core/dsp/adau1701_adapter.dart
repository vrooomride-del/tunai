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
/// PRAM 주소맵 — JAB4_DSP_Firmware_Hardware_SouceCode_V112_2021_01_12_IC_1_PARAM.h
/// (SigmaStudio export 원본 대조 확정, 2026-07):
///
///   이 펌웨어에는 별도의 "PEQ" 모듈이 없다. addr 14~799는 전부 크로스오버(XO)용
///   2차 필터 캐스케이드 8개(스테레오 페어 4쌍) + 210~211 믹서로 구성된다:
///     Filter1_4  14~111    Filter1_9  112~209   (98워드씩)
///     2XMixer1_3 210~211 (XO 믹스 포인트)
///     Filter1_10 212~309   Filter1_11 310~407
///     Filter1_5  408~505   Filter1_8  506~603
///     Filter1_6  604~701   Filter1_7  702~799
///   블록 → (채널, HPF/LPF) 매핑과 블록 내부 스테이지 오프셋은 아직 미확정 —
///   SigmaStudio .dspproj를 열어 블록 라벨을 육안 확인해야 한다(Boot Camp
///   Windows). 확인 전까지 writeCrossover/writeSubsonicFilter는 no-op.
///
///   writeBiquad(PEQ)는 이 펌웨어가 지원하지 않으므로 no-op이다 — 이전에
///   peqBase=14로 가정했던 것은 오판이었고(실제로는 XO 캐스케이드 영역),
///   향후 PEQ가 필요하면 SigmaStudio에서 별도 PEQ 블록을 추가해 펌웨어를
///   재컴파일해야 한다.
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

  // ── XO 필터 블록 (확정 주소, 채널/필터타입 매핑 미확정) ────────────
  // Filter1_4, 1_9, 1_10, 1_11, 1_5, 1_8, 1_6, 1_7 순서, 각 98워드 연속 배치
  static const List<int> _xoFilterBlockBase = [
    14, 112, 212, 310, 408, 506, 604, 702,
  ];
  static const int _xoMixerBase = 210; // 2XMixer1_3

  // 채널 → XO 필터 블록 인덱스 — TODO: SigmaStudio .dspproj 육안 확인 후 채우기
  static int? _xoBlockIndex(int channelIndex, FilterSide side) {
    assert(_xoFilterBlockBase.length == 8 && _xoMixerBase == 210);
    return null; // 매핑 미확정
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
  // 이 펌웨어에는 PEQ 모듈이 없음(addr 14~799는 전부 XO 캐스케이드) — no-op.
  // 향후 PEQ가 필요하면 SigmaStudio에서 PEQ 블록을 추가해 펌웨어를 재컴파일해야 한다.
  @override
  Future<void> writeBiquad(int channelIndex, int bandIndex, BiquadCoeffs coeffs) async {}

  // ── 크로스오버 ───────────────────────────────────────────────
  // 블록→(채널,HPF/LPF) 매핑과 블록 내부 스테이지 오프셋 미확정 — SigmaStudio
  // .dspproj 육안 확인 전까지 no-op.
  @override
  Future<void> writeCrossover(int channelIndex, CrossoverConfig config) async {
    final blockIndex = _xoBlockIndex(channelIndex, config.side);
    if (blockIndex == null) return; // TODO: 블록 매핑 미확정
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
  // XO 블록 매핑 미확정 — writeCrossover와 동일 사유로 no-op.
  @override
  Future<void> writeSubsonicFilter(int channelIndex, double freqHz) async {
    final blockIndex = _xoBlockIndex(channelIndex, FilterSide.hpf);
    if (blockIndex == null) return; // TODO: 블록 매핑 미확정
  }

  @override
  Future<DspState> readCurrentState() async => const DspState(raw: {});

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
}

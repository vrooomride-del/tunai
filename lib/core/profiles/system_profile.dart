import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../dsp/dsp_adapter.dart';
import '../dsp/adau1701_adapter.dart';
import '../dsp/adau1466_adapter.dart';
import '../dsp/validating_dsp_adapter.dart';

/// 선택된 시스템 프로파일 전역 상태
final systemProfileProvider =
    StateProvider<SystemProfile>((ref) => kTunaiOneSystemProfile);

enum SystemProfileId {
  tunaiOne,       // 경로 1: JAB4(ADAU1701) 2웨이
  isobarik,       // 경로 2: 파란보드(ADAU1466) 3웨이 Linn Isobarik
  tunaiReference, // 경로 3: 파란보드(ADAU1466) 동축 2웨이
}

enum ChannelType { woofer, mid, tweeter, fullRange, subwoofer }

/// L / R / 모노 구분 (모노: L/R 분리 미지원 채널)
enum ChannelSide { left, right, mono }

class ChannelConfig {
  final String name;
  final ChannelType type;
  final (double, double) freqRange; // (low Hz, high Hz)
  final ChannelSide side;
  const ChannelConfig({
    required this.name,
    required this.type,
    required this.freqRange,
    this.side = ChannelSide.mono,
  });
}

class SystemProfile {
  final SystemProfileId id;
  final String displayName;
  final String description;
  final String chipLabel;   // UI 표시용 DSP 칩 이름
  final DspAdapter Function(RawWriteFn writeRaw) adapterFactory;
  final List<ChannelConfig> channels;
  final int crossoverPoints; // 크로스오버 수 = 대역 수 - 1

  const SystemProfile({
    required this.id,
    required this.displayName,
    required this.description,
    required this.chipLabel,
    required this.adapterFactory,
    required this.channels,
    required this.crossoverPoints,
  });

  int get channelCount => channels.length;
  bool get isAdau1466 => id == SystemProfileId.isobarik || id == SystemProfileId.tunaiReference;
  // ADAU1701(비-1466) 펌웨어에는 PEQ 모듈이 없음 — Adau1701Adapter.writeBiquad는
  // no-op. 이 값은 현재 로컬 미리보기/밴드 합치기 한도로만 쓰임(실기기 전송 없음).
  int get maxPeqBands => isAdau1466 ? 20 : 10;

  /// 대역(ChannelType)별로 L/R 채널 쌍을 반환
  /// mono 채널은 [index, -1] 형태로 반환 (R 없음)
  List<({ChannelType type, int leftIdx, int rightIdx})> get bandPairs {
    final Map<ChannelType, ({int l, int r})> map = {};
    for (int i = 0; i < channels.length; i++) {
      final ch = channels[i];
      final prev = map[ch.type] ?? (l: -1, r: -1);
      if (ch.side == ChannelSide.left || ch.side == ChannelSide.mono) {
        map[ch.type] = (l: i, r: prev.r);
      } else if (ch.side == ChannelSide.right) {
        map[ch.type] = (l: prev.l, r: i);
      }
    }
    // ChannelType 출현 순서 유지
    final seen = <ChannelType>[];
    for (final ch in channels) {
      if (!seen.contains(ch.type)) seen.add(ch.type);
    }
    return seen.map((t) {
      final p = map[t]!;
      return (type: t, leftIdx: p.l, rightIdx: p.r);
    }).toList();
  }
}

// ── 사전 정의 프로파일 ─────────────────────────────────────────
//
// adapterFactory는 항상 ValidatingDspAdapter로 감싸서 반환한다 — Safety Validation
// Layer(AOS 항목 D)를 우회할 방법을 없애기 위함. 채널 리스트를 top-level const로
// 먼저 선언해 adapterFactory 클로저와 channels 필드가 동일한 리스트를 참조하게 함
// (SystemProfile 생성자 호출 자체는 const가 아니라 이 참조가 가능함).

/// TUNAI ONE — ADAU1701 2웨이 스테레오 (4채널)
/// ch0: WooferL, ch1: WooferR, ch2: TweeterL, ch3: TweeterR
const _tunaiOneChannels = [
  ChannelConfig(name: 'Woofer L',  type: ChannelType.woofer,  side: ChannelSide.left,  freqRange: (40,  2200)),
  ChannelConfig(name: 'Woofer R',  type: ChannelType.woofer,  side: ChannelSide.right, freqRange: (40,  2200)),
  ChannelConfig(name: 'Tweeter L', type: ChannelType.tweeter, side: ChannelSide.left,  freqRange: (2200, 20000)),
  ChannelConfig(name: 'Tweeter R', type: ChannelType.tweeter, side: ChannelSide.right, freqRange: (2200, 20000)),
];

final kTunaiOneSystemProfile = SystemProfile(
  id: SystemProfileId.tunaiOne,
  displayName: 'TUNAI ONE',
  description: '5.25" 우퍼 + 1" 트위터 2웨이 · JAB4(ADAU1701)',
  chipLabel: 'ADAU1701',
  adapterFactory: (write) =>
      ValidatingDspAdapter(Adau1701Adapter(writeRaw: write), _tunaiOneChannels),
  channels: _tunaiOneChannels,
  crossoverPoints: 1,
);

/// Isobarik — ADAU1466 3웨이 스테레오 (6채널)
/// ch0: WooferL, ch1: WooferR, ch2: MidL, ch3: MidR, ch4: TweeterL, ch5: TweeterR
const _isobarikChannels = [
  ChannelConfig(name: 'Woofer L',  type: ChannelType.woofer,  side: ChannelSide.left,  freqRange: (20,  280)),
  ChannelConfig(name: 'Woofer R',  type: ChannelType.woofer,  side: ChannelSide.right, freqRange: (20,  280)),
  ChannelConfig(name: 'Mid L',     type: ChannelType.mid,     side: ChannelSide.left,  freqRange: (280,  2500)),
  ChannelConfig(name: 'Mid R',     type: ChannelType.mid,     side: ChannelSide.right, freqRange: (280,  2500)),
  ChannelConfig(name: 'Tweeter L', type: ChannelType.tweeter, side: ChannelSide.left,  freqRange: (2500, 20000)),
  ChannelConfig(name: 'Tweeter R', type: ChannelType.tweeter, side: ChannelSide.right, freqRange: (2500, 20000)),
];

final kIsobarikSystemProfile = SystemProfile(
  id: SystemProfileId.isobarik,
  displayName: 'Isobarik 거실',
  description: 'Linn Isobarik 3웨이 · 파란보드(ADAU1466 + CS42448)',
  chipLabel: 'ADAU1466',
  adapterFactory: (write) =>
      ValidatingDspAdapter(Adau1466Adapter(writeRaw: write), _isobarikChannels),
  channels: _isobarikChannels,
  crossoverPoints: 2,
);

/// TUNAI REFERENCE — ADAU1466 동축 2웨이 스테레오 (4채널)
const _tunaiReferenceChannels = [
  ChannelConfig(name: 'Coaxial Woofer L',  type: ChannelType.woofer,  side: ChannelSide.left,  freqRange: (40,  2000)),
  ChannelConfig(name: 'Coaxial Woofer R',  type: ChannelType.woofer,  side: ChannelSide.right, freqRange: (40,  2000)),
  ChannelConfig(name: 'Coaxial Tweeter L', type: ChannelType.tweeter, side: ChannelSide.left,  freqRange: (2000, 20000)),
  ChannelConfig(name: 'Coaxial Tweeter R', type: ChannelType.tweeter, side: ChannelSide.right, freqRange: (2000, 20000)),
];

final kTunaiReferenceSystemProfile = SystemProfile(
  id: SystemProfileId.tunaiReference,
  displayName: 'TUNAI REFERENCE',
  description: '5.25" 동축 2웨이 · 파란보드(ADAU1466 + CS42448) + TPA3255 + QCC5125',
  chipLabel: 'ADAU1466',
  adapterFactory: (write) =>
      ValidatingDspAdapter(Adau1466Adapter(writeRaw: write), _tunaiReferenceChannels),
  channels: _tunaiReferenceChannels,
  crossoverPoints: 1,
);

final kAllSystemProfiles = [
  kTunaiOneSystemProfile,
  kIsobarikSystemProfile,
  kTunaiReferenceSystemProfile,
];

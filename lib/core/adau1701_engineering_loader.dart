// ── TUNAI Consumer — ADAU1701 Engineering Candidate Loader ───────────────────
// Two firmware maps are present in this codebase. Both are included so the
// operator can see all known addresses, but only appropriate candidates are
// writable given the active firmware and write-path capabilities.
//
// === Export14 (factory_screen.dart, "ADAU1701 v0.8 Export14") ================
//   Write shape:  singleWordParameter (transport.writeParameter, 4 bytes)
//   MV 0x0004/0x0005: UNBLOCKED — production-verified via MasterVolumeController
//   Gain 0x0084–0x0089: firmwareConfirmed=false by default
//                        → G7 FIRMWARE_SOURCE_NOT_CONFIRMED until operator confirms
//   Mute/Delay/PEQ:  isBlocked=true (protocol prerequisites unmet)
//
// === Recompiled 2026-07-04 (adau1701_adapter.dart) ===========================
//   Write shape:  fiveWordCoefficientBlock (DspCompiler.buildBleFrame, 20 bytes)
//   ALL blocked: WRITE_SHAPE_NOT_SUPPORTED — incompatible with writeParameter path.
//   Delay/PEQ:   unsupported (no firmware block).
//
// ABSOLUTE RESTRICTIONS: No EEPROM (0xA0). No Selfboot. No WriteAll.

import 'adau1701_engineering_candidate.dart';

const _kVersion = 'ADAU1701 v0.8 Export14 | Adapter-2026-07-04';

// ── Export14 addresses ────────────────────────────────────────────────────────

const _kMvLAddr = 0x0005;
const _kMvRAddr = 0x0004;

const _kGain1701Addrs = [0x0084, 0x0085, 0x0088, 0x0089];
const _kMute1701Addrs = [0x0086, 0x0087, 0x008A, 0x008B];
const _kDelay1701Addrs = [0x008C, 0x008D, 0x008E, 0x008F];
const _kPeq1701Addrs = [0x0030, 0x0045, 0x0064, 0x0074];
const _kChannelNames1701 = ['WOO L', 'WOO R', 'TWE L', 'TWE R'];

// ── Adapter (2026-07-04) addresses ───────────────────────────────────────────
// Gain: stereo-linked per band — addr 7=Woofer L+R, 6=Tweeter L+R
// Mute: channel mute addr 11=Woofer L+R, 12=Tweeter L+R
//       output mute addr 805/806/807/808 per physical DAC
// XO:   per-channel HPF+LPF biquad block, 5 words each

const _kAdapterGainAddrs = [
  (addr: 7, ch: 'WOO L+R', label: 'Gain WOO (stereo link)'),
  (addr: 6, ch: 'TWE L+R', label: 'Gain TWE (stereo link)'),
];
const _kAdapterChMuteAddrs = [
  (addr: 11, ch: 'WOO L+R', label: 'Mute Band WOO (stereo link)'),
  (addr: 12, ch: 'TWE L+R', label: 'Mute Band TWE (stereo link)'),
];
const _kAdapterOutMuteAddrs = [
  (addr: 805, ch: 'TWE L', label: 'Mute Out DAC0 TweeterL'),
  (addr: 806, ch: 'TWE R', label: 'Mute Out DAC1 TweeterR'),
  (addr: 807, ch: 'WOO L', label: 'Mute Out DAC2 WooferL'),
  (addr: 808, ch: 'WOO R', label: 'Mute Out DAC3 WooferR'),
];
const _kAdapterXoBlocks = [
  // (addr, ch, side) — each block = 5-word biquad (HPF or LPF)
  (addr: 21, ch: 'ch0 WooferL', label: 'XO DAC2-WooferA HPF'),
  (addr: 31, ch: 'ch0 WooferL', label: 'XO DAC2-WooferA LPF'),
  (addr: 36, ch: 'ch1 WooferR', label: 'XO DAC3-WooferB HPF'),
  (addr: 51, ch: 'ch1 WooferR', label: 'XO DAC3-WooferB LPF'),
  (addr: 41, ch: 'ch2 TweeterL', label: 'XO DAC0-TweeterA HPF'),
  (addr: 46, ch: 'ch2 TweeterL', label: 'XO DAC0-TweeterA LPF'),
  (addr: 16, ch: 'ch3 TweeterR', label: 'XO DAC1-TweeterB HPF'),
  (addr: 26, ch: 'ch3 TweeterR', label: 'XO DAC1-TweeterB LPF'),
];

// ── Helpers ───────────────────────────────────────────────────────────────────

const _kUnity523 = '00800000';
const _kSilence = '00000000';

String _hex(int a) =>
    '0x${a.toRadixString(16).toUpperCase().padLeft(4, '0')}';

String _id(String prefix, int addr) =>
    '${prefix}_0x${addr.toRadixString(16).padLeft(4, '0')}';

// ── Load result ───────────────────────────────────────────────────────────────

class Adau1701LoadResult {
  final List<Adau1701AddressCandidate> candidates;
  final String version;

  const Adau1701LoadResult({required this.candidates, required this.version});

  /// Candidates where isBlocked=false (may still require firmwareConfirmed/formatConfirmed).
  List<Adau1701AddressCandidate> get unblocked =>
      candidates.where((c) => !c.isBlocked).toList();

  /// Candidates that can execute without any additional operator confirmation
  /// (production-verified, single-word write, firmware confirmed, not blocked).
  List<Adau1701AddressCandidate> get writeReady => candidates
      .where((c) =>
          !c.isBlocked &&
          c.firmwareConfirmed &&
          c.writeShape == Adau1701WriteShape.singleWordParameter)
      .toList();

  List<Adau1701AddressCandidate> byKind(Adau1701CandidateKind k) =>
      candidates.where((c) => c.kind == k).toList();

  List<Adau1701AddressCandidate> bySource(Adau1701FirmwareSource s) =>
      candidates.where((c) => c.firmwareSource == s).toList();
}

// ── Loader ────────────────────────────────────────────────────────────────────

class Adau1701EngineeringLoader {
  static Adau1701LoadResult load() {
    final out = <Adau1701AddressCandidate>[];

    // ── Export14: Master Volume (production-verified) ────────────────────────
    // Already in production use by MasterVolumeController.
    // firmwareConfirmed=true — no additional gate needed.
    for (final (addr, ch) in [(_kMvLAddr, 'MV L'), (_kMvRAddr, 'MV R')]) {
      out.add(Adau1701AddressCandidate(
        id: _id('mv', addr),
        addressInt: addr,
        addressHex: _hex(addr),
        label: 'Master Volume $ch',
        channelName: ch,
        kind: Adau1701CandidateKind.masterVolume,
        firmwareSource: Adau1701FirmwareSource.export14SingleWord,
        writeShape: Adau1701WriteShape.singleWordParameter,
        isBlocked: false,
        exportDefaultHex: _kUnity523,
        status: Adau1701CandidateStatus.candidate,
        testValueHex: '00400000',
        restoreValueHex: _kUnity523,
        valueFormat: Adau1701ValueFormat.fixed523,
        firmwareConfirmed: true, // production-verified
        formatConfirmed: true,   // 5.23 is confirmed for MV
      ));
    }

    // ── Export14: Driver Gain (firmwareConfirmed=false — needs operator gate) ─
    for (var i = 0; i < _kGain1701Addrs.length; i++) {
      final addr = _kGain1701Addrs[i];
      final ch = _kChannelNames1701[i];
      out.add(Adau1701AddressCandidate(
        id: _id('gain', addr),
        addressInt: addr,
        addressHex: _hex(addr),
        label: 'Driver Gain $ch',
        channelName: ch,
        kind: Adau1701CandidateKind.gain,
        firmwareSource: Adau1701FirmwareSource.export14SingleWord,
        writeShape: Adau1701WriteShape.singleWordParameter,
        isBlocked: false,
        exportDefaultHex: _kUnity523,
        status: Adau1701CandidateStatus.candidate,
        testValueHex: '00400000',
        restoreValueHex: _kUnity523,
        valueFormat: Adau1701ValueFormat.unknown, // operator must select & confirm
        firmwareConfirmed: false, // G7 blocks until operator confirms Export14
        formatConfirmed: false,
      ));
    }

    // ── Export14: Driver Mute (blocked: capture window required) ─────────────
    for (var i = 0; i < _kMute1701Addrs.length; i++) {
      final addr = _kMute1701Addrs[i];
      final ch = _kChannelNames1701[i];
      out.add(Adau1701AddressCandidate(
        id: _id('mute', addr),
        addressInt: addr,
        addressHex: _hex(addr),
        label: 'Driver Mute $ch',
        channelName: ch,
        kind: Adau1701CandidateKind.mute,
        firmwareSource: Adau1701FirmwareSource.export14SingleWord,
        writeShape: Adau1701WriteShape.singleWordParameter,
        isBlocked: true,
        blockReason: 'CAPTURE_WINDOW_REQUIRED. Actual write disabled.',
        exportDefaultHex: _kUnity523,
        status: Adau1701CandidateStatus.blocked,
        testValueHex: _kSilence,
        restoreValueHex: _kUnity523,
        valueFormat: Adau1701ValueFormat.fixed523,
        firmwareConfirmed: false,
        formatConfirmed: false,
      ));
    }

    // ── Export14: Driver Delay (blocked: channel unconfirmed) ─────────────────
    for (var i = 0; i < _kDelay1701Addrs.length; i++) {
      final addr = _kDelay1701Addrs[i];
      final ch = _kChannelNames1701[i];
      out.add(Adau1701AddressCandidate(
        id: _id('delay', addr),
        addressInt: addr,
        addressHex: _hex(addr),
        label: 'Driver Delay $ch',
        channelName: ch,
        kind: Adau1701CandidateKind.delay,
        firmwareSource: Adau1701FirmwareSource.export14SingleWord,
        writeShape: Adau1701WriteShape.singleWordParameter,
        isBlocked: true,
        blockReason:
            'CHANNEL_UNCONFIRMED. Actual write disabled until channel mapping is confirmed.',
        exportDefaultHex: _kSilence,
        status: Adau1701CandidateStatus.blocked,
        testValueHex: _kSilence,
        restoreValueHex: _kSilence,
        valueFormat: Adau1701ValueFormat.fixed523,
        firmwareConfirmed: false,
        formatConfirmed: false,
      ));
    }

    // ── Export14: PEQ (blocked: coefficient order unknown) ────────────────────
    for (var i = 0; i < _kPeq1701Addrs.length; i++) {
      final addr = _kPeq1701Addrs[i];
      final ch = _kChannelNames1701[i];
      out.add(Adau1701AddressCandidate(
        id: _id('peq', addr),
        addressInt: addr,
        addressHex: _hex(addr),
        label: 'PEQ $ch (20-band)',
        channelName: ch,
        kind: Adau1701CandidateKind.peq,
        firmwareSource: Adau1701FirmwareSource.export14SingleWord,
        writeShape: Adau1701WriteShape.singleWordParameter,
        isBlocked: true,
        blockReason: 'COEFFICIENT_ORDER_UNKNOWN. Actual write disabled.',
        exportDefaultHex: _kSilence,
        status: Adau1701CandidateStatus.blocked,
        testValueHex: _kSilence,
        restoreValueHex: _kSilence,
        valueFormat: Adau1701ValueFormat.fixed523,
        firmwareConfirmed: false,
        formatConfirmed: false,
      ));
    }

    // ── Adapter 2026-07-04: Gain (5-word blocks — WRITE_SHAPE_NOT_SUPPORTED) ──
    for (final g in _kAdapterGainAddrs) {
      out.add(Adau1701AddressCandidate(
        id: _id('adp_gain', g.addr),
        addressInt: g.addr,
        addressHex: _hex(g.addr),
        label: g.label,
        channelName: g.ch,
        kind: Adau1701CandidateKind.gain,
        firmwareSource: Adau1701FirmwareSource.recompiled20260704Adapter,
        writeShape: Adau1701WriteShape.fiveWordCoefficientBlock,
        isBlocked: true,
        blockReason:
            'WRITE_SHAPE_NOT_SUPPORTED. Requires 5-word DspCompiler frame; '
            'writeParameter(4 bytes) cannot write this address correctly.',
        exportDefaultHex: _kUnity523,
        status: Adau1701CandidateStatus.blocked,
        testValueHex: _kUnity523,
        restoreValueHex: _kUnity523,
        valueFormat: Adau1701ValueFormat.fixed523,
        firmwareConfirmed: false,
        formatConfirmed: false,
      ));
    }

    // ── Adapter 2026-07-04: Channel Mute (5-word — WRITE_SHAPE_NOT_SUPPORTED) ─
    for (final m in _kAdapterChMuteAddrs) {
      out.add(Adau1701AddressCandidate(
        id: _id('adp_chmute', m.addr),
        addressInt: m.addr,
        addressHex: _hex(m.addr),
        label: m.label,
        channelName: m.ch,
        kind: Adau1701CandidateKind.mute,
        firmwareSource: Adau1701FirmwareSource.recompiled20260704Adapter,
        writeShape: Adau1701WriteShape.fiveWordCoefficientBlock,
        isBlocked: true,
        blockReason: 'WRITE_SHAPE_NOT_SUPPORTED. Requires 5-word DspCompiler frame.',
        exportDefaultHex: _kUnity523,
        status: Adau1701CandidateStatus.blocked,
        testValueHex: _kUnity523,
        restoreValueHex: _kUnity523,
        valueFormat: Adau1701ValueFormat.fixed523,
        firmwareConfirmed: false,
        formatConfirmed: false,
      ));
    }

    // ── Adapter 2026-07-04: Output Mute (5-word — WRITE_SHAPE_NOT_SUPPORTED) ──
    for (final m in _kAdapterOutMuteAddrs) {
      out.add(Adau1701AddressCandidate(
        id: _id('adp_outmute', m.addr),
        addressInt: m.addr,
        addressHex: _hex(m.addr),
        label: m.label,
        channelName: m.ch,
        kind: Adau1701CandidateKind.mute,
        firmwareSource: Adau1701FirmwareSource.recompiled20260704Adapter,
        writeShape: Adau1701WriteShape.fiveWordCoefficientBlock,
        isBlocked: true,
        blockReason: 'WRITE_SHAPE_NOT_SUPPORTED. Requires 5-word DspCompiler frame.',
        exportDefaultHex: _kSilence,
        status: Adau1701CandidateStatus.blocked,
        testValueHex: _kSilence,
        restoreValueHex: _kSilence,
        valueFormat: Adau1701ValueFormat.fixed523,
        firmwareConfirmed: false,
        formatConfirmed: false,
      ));
    }

    // ── Adapter 2026-07-04: XO Biquad Blocks (5-word — WRITE_SHAPE_NOT_SUPPORTED)
    for (final x in _kAdapterXoBlocks) {
      out.add(Adau1701AddressCandidate(
        id: _id('adp_xo', x.addr),
        addressInt: x.addr,
        addressHex: _hex(x.addr),
        label: x.label,
        channelName: x.ch,
        kind: Adau1701CandidateKind.crossover,
        firmwareSource: Adau1701FirmwareSource.recompiled20260704Adapter,
        writeShape: Adau1701WriteShape.fiveWordCoefficientBlock,
        isBlocked: true,
        blockReason:
            'WRITE_SHAPE_NOT_SUPPORTED. XO biquad requires 5-word coefficient block '
            '(B0/B1/B2/A0/A1); writeParameter(4 bytes) cannot write this address.',
        exportDefaultHex: _kSilence,
        status: Adau1701CandidateStatus.blocked,
        testValueHex: _kSilence,
        restoreValueHex: _kSilence,
        valueFormat: Adau1701ValueFormat.fixed523,
        firmwareConfirmed: false,
        formatConfirmed: false,
      ));
    }

    return Adau1701LoadResult(candidates: out, version: _kVersion);
  }
}

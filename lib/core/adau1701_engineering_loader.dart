// ── TUNAI Consumer — ADAU1701 Engineering Candidate Loader ───────────────────
// Sources from embedded constants matching factory_screen.dart (v0.8 Export14).
// No CSV, no external files, no EEPROM, no Selfboot, no WriteAll.
//
// Unblocked: masterVolume, gain
// Blocked:   mute (CAPTURE_WINDOW_REQUIRED)
//            delay (CHANNEL_UNCONFIRMED)
//            peq (COEFFICIENT_ORDER_UNKNOWN)
//
// Value format: 5.23 fixed-point by default (1.0 = 0x00800000)

import 'adau1701_engineering_candidate.dart';

const _kVersion = 'ADAU1701 v0.8 Export14';

const _kMvLAddr = 0x0005;
const _kMvRAddr = 0x0004;

const _kGain1701Addrs = [0x0084, 0x0085, 0x0088, 0x0089];
const _kMute1701Addrs = [0x0086, 0x0087, 0x008A, 0x008B];
const _kDelay1701Addrs = [0x008C, 0x008D, 0x008E, 0x008F];
const _kPeq1701Addrs = [0x0030, 0x0045, 0x0064, 0x0074];
const _kChannelNames1701 = ['WOO L', 'WOO R', 'TWE L', 'TWE R'];

// 5.23 fixed-point values
const _kUnity523 = '00800000'; // 1.0 = 0 dB
const _kSilence = '00000000'; // 0.0

String _addrHex(int a) =>
    '0x${a.toRadixString(16).toUpperCase().padLeft(4, '0')}';

class Adau1701LoadResult {
  final List<Adau1701AddressCandidate> candidates;
  final String version;

  const Adau1701LoadResult({required this.candidates, required this.version});

  List<Adau1701AddressCandidate> get unblocked =>
      candidates.where((c) => !c.isBlocked).toList();

  List<Adau1701AddressCandidate> byKind(Adau1701CandidateKind k) =>
      candidates.where((c) => c.kind == k).toList();
}

class Adau1701EngineeringLoader {
  static Adau1701LoadResult load() {
    final out = <Adau1701AddressCandidate>[];

    // ── Master Volume ────────────────────────────────────────────────────────
    for (final (addr, ch) in [
      (_kMvLAddr, 'MV L'),
      (_kMvRAddr, 'MV R'),
    ]) {
      out.add(Adau1701AddressCandidate(
        id: 'mv_0x${addr.toRadixString(16).padLeft(4, '0')}',
        addressInt: addr,
        addressHex: _addrHex(addr),
        label: 'Master Volume $ch',
        channelName: ch,
        kind: Adau1701CandidateKind.masterVolume,
        isBlocked: false,
        exportDefaultHex: _kUnity523,
        status: Adau1701CandidateStatus.candidate,
        testValueHex: '00400000', // -6 dB
        restoreValueHex: _kUnity523,
        valueFormat: Adau1701ValueFormat.fixed523,
      ));
    }

    // ── Driver Gain (unblocked) ──────────────────────────────────────────────
    for (var i = 0; i < _kGain1701Addrs.length; i++) {
      final addr = _kGain1701Addrs[i];
      final ch = _kChannelNames1701[i];
      out.add(Adau1701AddressCandidate(
        id: 'gain_0x${addr.toRadixString(16).padLeft(4, '0')}',
        addressInt: addr,
        addressHex: _addrHex(addr),
        label: 'Driver Gain $ch',
        channelName: ch,
        kind: Adau1701CandidateKind.gain,
        isBlocked: false,
        exportDefaultHex: _kUnity523,
        status: Adau1701CandidateStatus.candidate,
        testValueHex: '00400000', // -6 dB
        restoreValueHex: _kUnity523,
        valueFormat: Adau1701ValueFormat.fixed523,
      ));
    }

    // ── Driver Mute (blocked) ────────────────────────────────────────────────
    for (var i = 0; i < _kMute1701Addrs.length; i++) {
      final addr = _kMute1701Addrs[i];
      final ch = _kChannelNames1701[i];
      out.add(Adau1701AddressCandidate(
        id: 'mute_0x${addr.toRadixString(16).padLeft(4, '0')}',
        addressInt: addr,
        addressHex: _addrHex(addr),
        label: 'Driver Mute $ch',
        channelName: ch,
        kind: Adau1701CandidateKind.mute,
        isBlocked: true,
        blockReason: 'CAPTURE_WINDOW_REQUIRED. Actual write disabled.',
        exportDefaultHex: _kUnity523,
        status: Adau1701CandidateStatus.blocked,
        testValueHex: _kSilence,
        restoreValueHex: _kUnity523,
        valueFormat: Adau1701ValueFormat.fixed523,
      ));
    }

    // ── Driver Delay (blocked: channel unconfirmed) ──────────────────────────
    for (var i = 0; i < _kDelay1701Addrs.length; i++) {
      final addr = _kDelay1701Addrs[i];
      final ch = _kChannelNames1701[i];
      out.add(Adau1701AddressCandidate(
        id: 'delay_0x${addr.toRadixString(16).padLeft(4, '0')}',
        addressInt: addr,
        addressHex: _addrHex(addr),
        label: 'Driver Delay $ch',
        channelName: ch,
        kind: Adau1701CandidateKind.delay,
        isBlocked: true,
        blockReason:
            'CHANNEL_UNCONFIRMED. Actual write disabled until channel mapping is confirmed.',
        exportDefaultHex: _kSilence,
        status: Adau1701CandidateStatus.blocked,
        testValueHex: _kSilence,
        restoreValueHex: _kSilence,
        valueFormat: Adau1701ValueFormat.fixed523,
      ));
    }

    // ── PEQ (blocked: coefficient order unknown) ─────────────────────────────
    for (var i = 0; i < _kPeq1701Addrs.length; i++) {
      final addr = _kPeq1701Addrs[i];
      final ch = _kChannelNames1701[i];
      out.add(Adau1701AddressCandidate(
        id: 'peq_0x${addr.toRadixString(16).padLeft(4, '0')}',
        addressInt: addr,
        addressHex: _addrHex(addr),
        label: 'PEQ $ch (20-band)',
        channelName: ch,
        kind: Adau1701CandidateKind.peq,
        isBlocked: true,
        blockReason: 'COEFFICIENT_ORDER_UNKNOWN. Actual write disabled.',
        exportDefaultHex: _kSilence,
        status: Adau1701CandidateStatus.blocked,
        testValueHex: _kSilence,
        restoreValueHex: _kSilence,
        valueFormat: Adau1701ValueFormat.fixed523,
      ));
    }

    return Adau1701LoadResult(candidates: out, version: _kVersion);
  }
}

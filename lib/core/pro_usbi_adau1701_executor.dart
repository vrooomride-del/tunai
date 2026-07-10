/// ADAU1701 parameter write executor via USBi → I2C.
///
/// Target: WONDOM JAB4 / Miumax original ADAU1701 firmware (Export 19).
/// Transport: USBi (WinUSB) → I2C 0x68.
/// Gain format: 5.23 fixed-point, 4-byte Big Endian.
///
/// DIFFERENT FROM ADAU1466 EXECUTOR:
///   ADAU1466 uses SPI via raw USBi setup/body/ack packets.
///   ADAU1701 uses I2C. The native side must issue I2C transactions.
///   Do NOT reuse ADAU1466 packet format for ADAU1701 writes.
///
/// Phase 1 test scope:
///   Addresses 0x0321–0x0324 only (Default Gain, Gain1940 direct).
///   Same value written to all four addresses per button press.
///   EEPROM 0xA0 must never be written.
///   Selfboot write must never be triggered.
library;

import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'adau1701_jab4_miumax_address_registry.dart';
import 'dsp_profile.dart';

// ── Packet encoding ───────────────────────────────────────────────────────────

/// ADAU1701 5.23 fixed-point packet utilities.
/// 5.23 FP: value = bits / 2^23. 1.0 = 0x00800000.
class Adau1701PacketBuilder {
  Adau1701PacketBuilder._();

  /// Encode a linear gain in 5.23 fixed-point, 4-byte Big Endian.
  /// Input is clamped to [0.0, max ~16.0] (anything above 1.0 is amplification;
  /// Phase 1 only writes values ≤ 1.0).
  static List<int> encodeGain523(double linearGain) {
    final clamped = linearGain.clamp(0.0, 16.0);
    final fixed = (clamped * (1 << 23)).round().clamp(0, 0x7FFFFFFF);
    return [
      (fixed >> 24) & 0xFF,
      (fixed >> 16) & 0xFF,
      (fixed >> 8) & 0xFF,
      fixed & 0xFF,
    ];
  }

  /// True if the raw 4-byte value encodes unity gain (0 dB) in 5.23 FP.
  static bool isUnityGain(List<int> bytes) =>
      bytes.length == 4 &&
      bytes[0] == 0x00 &&
      bytes[1] == 0x80 &&
      bytes[2] == 0x00 &&
      bytes[3] == 0x00;

  /// Hex string for logging.
  static String toHex(List<int> bytes) =>
      bytes.map((b) => b.toRadixString(16).padLeft(2, '0').toUpperCase()).join(' ');
}

// ── Write result ──────────────────────────────────────────────────────────────

class Adau1701WriteResult {
  final int address;
  final List<int> bytesWritten;
  final bool success;
  final String? error;
  final DateTime timestamp;

  const Adau1701WriteResult({
    required this.address,
    required this.bytesWritten,
    required this.success,
    this.error,
    required this.timestamp,
  });

  String get addressHex =>
      '0x${address.toRadixString(16).toUpperCase().padLeft(4, '0')}';

  String get logLine {
    final bytes = Adau1701PacketBuilder.toHex(bytesWritten);
    final status = success ? 'OK' : 'FAIL: $error';
    return '[ADAU1701_JAB4_MIUMAX_ORIGINAL] I2C 0x68 WRITE param $addressHex = $bytes $status';
  }
}

class Adau1701MultiWriteResult {
  final List<Adau1701WriteResult> writes;
  final DateTime timestamp;
  final String gainLabel;

  const Adau1701MultiWriteResult({
    required this.writes,
    required this.timestamp,
    required this.gainLabel,
  });

  bool get allSucceeded => writes.every((r) => r.success);
  int get successCount => writes.where((r) => r.success).length;
  int get failCount => writes.where((r) => !r.success).length;

  String get summary =>
      allSucceeded
          ? 'All ${writes.length} addresses written OK ($gainLabel)'
          : '$successCount/${writes.length} OK, $failCount FAILED ($gainLabel)';
}

// ── Transport channel ─────────────────────────────────────────────────────────

/// Guard result from the pre-write validation chain.
class _GuardResult {
  final bool passed;
  final String? reason;
  const _GuardResult.ok() : passed = true, reason = null;
  const _GuardResult.fail(this.reason) : passed = false;
}

/// ADAU1701 write executor.
///
/// Uses MethodChannel `tunai/usbi` method `usbi_write_adau1701_param`.
/// The Windows native side receives:
///   {'i2c_address': int, 'param_address': int, 'data': List<int>}
/// and performs an I2C write transaction to the ADAU1701.
///
/// The native method must NOT be confused with the ADAU1466 SPI methods.
class ProUsbiAdau1701Executor {
  static const _channel = MethodChannel('tunai/usbi');

  static const DspProfile profile = DspProfile.adau1701Jab4MiumaxOriginal;
  static const int _i2cAddress = Adau1701Jab4MiumaxAddressRegistry.i2cDspAddress;

  const ProUsbiAdau1701Executor();

  // ── Guard chain ─────────────────────────────────────────────────────────────

  /// G1: Must be running on Windows.
  _GuardResult _g1Platform() {
    if (!Platform.isWindows) {
      return const _GuardResult.fail('G1: Platform is not Windows');
    }
    return const _GuardResult.ok();
  }

  /// G2: Address must be in the Phase 1 allowed set.
  /// Blocks any write outside {0x0321, 0x0322, 0x0323, 0x0324}.
  _GuardResult _g2Address(int address) {
    if (!Adau1701Jab4MiumaxAddressRegistry.phase1GainAddresses.contains(address)) {
      return _GuardResult.fail(
          'G2: Address 0x${address.toRadixString(16).toUpperCase()} '
          'not in phase1GainAddresses');
    }
    return const _GuardResult.ok();
  }

  /// G3: Data must be exactly 4 bytes.
  _GuardResult _g3DataLength(List<int> data) {
    if (data.length != 4) {
      return _GuardResult.fail('G3: Data must be 4 bytes, got ${data.length}');
    }
    return const _GuardResult.ok();
  }

  /// G4: Operator confirmation required.
  _GuardResult _g4Confirmed(bool operatorConfirmed) {
    if (!operatorConfirmed) {
      return const _GuardResult.fail('G4: operatorConfirmed is false');
    }
    return const _GuardResult.ok();
  }

  // ── Single-address write ─────────────────────────────────────────────────────

  Future<Adau1701WriteResult> _writeSingleParam({
    required int address,
    required List<int> data,
    required bool operatorConfirmed,
  }) async {
    final now = DateTime.now();

    // Run guards G1, G2, G3, G4.
    for (final g in [
      _g1Platform(),
      _g2Address(address),
      _g3DataLength(data),
      _g4Confirmed(operatorConfirmed),
    ]) {
      if (!g.passed) {
        debugPrint('[ADAU1701] Guard blocked: ${g.reason}');
        return Adau1701WriteResult(
          address: address,
          bytesWritten: data,
          success: false,
          error: g.reason,
          timestamp: now,
        );
      }
    }

    debugPrint(
        '[ADAU1701] WRITE I2C 0x${_i2cAddress.toRadixString(16).toUpperCase()} '
        'param 0x${address.toRadixString(16).toUpperCase().padLeft(4, '0')} '
        '= ${Adau1701PacketBuilder.toHex(data)}');

    try {
      await _channel.invokeMethod<void>('usbi_write_adau1701_param', {
        'i2c_address': _i2cAddress,
        'param_address': address,
        'data': data,
      });

      debugPrint('[ADAU1701] WRITE OK');
      return Adau1701WriteResult(
        address: address,
        bytesWritten: data,
        success: true,
        timestamp: now,
      );
    } on PlatformException catch (e) {
      final msg = '${e.code}: ${e.message}';
      debugPrint('[ADAU1701] WRITE FAIL: $msg');
      return Adau1701WriteResult(
        address: address,
        bytesWritten: data,
        success: false,
        error: msg,
        timestamp: now,
      );
    } catch (e) {
      debugPrint('[ADAU1701] WRITE FAIL (unexpected): $e');
      return Adau1701WriteResult(
        address: address,
        bytesWritten: data,
        success: false,
        error: e.toString(),
        timestamp: now,
      );
    }
  }

  // ── Phase 1 multi-address gain write ─────────────────────────────────────────

  /// Write the same 4-byte gain value to all four Phase 1 Default Gain
  /// addresses (0x0321, 0x0322, 0x0323, 0x0324).
  ///
  /// Writes are sequential. If one fails, remaining addresses are still
  /// attempted so the log reflects exactly which address failed.
  Future<Adau1701MultiWriteResult> writeDefaultGain({
    required List<int> gainBytes,
    required String gainLabel,
    required bool operatorConfirmed,
  }) async {
    final addresses = Adau1701Jab4MiumaxAddressRegistry.phase1GainAddresses.toList()
      ..sort(); // deterministic order: 0x0321, 0x0322, 0x0323, 0x0324

    debugPrint('[ADAU1701] writeDefaultGain($gainLabel) → '
        '${addresses.map((a) => '0x${a.toRadixString(16).toUpperCase()}').join(', ')}');

    final results = <Adau1701WriteResult>[];
    for (final addr in addresses) {
      final r = await _writeSingleParam(
        address: addr,
        data: List.unmodifiable(gainBytes),
        operatorConfirmed: operatorConfirmed,
      );
      results.add(r);
    }

    return Adau1701MultiWriteResult(
      writes: results,
      timestamp: DateTime.now(),
      gainLabel: gainLabel,
    );
  }

  /// Convenience: restore all four addresses to 0 dB (unity gain).
  Future<Adau1701MultiWriteResult> restore0dB({bool operatorConfirmed = true}) =>
      writeDefaultGain(
        gainBytes: Adau1701Jab4MiumaxAddressRegistry.gain0dB,
        gainLabel: '0 dB (restore)',
        operatorConfirmed: operatorConfirmed,
      );

  // ── Advanced Debug section (Engineering / Factory UI only) ──────────────────
  //
  // Single-address experimental writes for address discovery: Output Channel
  // Identify, Master Volume candidates, Mute candidates. Each write is gated
  // by its own address allowlist (never the Phase 1 four-address set as a
  // whole) so a bug here cannot widen what Phase 1 can touch, and vice versa.
  // Same transport (I2C 0x68 via usbi_write_adau1701_param) — no SPI, no
  // EEPROM, no Selfboot.

  /// G2-DEBUG: address must be in the explicit allowlist passed by the
  /// caller. Kept separate from G2 (Phase 1) by design.
  _GuardResult _g2Debug(int address, Set<int> allowed) {
    if (!allowed.contains(address)) {
      return _GuardResult.fail(
          'G2-DEBUG: Address 0x${address.toRadixString(16).toUpperCase()} '
          'not in the allowed debug set');
    }
    return const _GuardResult.ok();
  }

  Future<Adau1701WriteResult> _writeDebugParam({
    required int address,
    required List<int> data,
    required bool operatorConfirmed,
    required Set<int> allowedAddresses,
  }) async {
    final now = DateTime.now();

    for (final g in [
      _g1Platform(),
      _g2Debug(address, allowedAddresses),
      _g3DataLength(data),
      _g4Confirmed(operatorConfirmed),
    ]) {
      if (!g.passed) {
        debugPrint('[ADAU1701][DEBUG] Guard blocked: ${g.reason}');
        return Adau1701WriteResult(
          address: address,
          bytesWritten: data,
          success: false,
          error: g.reason,
          timestamp: now,
        );
      }
    }

    debugPrint(
        '[ADAU1701][DEBUG] WRITE I2C 0x${_i2cAddress.toRadixString(16).toUpperCase()} '
        'param 0x${address.toRadixString(16).toUpperCase().padLeft(4, '0')} '
        '= ${Adau1701PacketBuilder.toHex(data)}');

    try {
      await _channel.invokeMethod<void>('usbi_write_adau1701_param', {
        'i2c_address': _i2cAddress,
        'param_address': address,
        'data': data,
      });

      debugPrint('[ADAU1701][DEBUG] WRITE OK');
      return Adau1701WriteResult(
        address: address,
        bytesWritten: data,
        success: true,
        timestamp: now,
      );
    } on PlatformException catch (e) {
      final msg = '${e.code}: ${e.message}';
      debugPrint('[ADAU1701][DEBUG] WRITE FAIL: $msg');
      return Adau1701WriteResult(
        address: address,
        bytesWritten: data,
        success: false,
        error: msg,
        timestamp: now,
      );
    } catch (e) {
      debugPrint('[ADAU1701][DEBUG] WRITE FAIL (unexpected): $e');
      return Adau1701WriteResult(
        address: address,
        bytesWritten: data,
        success: false,
        error: e.toString(),
        timestamp: now,
      );
    }
  }

  /// Output Channel Identify — write a single Phase 1 Default Gain address
  /// alone (does not touch the other three). Reuses the Phase 1 allowlist
  /// since these are the same four confirmed-safe addresses.
  Future<Adau1701WriteResult> writeChannelIdentify({
    required int address,
    required List<int> gainBytes,
    required bool operatorConfirmed,
  }) =>
      _writeDebugParam(
        address: address,
        data: gainBytes,
        operatorConfirmed: operatorConfirmed,
        allowedAddresses: Adau1701Jab4MiumaxAddressRegistry.phase1GainAddresses,
      );

  /// Master Volume Candidate Test — EXPERIMENTAL. 0x0006/0x0007 are
  /// documented as ExtSWGainDB step parameters, not confirmed direct gain.
  /// Do not assume behavior until Capture Window verification.
  Future<Adau1701WriteResult> writeMasterVolumeCandidate({
    required int address,
    required List<int> bytes,
    required bool operatorConfirmed,
  }) =>
      _writeDebugParam(
        address: address,
        data: bytes,
        operatorConfirmed: operatorConfirmed,
        allowedAddresses:
            Adau1701Jab4MiumaxAddressRegistry.masterVolumeCandidateAddresses,
      );

  /// Mute Candidate Test — polarity UNVERIFIED. Writes a literal raw 4-byte
  /// value; caller must not label it "mute on" / "mute off".
  Future<Adau1701WriteResult> writeMuteCandidateRaw({
    required int address,
    required List<int> rawBytes,
    required bool operatorConfirmed,
  }) =>
      _writeDebugParam(
        address: address,
        data: rawBytes,
        operatorConfirmed: operatorConfirmed,
        allowedAddresses: Adau1701Jab4MiumaxAddressRegistry.muteCandidateAddresses,
      );
}

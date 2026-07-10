/// USBi temporary executor — Master Volume L/R write only.
///
/// ICP5 (BLE) remains the final production write path.
/// This executor is Windows-only, engineering use, Master Volume only.
///
/// 7-guard chain (D1–D7) — all must pass before any byte is sent:
///   D1  Platform is Windows
///   D2  Transport is usbiWindowsTemporary  ← DO NOT BYPASS
///   D3  Backend is connected (openDevice() was called)
///   D4  CommandType is masterVolumeL or masterVolumeR
///   D5  Address is in DspAddressRegistry.usbiAllowedAddresses
///   D6  Value is in [0.0, 1.0]
///   D7  operatorConfirmed == true
///
/// USBi packet protocol:
///   Setup (8B):  40 B2 00 00 01 01 06 00
///   Body  (6B):  [addr 2B BE] + [data 4B BE, 8.24 fixed-point]
///   ACK req (8B): C0 B5 00 00 00 00 01 00
///   ACK success: response byte[6] == 0x01
library;

import 'dart:io';
import 'package:flutter/foundation.dart';
import 'pro_usbi_native_backend.dart';
import 'transport_command_envelope.dart';
import 'dsp_address_registry.dart';
import 'address_validation_attempt.dart';

// ── Packet builder ────────────────────────────────────────────────────────────

/// Builds USBi byte sequences. All methods are pure/static — no IO.
class ProUsbiPacketBuilder {
  ProUsbiPacketBuilder._();

  /// Fixed USBi setup packet (8 bytes).
  static const List<int> setupBytes = [0x40, 0xB2, 0x00, 0x00, 0x01, 0x01, 0x06, 0x00];

  /// Fixed ACK read-request packet (8 bytes).
  static const List<int> ackRequestBytes = [0xC0, 0xB5, 0x00, 0x00, 0x00, 0x00, 0x01, 0x00];

  /// Build the 6-byte body: [address 2B BE] + [value as 8.24 fixed-point 4B BE].
  ///
  /// Examples from confirmed protocol docs:
  ///   0x0067 + 0.5 → 00 67 00 80 00 00
  ///   0x0064 + 1.0 → 00 64 01 00 00 00
  ///   0x0064 + 0.0 → 00 64 00 00 00 00
  static List<int> buildBody(int address, double value) {
    final addrHi = (address >> 8) & 0xFF;
    final addrLo = address & 0xFF;
    final fixed = _toFixed824(value);
    return [
      addrHi,
      addrLo,
      (fixed >> 24) & 0xFF,
      (fixed >> 16) & 0xFF,
      (fixed >> 8) & 0xFF,
      fixed & 0xFF,
    ];
  }

  /// 8.24 fixed-point encoding: 1.0 = 0x01000000, 0.5 = 0x00800000, 0.0 = 0.
  /// Input is clamped to [0.0, 1.0] before encoding.
  static int _toFixed824(double value) {
    final clamped = value.clamp(0.0, 1.0);
    return (clamped * 0x01000000).round().clamp(0, 0x01000000);
  }

  /// True if ACK response byte[6] == 0x01.
  static bool isAckSuccess(List<int> ackBytes) =>
      ackBytes.length > 6 && ackBytes[6] == 0x01;

  /// Hex string for logging (e.g. "40 B2 00 00").
  static String toHex(List<int> bytes) =>
      bytes.map((b) => b.toRadixString(16).padLeft(2, '0').toUpperCase()).join(' ');
}

// ── Execution result ──────────────────────────────────────────────────────────

class ExecutionResult {
  /// True only after [sendBody] was physically called by the executor.
  final bool wasActualWrite;

  /// True only after [readAck] returned a response (success or failure).
  final bool ackReceived;

  /// True if ACK response byte[6] == 0x01.
  final bool ackSuccess;

  /// Guard or transport failure message. Null on full success.
  final String? failureReason;

  final List<int>? setupBytes;
  final List<int>? bodyBytes;
  final List<int>? ackBytes;

  /// Recorded only after a live write attempt (guards D1–D7 all passed).
  final AddressValidationAttempt? validationAttempt;

  const ExecutionResult({
    required this.wasActualWrite,
    required this.ackReceived,
    required this.ackSuccess,
    this.failureReason,
    this.setupBytes,
    this.bodyBytes,
    this.ackBytes,
    this.validationAttempt,
  });

  bool get guardFailed => !wasActualWrite && ackBytes == null;
  bool get fullSuccess => wasActualWrite && ackReceived && ackSuccess;
}

// ── Executor ──────────────────────────────────────────────────────────────────

class ProUsbiTemporaryExecutor {
  final ProUsbiNativeBackend _backend;

  const ProUsbiTemporaryExecutor(this._backend);

  /// Execute a Master Volume write through the 7-guard chain.
  ///
  /// [wasActualWrite] is false unless all guards pass AND [sendBody] is called.
  /// [ackReceived] is false unless [readAck] returns a response.
  /// [liveWriteVerified] in the [AddressValidationAttempt] is always false —
  /// it requires separate explicit operator confirmation.
  Future<ExecutionResult> executeMasterVolumeWrite(
      TransportCommandEnvelope cmd) async {
    // Guard D1: Windows platform only.
    if (!Platform.isWindows) {
      return _guardFail('D1: Platform is not Windows (${Platform.operatingSystem})');
    }

    // Guard D2: Transport must be usbiWindowsTemporary. DO NOT BYPASS.
    if (cmd.transport != HardwareTransportBackend.usbiWindowsTemporary) {
      return _guardFail('D2: Transport ${cmd.transport.name} is not usbiWindowsTemporary');
    }

    // Guard D3: Backend must be connected.
    if (!_backend.isConnected) {
      return _guardFail('D3: Backend not connected — call openDevice() first');
    }

    // Guard D4: CommandType must be masterVolume.
    if (cmd.commandType != CommandType.masterVolumeL &&
        cmd.commandType != CommandType.masterVolumeR) {
      return _guardFail('D4: CommandType ${cmd.commandType.name} is not masterVolumeL or masterVolumeR');
    }

    // Guard D5: Address must be in the allowed set.
    if (!DspAddressRegistry.usbiAllowedAddresses.contains(cmd.address)) {
      return _guardFail(
          'D5: Address 0x${cmd.address.toRadixString(16).toUpperCase()} '
          'is not in usbiAllowedAddresses');
    }

    // Guard D6: Value in safe normalised range.
    if (cmd.value < 0.0 || cmd.value > 1.0) {
      return _guardFail('D6: Value ${cmd.value} is out of range [0.0, 1.0]');
    }

    // Guard D7: Operator explicitly confirmed.
    if (!cmd.operatorConfirmed) {
      return _guardFail('D7: operatorConfirmed is false');
    }

    // ── All guards passed — proceed to physical write ─────────────────────
    const setup = ProUsbiPacketBuilder.setupBytes;
    final body = ProUsbiPacketBuilder.buildBody(cmd.address, cmd.value);
    const ackReq = ProUsbiPacketBuilder.ackRequestBytes;

    debugPrint('[USBi] Setup:   ${ProUsbiPacketBuilder.toHex(setup)}');
    debugPrint('[USBi] Body:    ${ProUsbiPacketBuilder.toHex(body)}'
        ' (addr=0x${cmd.address.toRadixString(16).toUpperCase()}'
        ', val=${cmd.value})');
    debugPrint('[USBi] ACK req: ${ProUsbiPacketBuilder.toHex(ackReq)}');

    bool wasActualWrite = false;
    bool ackReceived = false;
    bool ackSuccess = false;
    List<int>? ackBytes;
    String? failureReason;

    try {
      await _backend.sendSetup(setup);
      // wasActualWrite only becomes true after body is sent.
      await _backend.sendBody(body);
      wasActualWrite = true;

      ackBytes = await _backend.readAck();
      ackReceived = true;
      ackSuccess = ProUsbiPacketBuilder.isAckSuccess(ackBytes);

      debugPrint('[USBi] ACK:     ${ProUsbiPacketBuilder.toHex(ackBytes)}'
          ' → ${ackSuccess ? "SUCCESS ✓" : "FAIL ✗"}');
    } catch (e) {
      failureReason = e.toString();
      debugPrint('[USBi] Write error: $failureReason'
          ' (wasActualWrite=$wasActualWrite)');
    }

    debugPrint('[USBi] wasActualWrite=$wasActualWrite  ackReceived=$ackReceived'
        '  ackSuccess=$ackSuccess');

    // Record validation attempt — liveWriteVerified stays false.
    final attempt = AddressValidationAttempt(
      address: cmd.address,
      value: cmd.value,
      timestamp: DateTime.now(),
      dryRunOnly: false,
      wasActualWrite: wasActualWrite,
      ackReceived: ackReceived,
      ackSuccess: ackSuccess,
      operatorConfirmed: true,
      resultStatus: wasActualWrite
          ? AddressValidationStatus.validationAttempted
          : AddressValidationStatus.dryRunOnly,
      // liveWriteVerified: false — never set automatically from ACK alone.
    );

    return ExecutionResult(
      wasActualWrite: wasActualWrite,
      ackReceived: ackReceived,
      ackSuccess: ackSuccess,
      failureReason: failureReason,
      setupBytes: setup,
      bodyBytes: body,
      ackBytes: ackBytes,
      validationAttempt: attempt,
    );
  }

  ExecutionResult _guardFail(String reason) {
    debugPrint('[USBi] Guard blocked: $reason');
    return ExecutionResult(
      wasActualWrite: false,
      ackReceived: false,
      ackSuccess: false,
      failureReason: reason,
    );
  }
}

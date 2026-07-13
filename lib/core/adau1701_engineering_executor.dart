// ── TUNAI Consumer — ADAU1701 Engineering Executor ───────────────────────────
// Controlled write+restore path for hardware verification via BLE transport.
//
// ABSOLUTE RESTRICTIONS:
//   - No EEPROM (addr 0xA0). No Selfboot. No WriteAll.
//   - testWasActualWrite = true ONLY when transport.writeParameter() was called.
//   - Restore always attempted after successful test write.
//
// Guards (in order):
//   G1: BLE transport connected (not null)
//   G2: user confirmed
//   G3: restore value confirmed
//   G4: address != 0xA0 (EEPROM — permanently blocked)
//   G5: candidate isBlocked=false
//   G6: writeShape == singleWordParameter (5-word/unsupported shapes cannot use this path)
//   G7: firmwareConfirmed=true (operator confirmed device runs the expected firmware)
//   G8: valueFormat != unknown AND formatConfirmed=true
//
// BLE writeParameter returns void. Success = no exception = PASS_ACK.
// VERIFIED is NEVER set by executor — requires separate operator manual action.

import 'dsp/transport/dsp_transport.dart';
import 'adau1701_engineering_candidate.dart';

// ── Request ───────────────────────────────────────────────────────────────────

class Adau1701EngWriteRequest {
  final String id;
  final int addressInt;
  final String label;
  final int testValue32;
  final int restoreValue32;
  final bool userConfirmed;
  final bool restoreValueConfirmed;
  final bool isBlocked;
  final Adau1701WriteShape writeShape;
  final bool firmwareConfirmed;
  final bool formatConfirmed;
  final Adau1701ValueFormat valueFormat;

  const Adau1701EngWriteRequest({
    required this.id,
    required this.addressInt,
    required this.label,
    required this.testValue32,
    required this.restoreValue32,
    required this.userConfirmed,
    required this.restoreValueConfirmed,
    required this.isBlocked,
    required this.writeShape,
    required this.firmwareConfirmed,
    required this.formatConfirmed,
    required this.valueFormat,
  });
}

// ── Result ────────────────────────────────────────────────────────────────────

class Adau1701EngWriteResult {
  final String id;
  final bool testWasActualWrite;
  final bool restoreWasActualWrite;
  final bool testWriteOk;
  final bool restoreWriteOk;
  final String? error;
  final Adau1701CandidateStatus resultStatus;
  final DateTime executedAt;
  final String transportDesc;

  const Adau1701EngWriteResult({
    required this.id,
    required this.testWasActualWrite,
    required this.restoreWasActualWrite,
    required this.testWriteOk,
    required this.restoreWriteOk,
    this.error,
    required this.resultStatus,
    required this.executedAt,
    required this.transportDesc,
  });
}

// ── Helpers ───────────────────────────────────────────────────────────────────

List<int> _encode32(int v) => [
      (v >> 24) & 0xFF,
      (v >> 16) & 0xFF,
      (v >> 8) & 0xFF,
      v & 0xFF,
    ];

Adau1701EngWriteResult _blocked(
  String id,
  String error,
  String desc,
  DateTime now,
) =>
    Adau1701EngWriteResult(
      id: id,
      testWasActualWrite: false,
      restoreWasActualWrite: false,
      testWriteOk: false,
      restoreWriteOk: false,
      error: error,
      resultStatus: Adau1701CandidateStatus.blocked,
      executedAt: now,
      transportDesc: desc,
    );

// ── Executor ──────────────────────────────────────────────────────────────────

class Adau1701EngineeringExecutor {
  final DspTransport? transport;

  const Adau1701EngineeringExecutor({required this.transport});

  Future<Adau1701EngWriteResult> writeWithRestore(
      Adau1701EngWriteRequest req) async {
    final now = DateTime.now();
    final desc = transport?.runtimeType.toString() ?? 'null';

    // G1: BLE transport connected
    if (transport == null) {
      return _blocked(req.id, 'G1: BLE transport not connected. Write blocked.', desc, now);
    }

    // G2: User confirmed
    if (!req.userConfirmed) {
      return _blocked(req.id, 'G2: User confirmation missing.', desc, now);
    }

    // G3: Restore value confirmed
    if (!req.restoreValueConfirmed) {
      return _blocked(req.id, 'G3: Restore value not confirmed.', desc, now);
    }

    // G4: EEPROM guard
    if (req.addressInt == 0xA0) {
      return _blocked(
          req.id,
          'G4: Address 0xA0 is the EEPROM I2C address. Write PERMANENTLY blocked.',
          desc,
          now);
    }

    // G5: Candidate isBlocked flag
    if (req.isBlocked) {
      return _blocked(req.id, 'G5: Candidate is blocked. Write disabled.', desc, now);
    }

    // G6: Write shape must be singleWordParameter
    if (req.writeShape != Adau1701WriteShape.singleWordParameter) {
      return _blocked(
          req.id,
          'G6: WRITE_SHAPE_NOT_SUPPORTED. '
          'This address requires ${req.writeShape.label} write; '
          'only singleWordParameter is supported by this executor.',
          desc,
          now);
    }

    // G7: Firmware source must be confirmed
    if (!req.firmwareConfirmed) {
      return _blocked(
          req.id,
          'G7: FIRMWARE_SOURCE_NOT_CONFIRMED. '
          'Operator must confirm the device is running the expected firmware '
          'before writing this address.',
          desc,
          now);
    }

    // G8: Value format must be selected and confirmed
    if (req.valueFormat == Adau1701ValueFormat.unknown || !req.formatConfirmed) {
      return _blocked(
          req.id,
          'G8: FORMAT_NOT_CONFIRMED. '
          'Value format is ${req.valueFormat.label}. '
          'Operator must select a format (5.23/8.24/Raw32) and explicitly confirm it.',
          desc,
          now);
    }

    // All guards passed — perform write+restore
    final testBytes = _encode32(req.testValue32);
    final restoreBytes = _encode32(req.restoreValue32);

    bool testWasActualWrite = false;
    bool restoreWasActualWrite = false;
    bool testWriteOk = false;
    bool restoreWriteOk = false;
    String? error;

    try {
      await transport!.writeParameter(req.addressInt, testBytes);
      testWasActualWrite = true;
      testWriteOk = true;

      // Restore always attempted after successful test write
      await transport!.writeParameter(req.addressInt, restoreBytes);
      restoreWasActualWrite = true;
      restoreWriteOk = true;
    } catch (e) {
      error = 'Write exception: $e';
    }

    final Adau1701CandidateStatus resultStatus;
    if (testWasActualWrite && testWriteOk) {
      resultStatus = Adau1701CandidateStatus.passAck;
    } else {
      resultStatus = Adau1701CandidateStatus.fail;
    }

    return Adau1701EngWriteResult(
      id: req.id,
      testWasActualWrite: testWasActualWrite,
      restoreWasActualWrite: restoreWasActualWrite,
      testWriteOk: testWriteOk,
      restoreWriteOk: restoreWriteOk,
      error: error,
      resultStatus: resultStatus,
      executedAt: now,
      transportDesc: desc,
    );
  }
}

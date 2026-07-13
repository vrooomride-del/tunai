// ── TUNAI Consumer — ADAU1701 Engineering Executor ───────────────────────────
// Controlled write+restore path for hardware verification via BLE transport.
//
// ABSOLUTE RESTRICTIONS:
//   - No EEPROM (addr 0xA0). No Selfboot. No WriteAll.
//   - testWasActualWrite = true ONLY when transport.writeParameter() was called.
//   - G1: BLE transport connected (not null).
//   - G2: user confirmed.
//   - G3: restore value confirmed.
//   - G4: address != 0xA0 (EEPROM guard — permanently blocked).
//   - G5: candidate isBlocked flag must be false.
//   - BLE writeParameter returns void; success = no exception = PASS_ACK.
//   - Restore always attempted after successful test write.

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

  const Adau1701EngWriteRequest({
    required this.id,
    required this.addressInt,
    required this.label,
    required this.testValue32,
    required this.restoreValue32,
    required this.userConfirmed,
    required this.restoreValueConfirmed,
    required this.isBlocked,
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

List<int> _encodeValue32(int v) => [
      (v >> 24) & 0xFF,
      (v >> 16) & 0xFF,
      (v >> 8) & 0xFF,
      v & 0xFF,
    ];

Adau1701EngWriteResult _blocked(
  String id,
  String error,
  String transportDesc,
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
      transportDesc: transportDesc,
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

    // G4: EEPROM guard — address 0xA0 is the EEPROM I2C address, permanently blocked
    if (req.addressInt == 0xA0) {
      return _blocked(
          req.id,
          'G4: Address 0xA0 is the EEPROM I2C address. Write PERMANENTLY blocked.',
          desc,
          now);
    }

    // G5: Candidate blocked flag
    if (req.isBlocked) {
      return _blocked(req.id, 'G5: Candidate is blocked. Write disabled.', desc, now);
    }

    // All guards passed — perform write+restore
    final testBytes = _encodeValue32(req.testValue32);
    final restoreBytes = _encodeValue32(req.restoreValue32);

    bool testWasActualWrite = false;
    bool restoreWasActualWrite = false;
    bool testWriteOk = false;
    bool restoreWriteOk = false;
    String? error;

    try {
      await transport!.writeParameter(req.addressInt, testBytes);
      testWasActualWrite = true;
      testWriteOk = true;

      // Restore always attempted after test write
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

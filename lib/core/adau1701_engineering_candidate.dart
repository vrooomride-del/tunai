// ── TUNAI Consumer — ADAU1701 Engineering Candidate Model ─────────────────────
// ABSOLUTE RESTRICTIONS:
//   - No EEPROM (addr 0xA0). No Selfboot. No WriteAll.
//   - wasActualWrite = true ONLY when transport.writeParameter() was called.
//   - VERIFIED = operator manual mark only, never automatic.
//   - ACK success alone = PASS_ACK, not VERIFIED.
//   - VERIFIED also requires formatConfirmed — format must be explicitly confirmed.
//   - 5-word coefficient-block addresses CANNOT use single-word writeParameter.
//   - Export14 single-word addresses require explicit firmware confirmation.
//   - 5.23 fixed-point format by default (1.0 = 0x00800000). NOT 8.24.

// ── Firmware source identity ──────────────────────────────────────────────────
// Every candidate carries the firmware map it originates from.
// Mixing sources across firmware revisions causes silent bad writes.

enum Adau1701FirmwareSource {
  /// "ADAU1701 v0.8 Export14" — single-word PRAM addresses from factory_screen.dart.
  /// Requires operator to confirm device is running this firmware revision.
  export14SingleWord,

  /// 2026-07-04 recompiled firmware — addresses from adau1701_adapter.dart.
  /// Writes use 5-word DspCompiler coefficient blocks, NOT single writeParameter calls.
  recompiled20260704Adapter,

  /// Source unknown — write disabled until classified.
  unknown;

  String get label => switch (this) {
        export14SingleWord => 'Export14',
        recompiled20260704Adapter => 'Adapter-2026',
        unknown => 'UNKNOWN-SRC',
      };
}

// ── Write shape ────────────────────────────────────────────────────────────────
// Describes the byte layout required for a correct write to this address.
// Do NOT write 5-word blocks through the single-word path.

enum Adau1701WriteShape {
  /// transport.writeParameter(addr, bytes4) — 4-byte single PRAM word.
  singleWordParameter,

  /// DspCompiler.buildBleFrame(RegisterPacket) — 5 × 4 = 20-byte coefficient block.
  /// INCOMPATIBLE with single-word writeParameter. Write BLOCKED in this executor.
  fiveWordCoefficientBlock,

  /// No firmware block exists (delay, PEQ on recompiled firmware). Write is no-op.
  unsupported;

  String get label => switch (this) {
        singleWordParameter => '4B-WORD',
        fiveWordCoefficientBlock => '20B-COEFF',
        unsupported => 'NO-OP',
      };
}

// ── Candidate kind ────────────────────────────────────────────────────────────

enum Adau1701CandidateKind {
  masterVolume,
  gain,
  mute,
  delay,
  peq,
  crossover,
  unknown;

  String get label => switch (this) {
        masterVolume => 'MV',
        gain => 'GAIN',
        mute => 'MUTE',
        delay => 'DELAY',
        peq => 'PEQ',
        crossover => 'XO',
        unknown => 'UNKN',
      };
}

// ── Candidate status ──────────────────────────────────────────────────────────

enum Adau1701CandidateStatus {
  unknown,
  candidate,
  passAck,
  needsMeasurement,
  verified,
  rejected,
  fail,
  blocked;

  String get label => switch (this) {
        unknown => 'UNKNOWN',
        candidate => 'CANDIDATE',
        passAck => 'PASS-ACK',
        needsMeasurement => 'NEEDS-MEAS',
        verified => 'VERIFIED',
        rejected => 'REJECTED',
        fail => 'FAIL',
        blocked => 'BLOCKED',
      };
}

// ── Value format ──────────────────────────────────────────────────────────────
// unknown is the default — must be changed AND confirmed before execution.

enum Adau1701ValueFormat {
  /// Not yet selected. Blocks execution. Operator must select a format explicitly.
  unknown,

  /// 5.23 fixed-point — ADAU1701 standard (1.0 = 0x00800000). Default for ADAU1701.
  fixed523,

  /// 8.24 fixed-point — ADAU1466 format (1.0 = 0x01000000). Do NOT assume for ADAU1701.
  fixed824,

  /// Raw 32-bit big-endian integer, no fixed-point encoding.
  raw32;

  String get label => switch (this) {
        unknown => 'UNKN-FMT',
        fixed523 => '5.23',
        fixed824 => '8.24',
        raw32 => 'RAW32',
      };
}

// ── Address Candidate ─────────────────────────────────────────────────────────

class Adau1701AddressCandidate {
  final String id;
  final int addressInt;
  final String addressHex;
  final String label;
  final String channelName;
  final Adau1701CandidateKind kind;
  final Adau1701FirmwareSource firmwareSource;
  final Adau1701WriteShape writeShape;
  final bool isBlocked; // true = permanently blocked (write-shape mismatch, PEQ, etc.)
  final String? blockReason;
  final String exportDefaultHex;

  Adau1701CandidateStatus status;
  String testValueHex;
  String restoreValueHex;
  Adau1701ValueFormat valueFormat;

  /// true = operator has confirmed the device runs the firmware this candidate targets.
  /// MV (0x0004/0x0005) is pre-set true (production-verified via MasterVolumeController).
  /// Export14 gain candidates start false — require operator confirmation before write.
  bool firmwareConfirmed;

  /// true = operator has explicitly confirmed the value format after selecting it.
  /// Resets to false whenever valueFormat changes.
  /// Required for both Execute and VERIFIED.
  bool formatConfirmed;

  bool wasActualWrite;
  String? lastError;
  String? measurementNote;
  String? operatorNote;
  DateTime? executedAt;

  Adau1701AddressCandidate({
    required this.id,
    required this.addressInt,
    required this.addressHex,
    required this.label,
    required this.channelName,
    required this.kind,
    required this.firmwareSource,
    required this.writeShape,
    required this.isBlocked,
    this.blockReason,
    required this.exportDefaultHex,
    required this.status,
    required this.testValueHex,
    required this.restoreValueHex,
    this.valueFormat = Adau1701ValueFormat.unknown,
    this.firmwareConfirmed = false,
    this.formatConfirmed = false,
    this.wasActualWrite = false,
    this.lastError,
    this.measurementNote,
    this.operatorNote,
    this.executedAt,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'addressInt': addressInt,
        'addressHex': addressHex,
        'label': label,
        'channelName': channelName,
        'kind': kind.name,
        'firmwareSource': firmwareSource.name,
        'writeShape': writeShape.name,
        'isBlocked': isBlocked,
        if (blockReason != null) 'blockReason': blockReason,
        'exportDefaultHex': exportDefaultHex,
        'status': status.name,
        'testValueHex': testValueHex,
        'restoreValueHex': restoreValueHex,
        'valueFormat': valueFormat.name,
        'firmwareConfirmed': firmwareConfirmed,
        'formatConfirmed': formatConfirmed,
        'wasActualWrite': wasActualWrite,
        if (lastError != null) 'lastError': lastError,
        if (measurementNote != null) 'measurementNote': measurementNote,
        if (operatorNote != null) 'operatorNote': operatorNote,
        if (executedAt != null) 'executedAt': executedAt!.toIso8601String(),
      };

  factory Adau1701AddressCandidate.fromJson(Map<String, dynamic> j) =>
      Adau1701AddressCandidate(
        id: j['id'] as String,
        addressInt: j['addressInt'] as int,
        addressHex: j['addressHex'] as String,
        label: j['label'] as String,
        channelName: j['channelName'] as String? ?? '',
        kind: Adau1701CandidateKind.values.firstWhere(
            (e) => e.name == j['kind'],
            orElse: () => Adau1701CandidateKind.unknown),
        firmwareSource: Adau1701FirmwareSource.values.firstWhere(
            (e) => e.name == j['firmwareSource'],
            orElse: () => Adau1701FirmwareSource.unknown),
        writeShape: Adau1701WriteShape.values.firstWhere(
            (e) => e.name == j['writeShape'],
            orElse: () => Adau1701WriteShape.unsupported),
        isBlocked: j['isBlocked'] as bool? ?? false,
        blockReason: j['blockReason'] as String?,
        exportDefaultHex: j['exportDefaultHex'] as String? ?? '00000000',
        status: Adau1701CandidateStatus.values.firstWhere(
            (e) => e.name == j['status'],
            orElse: () => Adau1701CandidateStatus.unknown),
        testValueHex: j['testValueHex'] as String? ?? '00000000',
        restoreValueHex: j['restoreValueHex'] as String? ?? '00000000',
        valueFormat: Adau1701ValueFormat.values.firstWhere(
            (e) => e.name == j['valueFormat'],
            orElse: () => Adau1701ValueFormat.unknown),
        firmwareConfirmed: j['firmwareConfirmed'] as bool? ?? false,
        formatConfirmed: j['formatConfirmed'] as bool? ?? false,
        wasActualWrite: j['wasActualWrite'] as bool? ?? false,
        lastError: j['lastError'] as String?,
        measurementNote: j['measurementNote'] as String?,
        operatorNote: j['operatorNote'] as String?,
        executedAt: j['executedAt'] != null
            ? DateTime.tryParse(j['executedAt'] as String)
            : null,
      );
}

// ── Engineering Log Entry ─────────────────────────────────────────────────────

class Adau1701EngLogEntry {
  final DateTime timestamp;
  final int addressInt;
  final String addressHex;
  final String label;
  final String channelName;
  final String kind;
  final String firmwareSource;
  final String writeShape;
  final String testValueHex;
  final String restoreValueHex;
  final String valueFormat;
  final bool formatConfirmed;
  final bool testWasActualWrite;
  final bool restoreWasActualWrite;
  final String resultStatus;
  final String? error;
  final String? measurementNote;
  final String? operatorNote;
  final String version;

  const Adau1701EngLogEntry({
    required this.timestamp,
    required this.addressInt,
    required this.addressHex,
    required this.label,
    required this.channelName,
    required this.kind,
    required this.firmwareSource,
    required this.writeShape,
    required this.testValueHex,
    required this.restoreValueHex,
    required this.valueFormat,
    required this.formatConfirmed,
    required this.testWasActualWrite,
    required this.restoreWasActualWrite,
    required this.resultStatus,
    this.error,
    this.measurementNote,
    this.operatorNote,
    required this.version,
  });

  Map<String, dynamic> toJson() => {
        'timestamp': timestamp.toIso8601String(),
        'addressInt': addressInt,
        'addressHex': addressHex,
        'label': label,
        'channelName': channelName,
        'kind': kind,
        'firmwareSource': firmwareSource,
        'writeShape': writeShape,
        'testValueHex': testValueHex,
        'restoreValueHex': restoreValueHex,
        'valueFormat': valueFormat,
        'formatConfirmed': formatConfirmed,
        'testWasActualWrite': testWasActualWrite,
        'restoreWasActualWrite': restoreWasActualWrite,
        'resultStatus': resultStatus,
        if (error != null) 'error': error,
        if (measurementNote != null) 'measurementNote': measurementNote,
        if (operatorNote != null) 'operatorNote': operatorNote,
        'version': version,
      };

  factory Adau1701EngLogEntry.fromJson(Map<String, dynamic> j) =>
      Adau1701EngLogEntry(
        timestamp: DateTime.parse(j['timestamp'] as String),
        addressInt: j['addressInt'] as int,
        addressHex: j['addressHex'] as String,
        label: j['label'] as String? ?? '',
        channelName: j['channelName'] as String? ?? '',
        kind: j['kind'] as String? ?? '',
        firmwareSource: j['firmwareSource'] as String? ?? 'unknown',
        writeShape: j['writeShape'] as String? ?? 'unsupported',
        testValueHex: j['testValueHex'] as String? ?? '',
        restoreValueHex: j['restoreValueHex'] as String? ?? '',
        valueFormat: j['valueFormat'] as String? ?? 'unknown',
        formatConfirmed: j['formatConfirmed'] as bool? ?? false,
        testWasActualWrite: j['testWasActualWrite'] as bool? ?? false,
        restoreWasActualWrite: j['restoreWasActualWrite'] as bool? ?? false,
        resultStatus: j['resultStatus'] as String? ?? 'unknown',
        error: j['error'] as String?,
        measurementNote: j['measurementNote'] as String?,
        operatorNote: j['operatorNote'] as String?,
        version: j['version'] as String? ?? '',
      );
}

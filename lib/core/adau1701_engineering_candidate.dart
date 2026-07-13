// ── TUNAI Consumer — ADAU1701 Engineering Candidate Model ─────────────────────
// ABSOLUTE RESTRICTIONS:
//   - No EEPROM (addr 0xA0). No Selfboot. No WriteAll.
//   - wasActualWrite = true ONLY when transport.writeParameter() was called.
//   - VERIFIED = operator manual mark only, never automatic.
//   - ACK success alone = PASS_ACK, not VERIFIED.
//   - Mute/Delay/PEQ blocked until prerequisites met.
//   - 5.23 fixed-point format by default (1.0 = 0x00800000).

enum Adau1701CandidateKind {
  masterVolume,
  gain,
  mute,
  delay,
  peq,
  unknown;

  String get label => switch (this) {
        masterVolume => 'MV',
        gain => 'GAIN',
        mute => 'MUTE',
        delay => 'DELAY',
        peq => 'PEQ',
        unknown => 'UNKN',
      };
}

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

enum Adau1701ValueFormat {
  fixed523, // 5.23 fixed-point — ADAU1701 default (1.0 = 0x00800000)
  fixed824, // 8.24 fixed-point — ADAU1466 format (1.0 = 0x01000000)
  raw32; // raw 32-bit integer, no encoding applied

  String get label => switch (this) {
        fixed523 => '5.23',
        fixed824 => '8.24',
        raw32 => 'RAW32',
      };
}

class Adau1701AddressCandidate {
  final String id;
  final int addressInt;
  final String addressHex;
  final String label;
  final String channelName;
  final Adau1701CandidateKind kind;
  final bool isBlocked;
  final String? blockReason;
  final String exportDefaultHex; // nominal value (8-char hex)

  Adau1701CandidateStatus status;
  String testValueHex;
  String restoreValueHex;
  Adau1701ValueFormat valueFormat;
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
    required this.isBlocked,
    this.blockReason,
    required this.exportDefaultHex,
    required this.status,
    required this.testValueHex,
    required this.restoreValueHex,
    required this.valueFormat,
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
        'isBlocked': isBlocked,
        if (blockReason != null) 'blockReason': blockReason,
        'exportDefaultHex': exportDefaultHex,
        'status': status.name,
        'testValueHex': testValueHex,
        'restoreValueHex': restoreValueHex,
        'valueFormat': valueFormat.name,
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
            orElse: () => Adau1701ValueFormat.fixed523),
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
  final String testValueHex;
  final String restoreValueHex;
  final String valueFormat;
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
    required this.testValueHex,
    required this.restoreValueHex,
    required this.valueFormat,
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
        'testValueHex': testValueHex,
        'restoreValueHex': restoreValueHex,
        'valueFormat': valueFormat,
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
        testValueHex: j['testValueHex'] as String? ?? '',
        restoreValueHex: j['restoreValueHex'] as String? ?? '',
        valueFormat: j['valueFormat'] as String? ?? 'fixed523',
        testWasActualWrite: j['testWasActualWrite'] as bool? ?? false,
        restoreWasActualWrite: j['restoreWasActualWrite'] as bool? ?? false,
        resultStatus: j['resultStatus'] as String? ?? 'unknown',
        error: j['error'] as String?,
        measurementNote: j['measurementNote'] as String?,
        operatorNote: j['operatorNote'] as String?,
        version: j['version'] as String? ?? '',
      );
}

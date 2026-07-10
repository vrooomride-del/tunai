/// Records a single DSP address write attempt for operator audit.
///
/// [liveWriteVerified] is NEVER set automatically — it requires explicit
/// operator confirmation that the hardware responded as expected.
/// [wasActualWrite] true + [ackSuccess] true = validationAttempted only.
library;

enum AddressValidationStatus {
  /// No bytes were sent — dry-run or guard failure.
  dryRunOnly,

  /// Bytes were sent and ACK was received. Hardware effect unconfirmed.
  validationAttempted,

  /// Operator manually confirmed hardware response matches expectation.
  /// Set only by explicit human action — never set automatically.
  liveWriteVerified,
}

class AddressValidationAttempt {
  final int address;
  final double value;
  final DateTime timestamp;
  final bool dryRunOnly;
  final bool wasActualWrite;
  final bool ackReceived;
  final bool ackSuccess;
  final bool operatorConfirmed;
  final AddressValidationStatus resultStatus;

  /// True only after explicit manual operator confirmation that hardware
  /// responded correctly. NEVER set automatically from ACK alone.
  final bool liveWriteVerified;

  const AddressValidationAttempt({
    required this.address,
    required this.value,
    required this.timestamp,
    required this.dryRunOnly,
    required this.wasActualWrite,
    required this.ackReceived,
    required this.ackSuccess,
    required this.operatorConfirmed,
    required this.resultStatus,
    this.liveWriteVerified = false,
  });

  String get addressHex => '0x${address.toRadixString(16).toUpperCase().padLeft(4, '0')}';
}

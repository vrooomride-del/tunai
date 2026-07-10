/// Transport abstraction for controlled DSP hardware writes.
///
/// Only [HardwareTransportBackend.usbiWindowsTemporary] is active.
/// ICP5 (BLE) is the final intended target — this envelope model is
/// transport-independent so address logic stays in [DspAddressRegistry].
library;

enum HardwareTransportBackend {
  /// Temporary Windows engineering path via SIGMA STUDIO USBi adapter.
  /// NOT the final transport — ICP5 remains the production target.
  usbiWindowsTemporary,

  /// Final production transport via ICP5 BLE GATT — NOT YET IMPLEMENTED.
  bleIcp5Future,
}

enum CommandType {
  /// ADAU1466 Master Volume Left — address 0x0067, 8.24 fixed-point.
  masterVolumeL,

  /// ADAU1466 Master Volume Right — address 0x0064, 8.24 fixed-point.
  masterVolumeR,
}

/// Wraps a single hardware write command with guards, confirmation state,
/// and result fields. [wasActualWrite] and [ackReceived] default to false
/// and are only set true by the executor after physical bytes are sent.
class TransportCommandEnvelope {
  final HardwareTransportBackend transport;
  final CommandType commandType;

  /// DSP PRAM address — must be in [DspAddressRegistry.usbiAllowedAddresses].
  final int address;

  /// Normalised value in [0.0, 1.0] — converted to 8.24 fixed-point by the executor.
  final double value;

  /// True only after the operator explicitly confirmed the write in the UI.
  final bool operatorConfirmed;

  /// If true, the executor builds packets and validates but does NOT call
  /// sendSetup / sendBody. Defaults to false (live execution path).
  bool dryRunOnly;

  /// Set true by [ProUsbiTemporaryExecutor] only after [sendBody] is called.
  /// Remains false if any guard fails or if setup fails before the body.
  bool wasActualWrite;

  /// Set true only after [readAck] returns a response (success or failure).
  bool ackReceived;

  /// Populated with guard or transport failure description on failure.
  String? failureReason;

  TransportCommandEnvelope({
    required this.transport,
    required this.commandType,
    required this.address,
    required this.value,
    required this.operatorConfirmed,
    this.dryRunOnly = false,
    this.wasActualWrite = false,
    this.ackReceived = false,
    this.failureReason,
  });
}

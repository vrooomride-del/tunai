/// Canonical registry of confirmed DSP PRAM addresses.
///
/// Addresses are transport-independent — the same address is used regardless
/// of whether the transport is USBi, ICP5/BLE, or SPI.
///
/// IMPORTANT: Do NOT hardcode DSP addresses in transport-specific code.
/// All addresses live here and are referenced by name.
library;

class DspAddressRegistry {
  DspAddressRegistry._();

  // ── ADAU1466 Master Volume ─────────────────────────────────────────────────
  // SigmaStudio PRAM parameter RAM. These are volatile — lost on power cycle.
  // Encoding: 8.24 fixed-point big-endian (1.0 = 0x01000000).
  // Restore path: write 1.0 (0x01000000) to both addresses.

  /// ADAU1466 Master Volume Left channel. Confirmed USBi write target.
  static const int adau1466MasterVolumeL = 0x0067;

  /// ADAU1466 Master Volume Right channel. Confirmed USBi write target.
  static const int adau1466MasterVolumeR = 0x0064;

  // ── USBi temporary executor allowed set ───────────────────────────────────
  // Only these addresses may pass Guard D5.
  // Do NOT expand this set without a new phase review.

  /// Addresses the [ProUsbiTemporaryExecutor] is permitted to write.
  /// All other addresses are blocked at Guard D5.
  static const Set<int> usbiAllowedAddresses = {
    adau1466MasterVolumeL,
    adau1466MasterVolumeR,
  };

  // ── Forbidden — never write from any consumer or automated path ───────────

  // EEPROM I2C address — NEVER write. Listed here as documentation only.
  // ignore: unused_field
  static const int _forbiddenEepromI2c = 0xA0; // NEVER WRITE
}

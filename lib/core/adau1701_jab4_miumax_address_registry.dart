/// ADAU1701 parameter address map extracted from Export(19) — WONDOM JAB4
/// original Miumax firmware.
///
/// Source file: wondom_miumax_original_export19_address_map.csv
/// DSP:  ADAU1701
/// I2C:  0x68 (device), 0xA0 (EEPROM — NEVER WRITE)
///
/// Gain format: 5.23 fixed-point, 4-byte Big Endian.
///   0 dB  = 00 80 00 00  (1.0  in 5.23 FP)
/// -40 dB  = 00 01 47 AE
/// -50 dB  = 00 00 67 9F
/// -60 dB  = 00 00 20 C5
///
/// Phase 1 hardware test must use Default Gain (direct, no-slew) addresses
/// 0x0321–0x0324.  Do NOT use ExtSWGainDB volume addresses 0x0006/0x0007/
/// 0x0320/0x0329 in Phase 1 — those are controlled by Aux ADC / external
/// logic and will not behave as direct gain writes.
library;

class Adau1701Jab4MiumaxAddressRegistry {
  Adau1701Jab4MiumaxAddressRegistry._();

  // ── I2C device addresses ──────────────────────────────────────────────────

  /// ADAU1701 DSP I2C address (write: 0xD0, read: 0xD1).
  static const int i2cDspAddress = 0x68;

  /// EEPROM I2C address.  NEVER WRITE — risk of overwriting boot program.
  // ignore: unused_field
  static const int _i2cEepromAddress = 0xA0; // documented, access forbidden

  // ── Phase 1 — Default Gain (Gain1940 direct, no-slew) ────────────────────
  //
  // These four addresses must be written together with the same value.
  // Source rows: Default Gain.Gain3 / Gain1 (Gain1940AlgNS1/2/9/10).
  // Category: direct_driver_gain_safe_test (confirmed safe per test summary).

  /// Default Gain.Gain3 ch A — Gain1940AlgNS9.
  static const int defaultGain3ChA = 0x0321;

  /// Default Gain.Gain3 ch B — Gain1940AlgNS10.
  static const int defaultGain3ChB = 0x0322;

  /// Default Gain.Gain1 ch B — Gain1940AlgNS2.
  static const int defaultGain1ChB = 0x0323;

  /// Default Gain.Gain1 ch A — Gain1940AlgNS1.
  static const int defaultGain1ChA = 0x0324;

  /// Phase 1 test address set — all four must be written identically.
  static const Set<int> phase1GainAddresses = {
    defaultGain3ChA,
    defaultGain3ChB,
    defaultGain1ChB,
    defaultGain1ChA,
  };

  // ── ExtSWGainDB Volume — DO NOT USE IN PHASE 1 ───────────────────────────
  //
  // These are step parameters driven by Aux ADC / external control.
  // Direct writes will NOT reliably change output gain.

  /// Volume.Vol_2 step — ExtSWGainDB3step.  NOT a direct gain value.
  static const int volumeVol2Step = 0x0006;

  /// Volume.Vol step — ExtSWGainDB2step.  NOT a direct gain value.
  static const int volumeVolStep = 0x0007;

  /// Default Gain SW vol step — ExtSWGainDB1step.  NOT a direct gain value.
  static const int defaultGainSwVolStep = 0x0320;

  /// SS.SW vol step — ExtSWGainDB5step.  NOT a direct gain value.
  static const int ssSwVolStep = 0x0329;

  // ── Mute candidates — verify polarity before use ─────────────────────────
  //
  // 0/1 meaning must be confirmed via SigmaStudio Capture Window before
  // writing from the app.  0 = muted or unmuted depends on DSP logic.

  /// Mute0_2 — MuteSWSlewAlg2mute.  Polarity unverified.
  static const int mute0_2 = 0x000B;

  /// Mute1 — MuteSWSlewAlg3mute.  Polarity unverified.
  static const int mute1Candidate = 0x0325;

  /// Mute0 — MuteSWSlewAlg1mute.  Polarity unverified.
  static const int mute0Candidate = 0x0327;

  // ── Known 5.23 fixed-point gain byte values ───────────────────────────────
  //
  // 5.23 FP: integer part in bits 31–23, fractional in bits 22–0.
  // 1.0 = 0x00800000 (bit 23 set).  Values confirmed from Export(19) map.

  /// 0 dB (unity gain) — restore value.
  static const List<int> gain0dB = [0x00, 0x80, 0x00, 0x00];

  /// -40 dB.
  static const List<int> gainNeg40dB = [0x00, 0x01, 0x47, 0xAE];

  /// -50 dB.
  static const List<int> gainNeg50dB = [0x00, 0x00, 0x67, 0x9F];

  /// -60 dB.
  static const List<int> gainNeg60dB = [0x00, 0x00, 0x20, 0xC5];

  /// Named presets for UI display.
  static const Map<String, List<int>> gainPresets = {
    '0 dB (restore)': gain0dB,
    '-40 dB': gainNeg40dB,
    '-50 dB': gainNeg50dB,
    '-60 dB': gainNeg60dB,
  };
}

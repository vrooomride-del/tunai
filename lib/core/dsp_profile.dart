/// DSP chip / firmware identity used to select the correct address map
/// and transport packet format.
///
/// Rules:
///   ADAU1466 uses SPI-via-USBi with 8.24 fixed-point gain encoding.
///   ADAU1701 uses I2C-via-USBi with 5.23 fixed-point gain encoding.
///   Never mix packet formats between profiles.
library;

enum DspProfile {
  /// ADAU1466 — custom TUNAI v0.8 3-way DSP (experimental, not first product).
  /// Transport: USBi → SPI.  Gain format: 8.24 FP.
  adau1466,

  /// ADAU1701 on WONDOM JAB4 running original Miumax firmware.
  /// Transport: USBi → I2C 0x68.  Gain format: 5.23 FP.
  /// This is the firmware base for TUNAI ONE v1.0.
  adau1701Jab4MiumaxOriginal,

  /// ADAU1701 on WONDOM JAB4 with future TUNAI-native DSP program.
  /// Not used in first product — reserved for future engineering.
  adau1701Jab4TunaiNativeV08Future,
}

extension DspProfileExt on DspProfile {
  String get displayName => switch (this) {
        DspProfile.adau1466 => 'ADAU1466 (TUNAI v0.8 experimental)',
        DspProfile.adau1701Jab4MiumaxOriginal =>
          'ADAU1701 / JAB4 – Miumax Original',
        DspProfile.adau1701Jab4TunaiNativeV08Future =>
          'ADAU1701 / JAB4 – TUNAI Native v0.8 (future)',
      };

  /// I2C address of the DSP (not valid for SPI-only chips).
  /// Returns null if the profile does not use I2C.
  int? get i2cAddress => switch (this) {
        DspProfile.adau1701Jab4MiumaxOriginal => 0x68,
        DspProfile.adau1701Jab4TunaiNativeV08Future => 0x68,
        _ => null,
      };
}

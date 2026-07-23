/// The user's chosen sound character — plain consumer language only, never
/// PEQ/DSP/gain terms. Selected once per Tune (see `_StateC` in
/// ai_screen.dart) and carried on the resulting [ConsumerSoundProfile] as
/// part of "Personal Sound Profile" (Room + Measurement + Tune + Preference
/// + Apply state, managed as one experience).
///
/// Every preference only ever *reduces* how much of a real, measured room
/// resonance gets corrected — see [intensity]/[midBandFactor] — never
/// increases it beyond what [TunePlanner] already computes as safe.
/// [TuneSafetyBounds] remains the hard ceiling regardless of preference; a
/// preference can only pull a correction further inside that envelope, never
/// outside it. No new frequency region is measured or corrected because of a
/// preference — the current pipeline only detects and corrects real room
/// modes at 20–300Hz (see `AudioAnalyzer.roomModeSearchCeilingHz`).
///
/// Preferences differ in *shape*, not just overall strength: each real,
/// measured peak is weighted by [weightFor] depending on which side of
/// [midBandThresholdHz] its own real frequency falls on — a low sub-bass
/// buildup (e.g. "room boom") and an upper-bass/boxiness buildup (e.g. "room
/// mud") are different, well-understood acoustic characters, and a
/// preference can reasonably treat them differently using only the real
/// frequency already measured for that peak. This never fabricates a
/// per-band effect the app can't actually measure — it only changes how
/// assertively the same, already-real data is corrected.
enum SoundPreference {
  /// TunePlanner's own default, unscaled behavior. The safest, most
  /// conservative choice — every other preference only softens from here.
  balanced(intensity: 1.0, midBandFactor: 1.0),

  /// Keeps deep bass fullness (gentle on the low sub-bass buildup) while
  /// still cleaning up boxy/muddy upper-bass buildup — a real "warm"
  /// tonal shape, not just a uniformly softer correction.
  warm(intensity: 0.6, midBandFactor: 0.95),

  /// Full correction of the measured room-mode buildup on both sides for
  /// the least coloration.
  clear(intensity: 1.0, midBandFactor: 1.0),

  /// Broad and even — moderate, similar-strength correction on both sides
  /// rather than a sharply shaped one, for a smooth, non-boxy character.
  open(intensity: 0.8, midBandFactor: 0.8),

  /// Assertive on the low-frequency buildup that can mask vocal
  /// fundamentals through psychoacoustic masking (a real, well-established
  /// effect), while staying more moderate on the upper-bass band to keep
  /// some natural body.
  vocal(intensity: 1.0, midBandFactor: 0.7);

  const SoundPreference({required this.intensity, required this.midBandFactor});

  /// Real per-peak frequency split between the "low" sub-bass buildup and
  /// the "boxy/mud" upper-bass buildup. Both bands still sit fully inside
  /// the pipeline's own real 20–300Hz room-mode detection range — this only
  /// distinguishes two acoustically different characters within data that
  /// was already measured, never a new region.
  static const double midBandThresholdHz = 100.0;

  /// Scale factor (0.0–1.0) applied to a measured room-mode correction
  /// below [midBandThresholdHz] (deep/sub-bass buildup), before the existing
  /// [TuneSafetyBounds] checks run — see [TunePlanner.generate]. Never
  /// exceeds 1.0.
  final double intensity;

  /// Scale factor (0.0–1.0) applied to a measured room-mode correction at or
  /// above [midBandThresholdHz] (upper-bass/boxiness buildup). Never exceeds
  /// 1.0.
  final double midBandFactor;

  /// The real, per-peak weight to use for a peak actually measured at
  /// [frequencyHz] — [intensity] below [midBandThresholdHz], [midBandFactor]
  /// at or above it.
  double weightFor(double frequencyHz) =>
      frequencyHz < midBandThresholdHz ? intensity : midBandFactor;

  String label({required bool ko}) => switch (this) {
        SoundPreference.balanced => ko ? '자연스럽게' : 'Balanced',
        SoundPreference.warm => ko ? '따뜻하게' : 'Warm',
        SoundPreference.clear => ko ? '선명하게' : 'Clear',
        SoundPreference.open => ko ? '넓게' : 'Open',
        SoundPreference.vocal => ko ? '보컬 중심으로' : 'Vocal',
      };

  String description({required bool ko}) => switch (this) {
        SoundPreference.balanced =>
          ko ? '어느 쪽으로도 치우치지 않는 균형 잡힌 소리' : 'A natural, even balance',
        SoundPreference.warm =>
          ko ? '저역의 풍성함을 살린 부드러운 소리' : 'Smooth, with more bass fullness',
        SoundPreference.clear =>
          ko ? '군더더기 없이 또렷하고 깨끗한 소리' : 'Clean and detailed, less clutter',
        SoundPreference.open => ko ? '답답함 없이 넓고 시원한 소리' : 'Spacious, less boxy',
        SoundPreference.vocal =>
          ko ? '목소리가 또렷하게 들리는 소리' : 'Vocals brought forward',
      };

  String toJson() => name;

  static SoundPreference fromJson(String? value) => switch (value) {
        'warm' => SoundPreference.warm,
        'clear' => SoundPreference.clear,
        'open' => SoundPreference.open,
        'vocal' => SoundPreference.vocal,
        _ => SoundPreference.balanced,
      };
}

import 'sound_preference.dart';

/// Consumer-facing "Fine Tune" knobs — five plain-language sliders, each
/// mapped to a real, already-existing, safety-bounded parameter of the Tune
/// Engine (see [TunePlanner.generate]). None of these invent a new
/// frequency region, new measurement, or effect beyond what the room scan
/// actually captured; they only change how much of that same real,
/// already-measured correction is applied and how it's shaped — the same
/// principle [SoundPreference] already follows.
///
/// - [bassWeight] — how assertively the low, sub-bass room-mode buildup
///   (below [SoundPreference.midBandThresholdHz]) is corrected.
/// - [warmWeight] — how assertively the upper-bass/boxiness buildup (at or
///   above the threshold) is corrected. Lower = warmer (more of that
///   natural fullness kept); higher = cleaner.
/// - [vocalWeight] — an overall multiplier on top of both bands, standing
///   in for how strongly to reduce the low-frequency masking that can bury
///   vocal fundamentals (see [SoundPreference.vocal]).
/// - [spaceWeight] — blends each band's correction shape between a broader,
///   gentler curve (0.0) and the room's own real measured sharpness (1.0,
///   surgical/precise) — never sharper than what was actually measured.
/// - [detailBandLimit] — how many of the safety-validated candidate bands to
///   keep, most-significant first. `null` means "no additional limit beyond
///   [TuneSafetyBounds.maximumBands]" — the same behavior as before Fine
///   Tune existed. When set, it can never exceed [maxDetailBandLimit], the
///   real Consumer ADAU1701 deployable band capacity (see
///   `DspCapability.consumerAdau1701`) — Fine Tune can never promise a band
///   that can't actually be deployed.
class FineTuneAdjustments {
  final double bassWeight;
  final double warmWeight;
  final double vocalWeight;
  final double spaceWeight;
  final int? detailBandLimit;

  const FineTuneAdjustments({
    this.bassWeight = 1.0,
    this.warmWeight = 1.0,
    this.vocalWeight = 1.0,
    this.spaceWeight = 1.0,
    this.detailBandLimit,
  })  : assert(bassWeight >= 0 && bassWeight <= 1),
        assert(warmWeight >= 0 && warmWeight <= 1),
        assert(vocalWeight >= 0 && vocalWeight <= 1),
        assert(spaceWeight >= 0 && spaceWeight <= 1),
        assert(detailBandLimit == null ||
            (detailBandLimit >= 1 && detailBandLimit <= maxDetailBandLimit));

  static const int maxDetailBandLimit = 3;

  static const neutral = FineTuneAdjustments();

  bool get isNeutral =>
      bassWeight == 1.0 &&
      warmWeight == 1.0 &&
      vocalWeight == 1.0 &&
      spaceWeight == 1.0 &&
      detailBandLimit == null;

  FineTuneAdjustments copyWith({
    double? bassWeight,
    double? warmWeight,
    double? vocalWeight,
    double? spaceWeight,
    int? detailBandLimit,
  }) =>
      FineTuneAdjustments(
        bassWeight: bassWeight ?? this.bassWeight,
        warmWeight: warmWeight ?? this.warmWeight,
        vocalWeight: vocalWeight ?? this.vocalWeight,
        spaceWeight: spaceWeight ?? this.spaceWeight,
        detailBandLimit: detailBandLimit ?? this.detailBandLimit,
      );

  /// Short, deterministic id suffix so different Fine Tune settings for the
  /// same measurement/preference don't collide on TunePlan id.
  String get idSuffix => isNeutral
      ? ''
      : ':ft-${(bassWeight * 100).round()}-${(warmWeight * 100).round()}-'
          '${(vocalWeight * 100).round()}-${(spaceWeight * 100).round()}-'
          '${detailBandLimit ?? 0}';
}

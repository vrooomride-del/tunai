import 'tune_plan.dart';

/// One plain-language statement about what a Tune actually did — no dB, Hz, Q,
/// PEQ, or any other engineering term, and never a fixed marketing line.
///
/// Every item here is derived from real [TuneCorrectionBand]s that a Tune
/// genuinely contains and that were genuinely deployed. If a Tune has no
/// bands, [TuneResultSummary.of] returns an empty summary and the UI shows
/// nothing rather than inventing an improvement.
class TuneResultPoint {
  /// Consumer-facing wording. `ko`/`en` chosen by the caller.
  final String Function({required bool ko}) label;

  const TuneResultPoint(this.label);
}

/// Groups a real, deployed [TunePlan] into at most a few consumer-facing
/// statements. Pure and side-effect free so it is exhaustively testable and
/// can be reused by both the TUNE result screen and LISTEN.
///
/// This never fabricates: an empty plan yields [points] == [] and
/// [hasAnyChange] == false. The wording describes the DIRECTION and REGION of
/// real corrections (which frequency regions were adjusted, and whether the
/// net move there was a reduction or a lift), which is information the plan
/// actually carries — not a claim about how much "better" it sounds.
class TuneResultSummary {
  final List<TuneResultPoint> points;

  const TuneResultSummary(this.points);

  bool get hasAnyChange => points.isNotEmpty;

  /// Frequency-region boundaries, in Hz. Chosen to match how a listener
  /// describes sound ("low / mid / high"), not any DSP band split.
  static const double _lowMidHz = 300;
  static const double _midHighHz = 2000;

  static TuneResultSummary of(TunePlan? plan) {
    if (plan == null || plan.bands.isEmpty) return const TuneResultSummary([]);

    // Net signed gain per region: a region corrected down (resonance/excess
    // removed) reads differently from one lifted (a dip filled). Summing
    // signed gains means two opposing small moves correctly cancel rather
    // than both being announced.
    var lowNet = 0.0, midNet = 0.0, highNet = 0.0;
    var lowTouched = false, midTouched = false, highTouched = false;
    var hasTonalBalance = false, hasRoomMode = false;

    for (final band in plan.bands) {
      if (band.frequencyHz < _lowMidHz) {
        lowNet += band.gainDb;
        lowTouched = true;
      } else if (band.frequencyHz < _midHighHz) {
        midNet += band.gainDb;
        midTouched = true;
      } else {
        highNet += band.gainDb;
        highTouched = true;
      }
      switch (band.source) {
        case TuneCorrectionSource.tonalBalance:
        case TuneCorrectionSource.preferenceTarget:
          hasTonalBalance = true;
        case TuneCorrectionSource.roomMode:
        case TuneCorrectionSource.speakerCharacter:
          hasRoomMode = true;
      }
    }

    final points = <TuneResultPoint>[];

    if (lowTouched) {
      final tightened = lowNet < 0;
      points.add(TuneResultPoint(({required bool ko}) => tightened
          ? (ko ? '저음을 더 단단하게 정리했어요' : 'Tightened the low end')
          : (ko ? '부족했던 저음을 채웠어요' : 'Filled in a lacking low end')));
    }
    if (midTouched) {
      final calmed = midNet < 0;
      points.add(TuneResultPoint(({required bool ko}) => calmed
          ? (ko ? '중음의 울림을 가라앉혔어요' : 'Calmed a boxy midrange')
          : (ko ? '중음을 또렷하게 살렸어요' : 'Brought the midrange forward')));
    }
    if (highTouched) {
      final softened = highNet < 0;
      points.add(TuneResultPoint(({required bool ko}) => softened
          ? (ko ? '고음의 날카로움을 부드럽게 했어요' : 'Softened a harsh treble')
          : (ko ? '고음의 선명함을 더했어요' : 'Added clarity up top')));
    }

    // A single umbrella line describing the WHAT, chosen by which correction
    // sources were actually present — placed first so it reads as the
    // headline, with the per-region points as the detail beneath it.
    if (hasTonalBalance && hasRoomMode) {
      points.insert(
          0,
          TuneResultPoint(({required bool ko}) => ko
              ? '공간의 울림과 전체 음색 밸런스를 함께 조정했어요'
              : 'Balanced your room’s response and overall tone'));
    } else if (hasTonalBalance) {
      points.insert(
          0,
          TuneResultPoint(({required bool ko}) =>
              ko ? '공간에 맞춰 전체 음색 밸런스를 조정했어요' : 'Balanced the overall tone for your space'));
    } else if (hasRoomMode) {
      points.insert(
          0,
          TuneResultPoint(({required bool ko}) =>
              ko ? '공간의 울림을 정리했어요' : 'Tamed your room’s resonances'));
    }

    return TuneResultSummary(points);
  }
}

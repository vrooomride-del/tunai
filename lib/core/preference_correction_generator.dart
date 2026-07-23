import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import 'acoustic_analysis.dart' show ToneRegion;
import 'broadband_tone_analyzer.dart';
import 'factory_sound_profile.dart';
import 'preference_target.dart';
import 'tune_plan.dart';

/// Turns a perceptual [PreferenceTarget] into a small set of bounded,
/// factory-anchored correction bands — the ENGINE step where the descriptor
/// finally becomes numbers.
///
/// This is deterministic and local: the same target always produces the same
/// bands. It NEVER involves AI, and it NEVER exceeds a gentle nudge — the whole
/// point is to lean the sound toward a taste while PROTECTING the factory
/// character, not to re-voice the speaker. Every band it emits is still subject
/// to the Safety Validator downstream (via the merge step); this generator only
/// proposes.
class PreferenceCorrectionGenerator {
  const PreferenceCorrectionGenerator();

  /// The nudge magnitude. Deliberately small and well under the +3dB boost
  /// ceiling the deployment protocol accepts — a lean, not a re-voicing.
  static const double nudgeDb = 1.5;

  /// A speaker voiced for a 'gentle' operating range gets an even smaller
  /// nudge, so the factory character is protected proportionally.
  static const double _gentleScale = 0.7;

  /// Band width — reuse the broadband analyzer's octave-wide Q so preference
  /// bands behave like the tonal-balance bands they sit beside.
  static const double _q = BroadbandToneAnalyzer.correctionQ;

  /// Region centre frequencies (geometric mean of each broadband region), so a
  /// preference band shifts a whole region rather than notching a point.
  static double _centerHz(ToneRegion region) {
    final r = switch (region) {
      ToneRegion.low => BroadbandToneAnalyzer.regions[0],
      ToneRegion.mid => BroadbandToneAnalyzer.regions[1],
      ToneRegion.high => BroadbandToneAnalyzer.regions[2],
    };
    return math.sqrt(r.lowHz * r.highHz);
  }

  /// Produces the preference bands (ascending by frequency). Empty when the
  /// target asks for no change — which keeps the no-preference flow identical.
  List<TuneCorrectionBand> generate(
    PreferenceTarget target, {
    FactorySoundProfile? factory,
  }) {
    if (!target.hasAnyNudge) return const [];
    final scale =
        factory?.safeOperatingRange == 'gentle' ? _gentleScale : 1.0;
    final magnitude = nudgeDb * scale;

    final bands = <TuneCorrectionBand>[];
    for (final region in ToneRegion.values) {
      final direction =
          target.regionDirection[region] ?? PreferenceDirection.neutral;
      final gain = switch (direction) {
        PreferenceDirection.gentleLift => magnitude,
        PreferenceDirection.gentleSoften => -magnitude,
        PreferenceDirection.neutral => 0.0,
      };
      if (gain == 0.0) continue;
      bands.add(TuneCorrectionBand(
        frequencyHz: _centerHz(region),
        gainDb: gain,
        q: _q,
        evidenceReference: 'preference:${target.descriptor}:${region.name}',
        // Proposed within bounds; the Safety Validator is still the gate that
        // confirms it during the merge.
        safetyValidated: true,
        source: TuneCorrectionSource.preferenceTarget,
      ));
    }
    bands.sort((a, b) => a.frequencyHz.compareTo(b.frequencyHz));
    debugPrint('[PREFERENCE_TARGET] ${target.descriptor} → '
        '${bands.map((b) => '${b.frequencyHz.toStringAsFixed(0)}Hz/'
            '${b.gainDb.toStringAsFixed(1)}dB').toList()}');
    return bands;
  }
}

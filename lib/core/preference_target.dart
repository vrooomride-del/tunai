import 'package:flutter/foundation.dart';

import 'acoustic_analysis.dart' show ToneRegion;

/// The direction a region should be nudged for a preference — perceptual only,
/// NEVER a dB value. The engine ([PreferenceCorrectionGenerator]) turns these
/// into small, bounded gains; this layer never holds a number.
enum PreferenceDirection { neutral, gentleLift, gentleSoften }

/// A user's listening preference expressed as a TARGET DESCRIPTOR — what they
/// want the sound to lean toward, per broad region — with NO DSP numbers.
///
/// This is the Phase 7 "Preference Target Layer": it sits between the factory
/// reference and room correction. A [PreferenceTarget] carries only a
/// descriptor ('warm'/'detailed'/...) and a per-region [PreferenceDirection].
/// The actual (small, bounded, factory-anchored) gains are computed by the
/// deterministic engine and validated by the Safety Validator — never here,
/// and never by AI.
@immutable
class PreferenceTarget {
  final String descriptor;
  final Map<ToneRegion, PreferenceDirection> regionDirection;

  const PreferenceTarget({
    required this.descriptor,
    required this.regionDirection,
  });

  /// Whether this target asks for any change at all. 'natural' / unknown yield
  /// an all-neutral target → no bands → the sound is unchanged.
  bool get hasAnyNudge =>
      regionDirection.values.any((d) => d != PreferenceDirection.neutral);

  /// The Descriptor → Direction table. Deterministic and fixed — this is the
  /// product's taste vocabulary, not an AI decision. Directions are gentle by
  /// definition; magnitudes are the engine's concern.
  ///
  /// Returns null for an unknown/absent descriptor, so no preference means no
  /// preference bands (regression-preserving).
  static PreferenceTarget? forDescriptor(String? descriptor) {
    if (descriptor == null) return null;
    final directions = _table[descriptor];
    if (directions == null) return null;
    final target =
        PreferenceTarget(descriptor: descriptor, regionDirection: directions);
    return target.hasAnyNudge ? target : null;
  }

  static const Map<String, Map<ToneRegion, PreferenceDirection>> _table = {
    // Fuller low end, a touch less top — a classic "warm" lean.
    'warm': {
      ToneRegion.low: PreferenceDirection.gentleLift,
      ToneRegion.mid: PreferenceDirection.neutral,
      ToneRegion.high: PreferenceDirection.gentleSoften,
    },
    // A little more air/detail up top.
    'detailed': {
      ToneRegion.low: PreferenceDirection.neutral,
      ToneRegion.mid: PreferenceDirection.neutral,
      ToneRegion.high: PreferenceDirection.gentleLift,
    },
    // Vocals slightly forward.
    'vocal': {
      ToneRegion.low: PreferenceDirection.neutral,
      ToneRegion.mid: PreferenceDirection.gentleLift,
      ToneRegion.high: PreferenceDirection.neutral,
    },
    // Easy for long sessions — take the edge off the top.
    'comfortable': {
      ToneRegion.low: PreferenceDirection.neutral,
      ToneRegion.mid: PreferenceDirection.neutral,
      ToneRegion.high: PreferenceDirection.gentleSoften,
    },
    'relaxed': {
      ToneRegion.low: PreferenceDirection.neutral,
      ToneRegion.mid: PreferenceDirection.neutral,
      ToneRegion.high: PreferenceDirection.gentleSoften,
    },
    // 'natural' and anything else → no entry → null → no nudge.
  };

  Map<String, dynamic> toJson() => {
        'descriptor': descriptor,
        'regionDirection': {
          for (final e in regionDirection.entries) e.key.name: e.value.name,
        },
      };
}

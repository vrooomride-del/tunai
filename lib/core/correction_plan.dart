import 'package:flutter/foundation.dart';

/// A perceptual acoustic PROBLEM the measurement + intent identified.
enum AcousticProblem {
  bassBoom,
  thinLowEnd,
  boxyMidrange,
  recessedMidrange,
  harshTreble,
  dullTreble,
}

/// The perceptual GOAL for that problem.
enum CorrectionGoal {
  tighterLowEnd,
  fullerLowEnd,
  clearerMidrange,
  forwardMidrange,
  smootherTreble,
  brighterTreble,
}

/// Whose intent drives this correction — measurement evidence, or the user's
/// stated preference. Lets a later stage weigh them.
enum CorrectionPriority { measurement, userPreference, balanced }

/// HOW the correction approaches the problem — the concrete strategy, framed
/// so that the speaker's factory character is preserved rather than replaced.
///
/// This is the heart of Phase 3-3's concept fix: TUNAI does not rebuild the
/// factory sound and does not tune the room toward some external target. It
/// only removes what the ROOM adds or fills what the ROOM subtracts, leaving
/// the manufacturer's voicing intact.
enum CorrectionStrategy {
  /// The room adds buildup (e.g. bass boom near a wall) — reduce that excess.
  reduceRoomExcess,

  /// The room subtracts energy in a region — gently fill it back.
  fillRoomDip,

  /// The room is already close to the factory character — preserve it, apply
  /// minimal or no correction.
  preserveFactoryCharacter,

  /// The measurement is too unreliable to act on (low split-half agreement).
  /// TUNAI does NOT chase an uncertain reading — it holds the factory sound
  /// rather than risk "correcting" noise. A conservative, evidence-first stance.
  lowConfidenceIgnore,

  /// A room correction is applied, but the speaker's factory character is
  /// actively protected: the user's stated preference is held as SECONDARY and
  /// not allowed to push the sound away from the factory voicing on evidence
  /// that is only moderately reliable.
  protectFactoryCharacter,

  /// The correction is measurement-led; the user preference informed the
  /// direction but did not override the factory-anchored result. A label for
  /// "we listened to you, but the room + factory came first."
  userPreferenceSecondary,
}

/// A single perceptual correction intent — the bridge between "what is wrong
/// and what the user wants" and the deterministic engine that will later turn
/// it into real numbers.
///
/// CONTRACT: a [CorrectionPlan] contains NO DSP values — no frequency, gain,
/// Q, filter, crossover, or register. It describes a problem/goal in
/// perceptual terms only. [TunePlanner] and [TuneSafetyValidator] remain the
/// sole owners of every numeric value; this layer never computes one. The
/// [allowed] flag lets a policy/safety stage veto a correction before any
/// numbers exist, without this class ever knowing what those numbers are.
@immutable
class CorrectionPlan {
  final AcousticProblem problem;
  final CorrectionGoal goal;
  final CorrectionPriority priority;

  /// HOW to correct while preserving factory character (see
  /// [CorrectionStrategy]). Defaults to reducing room excess — the most
  /// common and safest framing.
  final CorrectionStrategy strategy;

  /// Whether this correction is permitted to proceed to the numeric engine.
  /// A perceptual gate only — the actual safety math still runs later in
  /// [TuneSafetyValidator], unchanged.
  final bool allowed;

  /// Perceptual context from the AI intent layer (e.g.
  /// {'soundCharacter':'warm','listeningGoal':'longListening'}). Descriptors
  /// only — NEVER a frequency/gain/Q or any numeric tuning value. Empty when
  /// no intent was available.
  final Map<String, String> intentContext;

  /// The single perceptual preference descriptor this plan resolves to
  /// (e.g. 'warm', 'natural') — the bridge to TunePlanner's EXISTING
  /// `SoundPreference` context input. Not a DSP value; TunePlanner still owns
  /// every number. Null when nothing overrides the user's picker choice.
  final String? preferenceContext;

  const CorrectionPlan({
    required this.problem,
    required this.goal,
    this.priority = CorrectionPriority.balanced,
    this.strategy = CorrectionStrategy.reduceRoomExcess,
    this.allowed = true,
    this.intentContext = const {},
    this.preferenceContext,
  });

  Map<String, dynamic> toJson() => {
        'problem': problem.name,
        'goal': goal.name,
        'priority': priority.name,
        'strategy': strategy.name,
        'allowed': allowed,
        if (intentContext.isNotEmpty) 'intentContext': intentContext,
        if (preferenceContext != null) 'preferenceContext': preferenceContext,
      };

  factory CorrectionPlan.fromJson(Map<String, dynamic> json) => CorrectionPlan(
        problem: _byName(json['problem'], AcousticProblem.values) ??
            AcousticProblem.bassBoom,
        goal: _byName(json['goal'], CorrectionGoal.values) ??
            CorrectionGoal.tighterLowEnd,
        priority: _byName(json['priority'], CorrectionPriority.values) ??
            CorrectionPriority.balanced,
        strategy: _byName(json['strategy'], CorrectionStrategy.values) ??
            CorrectionStrategy.reduceRoomExcess,
        allowed: json['allowed'] is bool ? json['allowed'] as bool : true,
        intentContext: json['intentContext'] is Map
            ? {
                for (final e in (json['intentContext'] as Map).entries)
                  if (e.value is String) e.key.toString(): e.value as String,
              }
            : const {},
        preferenceContext: json['preferenceContext'] is String
            ? json['preferenceContext'] as String
            : null,
      );

  static T? _byName<T extends Enum>(Object? raw, List<T> values) {
    if (raw is! String) return null;
    for (final v in values) {
      if (v.name == raw) return v;
    }
    return null;
  }
}

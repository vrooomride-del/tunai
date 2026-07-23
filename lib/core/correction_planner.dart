import 'acoustic_intent.dart';
import 'correction_plan.dart';
import 'factory_sound_profile.dart';
import 'listening_taste.dart';
import 'personal_optimization_context.dart';
import 'room_measurement.dart';
import 'sound_preference.dart';

/// Builds a perceptual [CorrectionPlan] from a measurement plus the user's
/// intent/taste, and resolves that plan to TunePlanner's EXISTING
/// [SoundPreference] context input.
///
/// This is the Phase 3-1 "Context Layer" between Measurement and TunePlanner:
///
///   Measurement + AcousticIntent + Taste + FactoryProfile
///        → CorrectionPlan (perceptual: problem / goal / priority / direction)
///        → SoundPreference (TunePlanner's existing, unchanged context input)
///        → TunePlanner → Safety Validator → DSP
///
/// HARD CONTRACT:
///  * Produces NO DSP value — never a frequency, gain, Q, filter, crossover,
///    delay, limiter, or register. The [CorrectionPlan] is perceptual only.
///  * Does NOT change TunePlanner's algorithm or signature. The connection is
///    made purely by deriving the `preference` argument TunePlanner already
///    accepts; TunePlanner still owns every number and Safety Validator still
///    runs unchanged.
///  * Behaviour-preserving when no intent/taste is present: [resolvePreference]
///    returns the caller's fallback (the picker choice) unchanged, so an
///    existing measurement-only flow is byte-identical to before.
class CorrectionPlanner {
  const CorrectionPlanner();

  /// Region boundary for the coarse perceptual problem read. Matches the
  /// low/mid split used elsewhere; this is a description of WHERE the dominant
  /// issue sits, not a filter frequency.
  static const double _lowRegionCeilingHz = 300;

  /// Context-driven entry point (Phase 3-4). Runs the planner from a fully
  /// built [PersonalOptimizationContext] plus the [measurement] it describes —
  /// the measurement is still required because the room ANALYSIS (which region
  /// the room added/subtracted, and by which sign) cannot be reconstructed from
  /// perceptual descriptors alone; the context supplies the factory reference,
  /// the user preference, and the listening intent.
  ///
  /// This makes the documented Runtime Flow literal:
  ///   PersonalOptimizationContext → CorrectionPlanner → CorrectionPlan.
  CorrectionPlan planFromContext({
    required RoomMeasurement measurement,
    required PersonalOptimizationContext context,
  }) {
    final (problem, goal, roomStrategy) = _dominantProblem(measurement);

    // JUDGMENT LAYER (Phase 4): the room read is only half the decision. How
    // far to act on it depends on how much the measurement can be trusted, and
    // the speaker's factory character always wins ties.
    final confidence = context.confidence;
    final hasPreference = context.userPreference != null;
    final strategy = _judge(
      roomStrategy: roomStrategy,
      confidence: confidence,
      hasPreference: hasPreference,
    );

    // The user's stated preference is applied to the tuning ONLY on a
    // trustworthy measurement. On a shaky reading it is held as SECONDARY —
    // recorded in context for the explanation, but never allowed to push the
    // sound away from the factory voicing on weak evidence. Preserves the
    // no-input flow exactly (no preference → fallback regardless of confidence).
    final applyPreference = confidence == 'stable';
    final priority = context.hasUserSignal
        ? CorrectionPriority.balanced
        : CorrectionPriority.measurement;

    final intentContext = <String, String>{
      ...context.listeningIntent,
      if (context.userPreference != null) 'preference': context.userPreference!,
      if (context.factoryReference != null) ...{
        'factoryTarget': context.factoryReference!.targetCharacter,
        'factoryIntent': context.factoryReference!.factoryIntent,
        'factoryListeningGoal': context.factoryReference!.listeningGoal,
        'safeOperatingRange': context.factoryReference!.safeOperatingRange,
      },
    };

    return CorrectionPlan(
      problem: problem,
      goal: goal,
      priority: priority,
      strategy: strategy,
      allowed: true,
      intentContext: intentContext,
      // Applied preference only on a trustworthy measurement; otherwise null so
      // resolvePreference falls back to the picker and the factory sound holds.
      preferenceContext: applyPreference ? context.userPreference : null,
    );
  }

  /// The judgment: combine the room read with measurement confidence, with
  /// factory-character preservation as the tie-breaker. Never produces a DSP
  /// value — only chooses WHY/HOW conservative to be.
  CorrectionStrategy _judge({
    required CorrectionStrategy roomStrategy,
    required String confidence,
    required bool hasPreference,
  }) {
    // Too unreliable to act on — hold the factory sound rather than chase noise.
    if (confidence == 'low') return CorrectionStrategy.lowConfidenceIgnore;
    // Room already close to factory — nothing to correct, preserve.
    if (roomStrategy == CorrectionStrategy.preserveFactoryCharacter) {
      return CorrectionStrategy.preserveFactoryCharacter;
    }
    // A real room problem, but only moderately reliable AND the user asked for
    // a character change: correct the room, but PROTECT the factory voicing —
    // the preference stays secondary (not applied to the tuning here).
    if (confidence == 'moderate' && hasPreference) {
      return CorrectionStrategy.protectFactoryCharacter;
    }
    // Trustworthy room read → act on it (reduce excess / fill dip).
    return roomStrategy;
  }

  /// Derives the plan. All inputs except [measurement] are optional; with none
  /// of them the plan still describes the measured problem, with neutral
  /// priority and no preference override.
  CorrectionPlan plan({
    required RoomMeasurement measurement,
    AcousticIntent? intent,
    ListeningTaste? taste,
    FactorySoundProfile? factory,
  }) {
    final (problem, goal, strategy) = _dominantProblem(measurement);

    // Priority reflects whether the user expressed a clear intent. Measurement
    // always matters; a confident intent raises the user's voice to balanced/
    // user-led. This only affects the CONTEXT label — never the safety math.
    final priority = switch (intent?.confidence) {
      IntentConfidence.high => CorrectionPriority.userPreference,
      IntentConfidence.medium => CorrectionPriority.balanced,
      _ => CorrectionPriority.measurement,
    };

    final intentContext = <String, String>{
      if (intent?.soundCharacter != null)
        'soundCharacter': intent!.soundCharacter!.name,
      if (intent?.bassPreference != null)
        'bassPreference': intent!.bassPreference!.name,
      if (intent?.vocalPreference != null)
        'vocalPreference': intent!.vocalPreference!.name,
      if (intent?.listeningGoal != null)
        'listeningGoal': intent!.listeningGoal!.name,
      if (intent?.listeningFatigue != null)
        'listeningFatigue': intent!.listeningFatigue!,
      if (taste != null) 'taste': taste.name,
      // Factory voicing INTENT — the target direction every correction must
      // re-interpret rather than flatten. All perceptual descriptors, never a
      // number. This is what keeps TUNAI a Factory-Sound-Intent engine, not a
      // room EQ.
      if (factory != null) ...{
        'factoryTarget': factory.targetCharacter,
        'factoryIntent': factory.factoryIntent,
        'factoryListeningGoal': factory.listeningGoal,
        'safeOperatingRange': factory.safeOperatingRange,
      },
    };

    return CorrectionPlan(
      problem: problem,
      goal: goal,
      priority: priority,
      strategy: strategy,
      allowed: true,
      intentContext: intentContext,
      // Factory is deliberately NOT a factor in preference resolution: the
      // user's picker choice already IS their preference, and it defaults to
      // the same neutral character the factory targets. Letting the factory
      // feed this would let it override the picker, changing behaviour. The
      // factory's target direction lives in intentContext (above) as context
      // a later stage / the AI explanation can preserve — never as a silent
      // preference override.
      preferenceContext: _preferenceDescriptor(intent, taste),
    );
  }

  /// Resolves the perceptual direction to one of TunePlanner's EXISTING
  /// [SoundPreference] values — the only channel through which context reaches
  /// the numeric engine, and one TunePlanner already supported before Phase 3.
  ///
  /// Returns [fallback] (the user's picker choice) whenever the plan carries
  /// no preference override, guaranteeing identical behaviour for the existing
  /// intent-free flow.
  SoundPreference resolvePreference(
    CorrectionPlan plan, {
    required SoundPreference fallback,
  }) {
    final descriptor = plan.preferenceContext;
    if (descriptor == null) return fallback;
    return switch (descriptor) {
      'warm' => SoundPreference.warm,
      'detailed' => SoundPreference.clear,
      'relaxed' => SoundPreference.open,
      'vocal' => SoundPreference.vocal,
      'natural' => SoundPreference.balanced,
      // 'energetic', 'deepBass' and anything unmapped intentionally fall back:
      // there is no existing SoundPreference that means them WITHOUT inventing
      // new EQ math, which is forbidden. They remain context only.
      _ => fallback,
    };
  }

  /// Maps the strongest intent/taste signal to a perceptual preference
  /// descriptor, or null when nothing clearly overrides the picker.
  /// Intent (an explicit request) outranks a stored taste.
  String? _preferenceDescriptor(AcousticIntent? intent, ListeningTaste? taste) {
    switch (intent?.soundCharacter) {
      case SoundCharacter.warm:
        return 'warm';
      case SoundCharacter.detailed:
        return 'detailed';
      case SoundCharacter.relaxed:
        return 'relaxed';
      case SoundCharacter.natural:
        return 'natural';
      case SoundCharacter.energetic:
      case null:
        break;
    }
    // Vocal-forward intent, if the character did not already decide it.
    if (intent?.vocalPreference == VocalPreference.forward) return 'vocal';
    switch (taste) {
      case ListeningTaste.warm:
        return 'warm';
      case ListeningTaste.detailed:
        return 'detailed';
      case ListeningTaste.natural:
        return 'natural';
      case ListeningTaste.deepBass:
      case null:
        return null; // deepBass has no existing preference; context only.
    }
  }

  /// Builds the full [PersonalOptimizationContext] — the four independent
  /// inputs kept separate (factory reference, room condition, user preference,
  /// listening intent). Perceptual only.
  ///
  /// This is the explicit "personalise, don't rebuild" picture: the factory
  /// reference is carried to be PRESERVED, the room condition is what gets
  /// corrected, and the user's preference/intent stay as their own voice —
  /// none overriding another.
  PersonalOptimizationContext buildContext({
    required RoomMeasurement measurement,
    AcousticIntent? intent,
    ListeningTaste? taste,
    FactorySoundProfile? factory,
    String? placement,
  }) {
    final (problem, _, _) = _dominantProblem(measurement);
    return PersonalOptimizationContext(
      factoryReference: factory,
      roomCondition: _roomConditionDescriptor(measurement, problem),
      userPreference: _preferenceDescriptor(intent, taste),
      // REAL measured trust signals — never guessed. `consistencyMetric` is the
      // capture's own split-half agreement (see CaptureAnalysis.agreement);
      // `quality` is its recorded classification.
      confidence: confidenceBucket(measurement.consistencyMetric),
      measurementQuality: measurement.quality.name,
      listeningIntent: {
        if (intent?.soundCharacter != null)
          'soundCharacter': intent!.soundCharacter!.name,
        if (intent?.listeningGoal != null)
          'listeningGoal': intent!.listeningGoal!.name,
        if (intent?.listeningFatigue != null)
          'listeningFatigue': intent!.listeningFatigue!,
        // Placement is a user-chosen descriptor (desk/near_wall/…), context
        // only — never a measured value. Lets the explanation name the setting.
        if (placement != null) 'placement': placement,
      },
    );
  }

  /// Buckets a 0..1 split-half agreement into a trust label. Same thresholds
  /// the AI digest uses, so "stable/moderate/low" means one thing app-wide.
  static String confidenceBucket(double agreement) => agreement >= 0.75
      ? 'stable'
      : agreement >= 0.5
          ? 'moderate'
          : 'low';

  String _roomConditionDescriptor(
      RoomMeasurement measurement, AcousticProblem problem) {
    if (measurement.peaks.isEmpty) return 'balanced';
    return problem.name;
  }

  /// Coarse perceptual read of the dominant measured problem — WHERE the
  /// biggest deviation sits, the goal that addresses it, and the STRATEGY that
  /// does so while preserving factory character. Uses only the already-detected
  /// peaks; produces no numbers.
  (AcousticProblem, CorrectionGoal, CorrectionStrategy) _dominantProblem(
      RoomMeasurement measurement) {
    if (measurement.peaks.isEmpty) {
      // Nothing stood out — the room is already close to the factory sound, so
      // the strategy is to PRESERVE it, not to invent a correction.
      return (
        AcousticProblem.bassBoom,
        CorrectionGoal.tighterLowEnd,
        CorrectionStrategy.preserveFactoryCharacter,
      );
    }
    // Deepest cut (most negative gain) is the dominant issue. A negative gain
    // means the room ADDS energy there → reduce that room excess; a positive
    // one means the room subtracts → fill the room dip. Either way the factory
    // voicing is the baseline being restored, never replaced.
    var dominant = measurement.peaks.first;
    for (final p in measurement.peaks) {
      if (p.gain < dominant.gain) dominant = p;
    }
    final strategy = dominant.gain <= 0
        ? CorrectionStrategy.reduceRoomExcess
        : CorrectionStrategy.fillRoomDip;
    if (dominant.frequency < _lowRegionCeilingHz) {
      return (AcousticProblem.bassBoom, CorrectionGoal.tighterLowEnd, strategy);
    }
    return (
      AcousticProblem.boxyMidrange,
      CorrectionGoal.clearerMidrange,
      strategy,
    );
  }
}

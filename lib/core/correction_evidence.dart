import 'package:flutter/foundation.dart';

import 'correction_plan.dart';
import 'personal_optimization_context.dart';

/// A structured, traceable record of WHY CorrectionPlanner chose the correction
/// it did — the judgment's evidence, not its numbers.
///
/// This is the audit trail for "TUNAI decided X because Y". It is produced
/// deterministically from the [PersonalOptimizationContext] and the resulting
/// [CorrectionPlan], so the same inputs always yield the same evidence. It
/// enables, without any recomputation:
///   1. the LISTEN "why it sounds this way" explanation,
///   2. richer AI analysis input,
///   3. a future Pro report,
///   4. future learning data.
///
/// PERCEPTUAL ONLY — factory character, room condition, confidence, strategy,
/// and a rationale phrase. It has no frequency, gain, Q, filter, crossover,
/// delay, limiter, or register field, and never will: the numeric work stays
/// entirely in TunePlanner / Safety Validator.
@immutable
class CorrectionEvidence {
  /// The factory voicing that was being PRESERVED (e.g. 'natural_balanced'),
  /// or null when no factory reference was available.
  final String? factoryReference;

  /// What the room was doing, perceptually (e.g. 'bassBoom', 'balanced').
  final String roomCondition;

  /// How much the measurement could be trusted — 'stable' / 'moderate' / 'low'.
  final String measurementConfidence;

  /// The chosen approach (see [CorrectionStrategy]).
  final CorrectionStrategy strategy;

  /// A deterministic, machine-stable rationale code summarising the decision
  /// (e.g. 'measurement_low_confidence_preserved_factory'). Not consumer copy —
  /// that is generated separately by SoundExplanation.
  final String reason;

  const CorrectionEvidence({
    required this.factoryReference,
    required this.roomCondition,
    required this.measurementConfidence,
    required this.strategy,
    required this.reason,
  });

  /// Derives the evidence from the context + the plan the planner produced.
  /// Pure and deterministic.
  factory CorrectionEvidence.from({
    required PersonalOptimizationContext context,
    required CorrectionPlan plan,
  }) {
    return CorrectionEvidence(
      factoryReference: context.factoryReference?.targetCharacter,
      roomCondition: context.roomCondition,
      measurementConfidence: context.confidence,
      strategy: plan.strategy,
      reason: _reasonFor(plan.strategy),
    );
  }

  /// One deterministic rationale code per strategy — a stable key, safe to log,
  /// store, and later learn from.
  static String _reasonFor(CorrectionStrategy strategy) => switch (strategy) {
        CorrectionStrategy.lowConfidenceIgnore =>
          'measurement_low_confidence_preserved_factory',
        CorrectionStrategy.preserveFactoryCharacter =>
          'room_balanced_preserved_factory',
        CorrectionStrategy.protectFactoryCharacter =>
          'moderate_confidence_protected_factory',
        CorrectionStrategy.reduceRoomExcess => 'reduced_room_excess',
        CorrectionStrategy.fillRoomDip => 'filled_room_dip',
        CorrectionStrategy.userPreferenceSecondary =>
          'user_preference_kept_secondary',
      };

  Map<String, dynamic> toJson() => {
        if (factoryReference != null) 'factoryReference': factoryReference,
        'roomCondition': roomCondition,
        'measurementConfidence': measurementConfidence,
        'strategy': strategy.name,
        'reason': reason,
      };

  factory CorrectionEvidence.fromJson(Map<String, dynamic> json) {
    CorrectionStrategy strategy = CorrectionStrategy.preserveFactoryCharacter;
    final rawStrategy = json['strategy'];
    if (rawStrategy is String) {
      for (final s in CorrectionStrategy.values) {
        if (s.name == rawStrategy) {
          strategy = s;
          break;
        }
      }
    }
    return CorrectionEvidence(
      factoryReference: json['factoryReference'] as String?,
      roomCondition: json['roomCondition'] as String? ?? 'balanced',
      measurementConfidence: json['measurementConfidence'] as String? ?? 'stable',
      strategy: strategy,
      reason: json['reason'] as String? ?? _reasonFor(strategy),
    );
  }
}

import 'package:flutter/foundation.dart';

import 'tune_plan.dart';
import 'tune_safety_validator.dart';

/// Merges preference-target bands into a room-corrected [TunePlan], enforcing
/// the priority: Safety > Room correction > Factory protection > Preference.
///
/// The merge is arbitrated by the EXISTING [TuneSafetyValidator], unchanged:
/// room bands are offered FIRST and preference bands SECOND, and the validator
/// approves greedily in order, rejecting anything that would violate spacing,
/// the aggregate cut limit, or the deployable band budget. That ordering is
/// exactly the priority above — room bands always win the budget, and
/// preference is dropped when it cannot safely fit ("over budget = preference
/// removed"). TunePlanner and the validator are untouched; this only composes
/// them.
class PreferencePlanMerger {
  final TuneSafetyValidator validator;

  const PreferencePlanMerger({this.validator = const TuneSafetyValidator()});

  /// Returns [roomPlan] UNCHANGED when there are no preference bands — the
  /// no-preference flow is therefore byte-identical to before Phase 7. When
  /// preference bands exist, returns a re-validated plan with room bands
  /// prioritised and preference fitted only within the remaining safe budget.
  TunePlan merge(
    TunePlan roomPlan,
    List<TuneCorrectionBand> preferenceBands,
  ) {
    if (preferenceBands.isEmpty) return roomPlan;

    // Room first (higher priority), preference second. The validator's greedy,
    // order-preserving approval turns this ordering into the priority rule.
    final validated =
        validator.validate([...roomPlan.bands, ...preferenceBands]);
    final merged = validated.rebuild(roomPlan);
    debugPrint('[PREFERENCE_MERGE] room=${roomPlan.bands.length} '
        'preference=${preferenceBands.length} '
        '→ approved=${merged.bands.length} '
        '(preferenceApplied='
        '${merged.bands.any((b) => b.source == TuneCorrectionSource.preferenceTarget)})');
    return merged;
  }
}

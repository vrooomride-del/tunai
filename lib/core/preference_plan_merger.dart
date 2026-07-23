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

  /// Returns a plan that is always DEPLOYABLE — no more than the DSP's real
  /// band capacity ([DspCapability.maxDeployableBands], 3) — with room
  /// correction prioritised and preference fitted only in the remaining budget.
  ///
  /// Fast path: with no preference bands AND a room plan already within the
  /// deployable capacity, [roomPlan] is returned UNCHANGED (identical object),
  /// so the intent-free ≤3-band flow stays byte-identical to before.
  ///
  /// When the combined bands EXCEED the deployable capacity — whether from
  /// preference OR from a room plan that TunePlanner produced with more than
  /// the DSP can deploy (TunePlanner's own `maximumBands` is 4, but only 3
  /// deploy) — the shared [TuneSafetyValidator] trims to capacity. Because it
  /// approves greedily in order and the bands are offered room-first,
  /// preference-last, the priority is Room correction > Factory > Preference:
  /// preference is dropped first, and only then, if still over budget, the
  /// lowest-priority room band. This is the ONLY change needed to stop the
  /// `tooManyBands` → blocked → "can't enter comparison" failure, and it
  /// reuses the existing validator without altering TunePlanner, the Safety
  /// Validator's policy, or the DSP protocol.
  TunePlan merge(
    TunePlan roomPlan,
    List<TuneCorrectionBand> preferenceBands,
  ) {
    final maxDeployable = validator.capability.maxDeployableBands;
    if (preferenceBands.isEmpty &&
        roomPlan.bands.length <= maxDeployable) {
      return roomPlan; // identical fast-path — already deployable, no change
    }

    // Room first (higher priority), preference second. The validator's greedy,
    // order-preserving approval turns this ordering into the priority rule and
    // caps the result at the deployable band capacity.
    final validated =
        validator.validate([...roomPlan.bands, ...preferenceBands]);
    final merged = validated.rebuild(roomPlan);
    debugPrint('[PREFERENCE_MERGE] room=${roomPlan.bands.length} '
        'preference=${preferenceBands.length} maxDeployable=$maxDeployable '
        '→ approved=${merged.bands.length} '
        '(preferenceApplied='
        '${merged.bands.any((b) => b.source == TuneCorrectionSource.preferenceTarget)})');
    return merged;
  }
}

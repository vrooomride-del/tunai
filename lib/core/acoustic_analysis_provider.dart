import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'acoustic_analysis.dart';
import 'acoustic_analysis_service.dart';
import 'consumer_sound_profile.dart';
import 'install_location.dart';
import 'tune_plan.dart';

/// Runs the Acoustic Intelligence Layer for the currently active profile's
/// deployed Tune, and caches the result.
///
/// Additive and non-blocking by construction: it depends on the already-saved
/// [TunePlan] and the active profile, both of which exist before this ever
/// runs. Nothing in the Tune-creation flow awaits it. The UI watches this and
/// shows the AI card only when it resolves to a non-null [AcousticAnalysis].
///
/// Returns null (card hidden) when: there is no active profile, no matching
/// deployed plan, the plan has no bands to describe, or the AI call fails for
/// any reason. Every one of those is a legitimate "nothing to show", never an
/// error surfaced to the user.
final acousticAnalysisProvider = FutureProvider<AcousticAnalysis?>((ref) async {
  final profile = ref.watch(activeConsumerProfileProvider);
  if (profile == null) return null;

  final plan = await TunePlanStore.load();
  if (plan == null || plan.id != profile.tunePlanId) return null;

  final placement = ref.watch(installLocationProvider)?.promptKey;

  final digest = AcousticAnalysisDigest.of(
    plan: plan,
    // The plan carries the capture's real split-half repeatability, stored
    // at Tune-creation time — no new measurement, no fabricated confidence.
    captureAgreement: plan.measurementConsistency,
    placement: placement,
  );
  if (digest == null) return null;

  return AcousticAnalysisService.analyze(digest);
});

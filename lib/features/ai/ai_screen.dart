import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../ble/ble_controller.dart';
import '../measurement/measurement_controller.dart' show measurementProvider;
import '../../core/consumer_dsp_deployment.dart';
import '../../core/dsp_state_synchronization.dart';
import '../../core/room_scan_result.dart';
import '../../core/consumer_sound_profile.dart';
import '../../core/room_measurement.dart';
import '../../core/audio_analyzer.dart' show ResonancePeak;
import '../../core/speaker_check_gate.dart';
import '../../core/speaker_profile.dart';
import '../../core/speaker_state_verification.dart';
import '../../core/speaker_verification_session.dart';
import '../../core/acoustic_profile.dart';
import '../../core/correction_evidence.dart';
import '../../core/correction_planner.dart';
import '../../core/factory_sound_profile.dart';
import '../../core/install_location.dart';
import '../../core/personal_optimization_context.dart';
import '../../core/preference_correction_generator.dart';
import '../../core/preference_plan_merger.dart';
import '../../core/preference_target.dart';
import '../../core/sound_preference.dart';
import '../../core/tune_session.dart';
import '../../core/sound_score_calculator.dart';
import '../../core/spectrum_snapshot.dart';
import '../../core/tune_availability.dart';
import '../../core/tune_deployment_plan.dart';
import '../../core/tune_outcome_history.dart';
import '../../core/tune_plan.dart';
import '../../shared/acoustic_timeline.dart';
import '../../shared/consumer_response_chart.dart';
import '../fine_tune/fine_tune_screen.dart';

/// What tapping the TUNE apply/check button should do, resolved from the LIVE
/// speaker-check status and BLE connection state. The button is ALWAYS
/// actionable — this never resolves to "do nothing".
enum SpeakerButtonAction {
  /// Ready — continue to the apply / comparison-listening flow.
  apply,

  /// Bluetooth is off — route to CONNECT and surface Bluetooth guidance.
  bluetoothOff,

  /// No speaker connected — route to CONNECT to connect one.
  connect,

  /// Connected but not verified (identity/sound state) — route to CONNECT to
  /// re-verify / reconnect.
  reconnect,

  /// Everything else (connection, identity, DSP readiness) checks out, but
  /// the user's audio Speaker Check confirmation ("did you hear it from your
  /// speaker") is missing or no longer matches this connection — route back
  /// to ROOM's Speaker Check rather than allowing Apply on an unconfirmed
  /// audio path.
  confirmSpeaker,
}

/// Pure routing decision for the TUNE speaker button. Kept side-effect free so
/// it is exhaustively testable. Never returns a null/no-op — the button is
/// never a dead control.
SpeakerButtonAction resolveSpeakerButtonAction({
  required SpeakerCheckStatus status,
  required BleConnectionState connection,
  required bool audioConfirmed,
}) {
  if (status == SpeakerCheckStatus.readyToApply) {
    return audioConfirmed
        ? SpeakerButtonAction.apply
        : SpeakerButtonAction.confirmSpeaker;
  }
  // Bluetooth off takes priority over "not connected" so the user gets the
  // correct guidance.
  if (connection == BleConnectionState.bluetoothOff) {
    return SpeakerButtonAction.bluetoothOff;
  }
  if (status == SpeakerCheckStatus.speakerNotConnected) {
    return SpeakerButtonAction.connect;
  }
  // identityUnconfirmed / speakerMismatch / soundStateNotVerified /
  // originalValuesUnavailable → a speaker is connected but not verified.
  return SpeakerButtonAction.reconnect;
}

/// The user's chosen sound character for the *next* Tune to be created.
/// Session-scoped (resets to [SoundPreference.balanced] on app launch) —
/// once a Tune is created, the choice is captured on the resulting
/// [ConsumerSoundProfile.preference] for persistence, not here.
final soundPreferenceProvider =
    StateProvider<SoundPreference>((ref) => SoundPreference.balanced);

/// The Single Source of Truth for "is there a real TunePlan right now, and
/// what does it actually contain" — [TunePlanStore] holds exactly ONE
/// "current" plan (one SharedPreferences key), so every screen that needs
/// to know whether Apply is real must read the SAME fresh value, not a
/// proxy like a profile's cached `resultCards`. Callers that write a new
/// plan (`_createTune` here, Fine Tune's save) MUST `ref.invalidate` this
/// provider immediately after `TunePlanStore.save()` so stale reads can
/// never linger.
final currentTunePlanProvider =
    FutureProvider<TunePlan?>((ref) => TunePlanStore.load());

/// TUNE 탭 — Consumer Your Sound 6-state flow.
/// No DSP, no EQ, no PEQ, no frequency data exposed.
class AiScreen extends ConsumerStatefulWidget {
  final VoidCallback onApplied;
  final void Function(int)? onGoTo;
  const AiScreen({super.key, required this.onApplied, this.onGoTo});

  @override
  ConsumerState<AiScreen> createState() => _AiScreenState();
}

class _AiScreenState extends ConsumerState<AiScreen> {
  bool _creating = false;
  String? _createError;

  bool get _isKo => Localizations.localeOf(context).languageCode == 'ko';

  void _resetApplyPhase() {
    ref.read(consumerApplyPhaseProvider.notifier).state =
        ConsumerApplyPhase.idle;
  }

  /// Shows a short, plain-language error so a failed/aborted Apply attempt
  /// is never silent — every early-return path below that used to just
  /// `return` now goes through here first.
  void _showApplyError(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message), duration: const Duration(seconds: 3)),
      );
    }
  }

  Future<void> _applyTune() async {
    final ko = _isKo;
    final speakerCheck = ref.read(speakerCheckResultProvider);
    final snapshot = ref.read(dspStateSnapshotProvider);
    final profile = ref.read(selectedConsumerProfileProvider);
    if (!speakerCheck.readyToApply || snapshot == null || profile == null) {
      _showApplyError(ko
          ? '스피커 상태를 다시 확인해 주세요.'
          : 'Please check your speaker connection again.');
      return;
    }

    final tunePlan = await TunePlanStore.load();
    if (!mounted) return;
    if (tunePlan == null) {
      _showApplyError(ko
          ? '적용할 사운드를 찾을 수 없습니다. 나만의 사운드를 다시 만들어 주세요.'
          : 'No sound to apply. Please create Your Sound again.');
      return;
    }
    if (tunePlan.bands.isEmpty) {
      // A Tune with zero bands means no real correction was found for this
      // room — applying it would be a no-op DSP write, so block it with an
      // honest explanation instead of silently "succeeding" at nothing.
      _showApplyError(ko
          ? '이 공간에서는 적용할 조정 내용이 없습니다. 공간 분석을 다시 진행해 주세요.'
          : "There's no adjustment to apply for this space. Please redo Space Analysis.");
      return;
    }

    final expectedId = speakerCheck.confirmedSpeakerId!;

    final originalValues = <TuneDeploymentOriginalValues>[];
    for (var i = 0; i < tunePlan.bands.length; i++) {
      final state = snapshot.stateFor(
        DspPeqStateRequest(
          channel: ConsumerDspDeploymentExecutor.confirmedTunePlanChannel,
          bandId: i,
        ),
      );
      if (state == null) {
        _showApplyError(ko
            ? '스피커 상태를 확인하지 못했습니다. 다시 시도해 주세요.'
            : "Couldn't verify your speaker's state. Please try again.");
        return;
      }
      if (!mounted) return;
      originalValues.add(TuneDeploymentOriginalValues(
        frequencyHz: state.frequencyHz,
        gainDb: state.gainDb,
        q: state.q,
        enable: state.enabled,
      ));
    }

    final plans = TuneDeploymentPlan.fromTunePlan(
      tunePlan,
      channel: ConsumerDspDeploymentExecutor.confirmedTunePlanChannel,
      originalValues: originalValues,
    );

    ref.read(consumerApplyPhaseProvider.notifier).state =
        ConsumerApplyPhase.applying;

    final service = ref.read(consumerBleServiceProvider);
    final result = await ConsumerDspDeploymentExecutor(
      transport: ConsumerBleDspTransport(service),
    ).execute(
      plans: plans,
      expectedDeviceIdentifier: expectedId,
      explicitlyConfirmed: true,
    );

    if (!mounted) return;

    final recordResult = switch (result.outcome) {
      ConsumerDspDeploymentOutcome.applied =>
        ConsumerDspDeploymentRecordResult.applied,
      ConsumerDspDeploymentOutcome.restored =>
        ConsumerDspDeploymentRecordResult.restored,
      ConsumerDspDeploymentOutcome.failed =>
        ConsumerDspDeploymentRecordResult.failed,
      ConsumerDspDeploymentOutcome.blocked =>
        ConsumerDspDeploymentRecordResult.blocked,
    };

    await ref.read(consumerSoundProfileProvider.notifier).recordDspDeployment(
          profile.id,
          ConsumerDspDeploymentRecord(
            tunePlanId: tunePlan.id,
            deviceIdentifier: expectedId,
            attemptedAt: DateTime.now(),
            bandCount: plans.length,
            result: recordResult,
            dspApplied: result.dspApplied,
            failureCategory: result.failure?.name,
          ),
        );

    if (!mounted) return;

    ref.read(consumerApplyPhaseProvider.notifier).state =
        switch (result.outcome) {
      ConsumerDspDeploymentOutcome.applied => ConsumerApplyPhase.idle,
      ConsumerDspDeploymentOutcome.restored => ConsumerApplyPhase.restored,
      ConsumerDspDeploymentOutcome.failed => ConsumerApplyPhase.failed,
      ConsumerDspDeploymentOutcome.blocked => ConsumerApplyPhase.idle,
    };
  }

  /// Handler for the TUNE apply/check button. Always active — on every tap it
  /// re-reads the LIVE speaker-check and BLE state (refreshing any stale
  /// derivation) and routes accordingly, so the button is never a dead control.
  /// Consumer policy: no hardware readback protocol exists, so a connected &
  /// identity-validated speaker's pre-apply state is treated as the Flat
  /// baseline (gain 0). We synthesize the required DspStateSnapshot for the
  /// connected device from the active TunePlan (same frequency/Q, gain 0, all
  /// bands enabled) so the existing speaker verification passes and the rollback
  /// baseline is flat. No device read, no BLE/protocol/executor change.
  Future<void> _seedFlatBaselineSnapshot() async {
    if (ref.read(dspStateSnapshotProvider) != null) return;
    final ble = ref.read(bleProvider);
    final service = ref.read(consumerBleServiceProvider);
    final deviceId = ble.selectedDeviceIdentifier;
    if (ble.connection != BleConnectionState.connected ||
        !service.supportedIdentityValidated ||
        deviceId == null ||
        deviceId.isEmpty ||
        service.validatedDeviceIdentifier != deviceId) {
      return; // Not truly ready — let the existing gate route the user.
    }
    final tunePlan = await TunePlanStore.load();
    if (tunePlan == null) return;
    const channel = ConsumerDspDeploymentExecutor.confirmedTunePlanChannel;
    final bandCount = tunePlan.bands.length < 3 ? 3 : tunePlan.bands.length;
    final states = <DspPeqState>[
      for (var bandId = 0; bandId < bandCount; bandId++)
        DspPeqState(
          channel: channel,
          bandId: bandId,
          frequencyHz: bandId < tunePlan.bands.length
              ? tunePlan.bands[bandId].frequencyHz.round()
              : 1000,
          gainDb: 0.0,
          q: bandId < tunePlan.bands.length ? tunePlan.bands[bandId].q : 1.0,
          enabled: true,
        ),
    ];
    ref.read(dspStateSnapshotProvider.notifier).state = DspStateSnapshot(
      deviceIdentifier: deviceId,
      capturedAt: DateTime.now(),
      peqStates: states,
    );
  }

  Future<void> _onSpeakerButtonPressed() async {
    await _seedFlatBaselineSnapshot();
    final check = ref.read(speakerCheckResultProvider);
    final ble = ref.read(bleProvider);
    final audioConfirmed = ref.read(audioSpeakerConfirmedProvider);
    final action = resolveSpeakerButtonAction(
      status: check.status,
      connection: ble.connection,
      audioConfirmed: audioConfirmed,
    );
    final ko = _isKo;
    switch (action) {
      case SpeakerButtonAction.apply:
        await _applyTune();
      case SpeakerButtonAction.bluetoothOff:
        _guideToConnect(ko
            ? '블루투스를 켜고 스피커를 연결해 주세요.'
            : 'Turn on Bluetooth and connect your speaker.');
      case SpeakerButtonAction.connect:
        _guideToConnect(
            ko ? '스피커를 먼저 연결해 주세요.' : 'Please connect your speaker first.');
      case SpeakerButtonAction.reconnect:
        _guideToConnect(ko
            ? '스피커를 다시 연결해 확인해 주세요.'
            : 'Reconnect your speaker to verify it.');
      case SpeakerButtonAction.confirmSpeaker:
        final stale = ref.read(audioSpeakerConfirmationStaleProvider);
        _guideToSpeakerCheck(stale
            ? (ko
                ? '스피커 연결이 변경되었습니다. 확인음을 다시 재생해 주세요.'
                : 'Your speaker connection has changed. Please play the '
                    'confirmation tone again.')
            : (ko
                ? '먼저 스피커 확인을 완료해 주세요.'
                : 'Please complete the speaker check first.'));
    }
  }

  /// Opens Fine Tune as a pushed screen (not a tab) — a pure rule-based
  /// refinement on top of [profile]'s already-safety-checked Tune. Does not
  /// touch DSP Apply/BLE/Safety Validator/AI Orchestrator; it only produces
  /// a new candidate profile via the same TunePlanner path _createTune uses.
  Future<void> _openFineTune(
      ConsumerSoundProfile profile, RoomScanResult scan) async {
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => FineTuneScreen(baseProfile: profile, scan: scan),
    ));
  }

  /// "재측정" — resets the (session-scoped) measurement state and routes to
  /// the ROOM tab, landing directly on the ready-to-scan screen rather than
  /// the stale result view for the OLD measurement.
  void _reMeasure() {
    ref.read(measurementProvider.notifier).reset();
    widget.onGoTo?.call(1);
  }

  /// "완료" for a profile that needed no real correction (empty TunePlan) —
  /// marks it reviewed (see markReviewedWithoutCorrection's doc) WITHOUT
  /// ever claiming it was applied/active, since nothing was written to the
  /// speaker. This is what lets the Flow move on instead of being stuck
  /// showing the same "already balanced" screen forever.
  Future<void> _completeWithoutCorrection(String profileId) async {
    await ref
        .read(consumerSoundProfileProvider.notifier)
        .markReviewedWithoutCorrection(profileId);
  }

  /// Shows a short guidance message and navigates to the CONNECT tab (index 0).
  void _guideToConnect(String message) {
    if (mounted && message.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message), duration: const Duration(seconds: 3)),
      );
    }
    widget.onGoTo?.call(0);
  }

  /// Shows a short guidance message and navigates to the ROOM tab (index 1),
  /// where the Speaker Check confirmation tone lives — used when everything
  /// else about the connection checks out but the audio confirmation is
  /// missing or stale (see speaker_verification_session.dart).
  void _guideToSpeakerCheck(String message) {
    if (mounted && message.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message), duration: const Duration(seconds: 3)),
      );
    }
    widget.onGoTo?.call(1);
  }

  Future<void> _createTune(RoomScanResult scan) async {
    if (_creating) return;
    setState(() {
      _creating = true;
      _createError = null;
    });
    TunePlan? plan;
    try {
      if (!scan.validatedMeasurement || scan.measurementId == null) {
        throw StateError('A validated Room Analysis is required.');
      }
      final measurement = await RoomMeasurementStore.load();
      if (measurement == null || measurement.id != scan.measurementId) {
        throw StateError(
            'The validated Room Analysis measurement is unavailable.');
      }
      final pickerPreference = ref.read(soundPreferenceProvider);

      // "Before" is computed from the real measured curve only, so it never
      // depends on which plan (AI or rule-based) ends up selected below.
      final beforeScore =
          SoundScoreCalculator.compute(measurement.frequencyBins);

      // Phase 3-4 Runtime Flow — the documented pipeline, made literal:
      //   Measurement + Factory + Preference + Intent
      //     → PersonalOptimizationContext   (WHY: the four inputs, separate)
      //     → CorrectionPlan                (perceptual direction, no numbers)
      //     → SoundPreference               (TunePlanner's EXISTING input)
      //     → TunePlanner → Safety Validator → DSP   (all UNCHANGED)
      //
      // Nothing here changes TunePlanner's algorithm or Safety Validator — the
      // context only chooses which already-supported preference the engine runs
      // with. With no stored taste/intent (there is no intent-input UI yet),
      // `userPreference` is null → `resolvePreference` returns the picker choice
      // unchanged → this flow stays byte-identical to before.
      const planner = CorrectionPlanner();
      final storedProfile = await AcousticProfileStore.load();
      final optimizationContext = planner.buildContext(
        measurement: measurement,
        intent: storedProfile?.intent,
        taste: storedProfile?.listeningTaste,
        factory: FactorySoundProfileRegistry.consumerReference(),
        placement: ref.read(installLocationProvider)?.promptKey,
      );
      final correctionPlan = planner.planFromContext(
        measurement: measurement,
        context: optimizationContext,
      );
      final preference =
          planner.resolvePreference(correctionPlan, fallback: pickerPreference);
      // Structured judgment evidence (Phase 5) — WHY this correction was
      // chosen, traceable and deterministic. Perceptual only; logged now and
      // re-derivable anytime from the stored context + regenerated plan.
      final evidence = CorrectionEvidence.from(
          context: optimizationContext, plan: correctionPlan);
      debugPrint('[CORRECTION_PLAN] problem=${correctionPlan.problem.name} '
          'goal=${correctionPlan.goal.name} strategy=${correctionPlan.strategy.name} '
          'priority=${correctionPlan.priority.name} '
          'roomCondition=${optimizationContext.roomCondition} '
          'confidence=${optimizationContext.confidence} '
          'reason=${evidence.reason} '
          'preferenceContext=${correctionPlan.preferenceContext} '
          '→ preference=${preference.name} (picker=${pickerPreference.name})');

      // Bands come ONLY from the deterministic engine. The AI never generates
      // or influences any DSP band; CorrectionPlan only selects the perceptual
      // preference context, which TunePlanner already accepted before Phase 3.
      // TunePlanner owns every number and Safety Validator runs unchanged.
      final roomPlan = const TunePlanner(now: DateTime.now)
          .generate(measurement, preference: preference);

      // Phase 7 — Preference Target Layer. The user's stated taste becomes a
      // small, bounded, factory-anchored tonal NUDGE (measurement-independent,
      // engine-computed, never AI), merged in AFTER room correction. Priority
      // is Safety > Room > Factory > Preference, enforced by the shared Safety
      // Validator inside the merge. With NO stored preference this produces no
      // bands and the merge returns the room plan UNCHANGED — so the intent-free
      // flow stays byte-identical to before. `userPreference` is measurement-
      // independent (unlike the confidence-gated room-correction preference),
      // so taste can safely shape tone even on a neutral room.
      final preferenceTarget =
          PreferenceTarget.forDescriptor(optimizationContext.userPreference);
      final preferenceBands = preferenceTarget == null
          ? const <TuneCorrectionBand>[]
          : const PreferenceCorrectionGenerator().generate(
              preferenceTarget,
              factory: optimizationContext.factoryReference,
            );
      plan = const PreferencePlanMerger().merge(roomPlan, preferenceBands);
      const usedAi = false;
      await TunePlanStore.save(plan);
      // Remember WHY this Tune was made — perceptual reasons only, keyed by the
      // plan id (see OptimizationContextStore). Never a DSP value; best-effort,
      // so a storage hiccup can never fail Tune creation.
      try {
        await OptimizationContextStore.save(plan.id, optimizationContext);
      } catch (error) {
        debugPrint('[OPT_CONTEXT] save skipped (non-fatal): $error');
      }
      // Record the full traceable session (Phase 6): what/why/applied-status,
      // perceptual only. TuneSessionStore is best-effort by contract — it can
      // never throw into this flow — but guard here too for defense in depth.
      try {
        await TuneSessionStore.save(TuneSession(
          tuneId: plan.id,
          timestamp: DateTime.now(),
          factoryReference: FactorySoundProfileRegistry.consumerReference(),
          contextSummary: optimizationContext,
          evidence: evidence,
          applied: false, // set true later when Apply succeeds
        ));
      } catch (error) {
        debugPrint('[TUNE_SESSION] record skipped (non-fatal): $error');
      }
      // TunePlanStore holds only one "current" plan — invalidate the
      // shared read so every screen (including this one, on its next
      // build) re-fetches the plan that was JUST saved instead of a
      // possibly-cached earlier one.
      ref.invalidate(currentTunePlanProvider);
      // A flat-baseline DSP snapshot seeded for an EARLIER plan (see
      // _seedFlatBaselineSnapshot) would otherwise linger with the wrong
      // band frequencies/Q for this new plan — clear it so it gets reseeded
      // fresh against the plan that actually matters now.
      ref.invalidate(dspStateSnapshotProvider);
      final ko = _isKo;
      final roomLabel = ko ? roomTypeLabelKo(scan.roomType) : scan.roomType;
      final now = DateTime.now();

      // "After" reuses the identical octave-gaussian synthesis already used
      // for the LISTEN preview (spectrum_snapshot) — no new scoring
      // algorithm, no fabricated numbers — applied to whichever plan (AI or
      // rule-based) was actually selected above. Null when the underlying
      // curve can't produce a score (e.g. too few bins); the UI already
      // hides the Sound Score card whenever either value is null.
      final planPeaks = [
        for (final band in plan.bands)
          ResonancePeak(
              frequency: band.frequencyHz, gain: band.gainDb, q: band.q),
      ];
      final afterBins = SpectrumSnapshotController.previewWithPeaks(
        measurement.frequencyBins,
        planPeaks,
      );
      final afterScore = SoundScoreCalculator.compute(afterBins);

      final profile = ConsumerSoundProfile(
        id: plan.id,
        name: '$roomLabel Your Sound',
        roomType: scan.roomType,
        createdAt: now,
        updatedAt: now,
        micProfileName: scan.micProfileName,
        confidence: scan.confidence,
        isActive: false,
        status: ConsumerProfileStatus.ready,
        resultCards: resultCardsForPlan(scan.cards, plan),
        soundScoreBefore: beforeScore?.total,
        soundScoreAfter: afterScore?.total,
        preference: preference,
        usedAiRecommendation: usedAi,
        speakerProfileId: ref.read(speakerProfileProvider)?.id,
        profileType: ConsumerProfileType.tunaiTune,
        measurementId: measurement.id,
        tunePlanId: plan.id,
        isSelected: true,
        generationStatus: ConsumerProfileGenerationStatus.generated,
        deploymentStatus: TuneDeploymentStatus.notDeployed,
      );
      await ref
          .read(consumerSoundProfileProvider.notifier)
          .upsertGeneratedAndSelect(profile);

      // Generates the LISTEN "TUNAI Sound" preview curve from the real
      // TunePlan bands on top of the real Room Scan curve (spectrum_snapshot's
      // existing octave-gaussian synthesis — no new algorithm, no fabricated
      // values). No-ops if `before` isn't set this session (spectrum snapshot
      // is not persisted across restarts; the live DSP A/B toggle in LISTEN
      // does not depend on this and keeps working regardless).
      ref.read(spectrumSnapshotProvider.notifier).applyPeaks(planPeaks);
    } catch (error, stackTrace) {
      // Do NOT swallow: surface the failure so the flow stops silently bouncing
      // back to the analysis screen. debugPrint exposes the exact throw on-device.
      debugPrint('[TUNE] Acoustic Tune generation failed: $error\n$stackTrace');
      if (plan != null) await TunePlanStore.clear();
      if (mounted) setState(() => _createError = error.toString());
    } finally {
      if (mounted) setState(() => _creating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ko = _isKo;
    final ble = ref.watch(bleProvider);
    final scan = ref.watch(roomScanResultProvider);
    final profiles = ref.watch(consumerSoundProfileProvider);
    final active = ref.watch(activeConsumerProfileProvider);
    final isConnected = ble.connection == BleConnectionState.connected;

    // State F — the active profile is applied now, OR was successfully applied
    // in a prior session. On reload the persisted `applied` deploymentStatus is
    // downgraded to `unknown` (historical), but the dspDeploymentRecord survives
    // and proves a real prior apply — enough to re-enter the Sound Profile /
    // LISTEN view. Shown regardless of BLE connection.
    final activeRecord = active?.dspDeploymentRecord;
    final activeApplied = active != null &&
        (active.deploymentStatus == TuneDeploymentStatus.applied ||
            (activeRecord != null &&
                activeRecord.result ==
                    ConsumerDspDeploymentRecordResult.applied &&
                activeRecord.dspApplied));
    if (activeApplied) {
      return _StateF(
          ko: ko,
          profile: active,
          onGoListen: widget.onApplied,
          onReset: () async {
            _resetApplyPhase();
            await ref
                .read(consumerSoundProfileProvider.notifier)
                .deactivateAll();
          },
          onFineTune: scan == null ? null : () => _openFineTune(active, scan));
    }

    // Apply lifecycle states (session-scoped, not persisted)
    final applyPhase = ref.watch(consumerApplyPhaseProvider);
    debugPrint('[FLOW] AiScreen build: scan=${scan != null} '
        'connected=$isConnected creating=$_creating '
        'activeDeploy=${active?.deploymentStatus} applyPhase=$applyPhase '
        'profiles=${profiles.length}');
    if (applyPhase == ConsumerApplyPhase.applying) {
      return _StateApplying(ko: ko);
    }
    if (applyPhase == ConsumerApplyPhase.restored) {
      return _StateApplyResult(
        ko: ko,
        safe: true,
        onRetry: _resetApplyPhase,
      );
    }
    if (applyPhase == ConsumerApplyPhase.failed) {
      return _StateApplyResult(
        ko: ko,
        safe: false,
        onRetry: _resetApplyPhase,
      );
    }

    // State A — no BLE AND no scan data: show connection prompt.
    // If scan already exists (e.g. from simulation), skip past State A.
    if (!isConnected && scan == null) {
      return _StateA(
          ko: ko,
          onGoConnect: widget.onGoTo != null ? () => widget.onGoTo!(0) : null);
    }

    // State B — BLE connected but no scan yet
    if (scan == null) {
      debugPrint('[FLOW] RENDER StateB (scan null)');
      return _StateB(
          ko: ko,
          onGoRoom: widget.onGoTo != null ? () => widget.onGoTo!(1) : null);
    }

    // State D — creating in progress
    if (_creating) {
      return _StateD(ko: ko);
    }

    // State E — ready profile exists (not yet active); visible even without BLE
    final ready = profiles
        .where((profile) =>
            profile.status == ConsumerProfileStatus.ready &&
            profile.generationStatus ==
                ConsumerProfileGenerationStatus.generated &&
            profile.deploymentStatus == TuneDeploymentStatus.notDeployed)
        .toList();
    debugPrint('[FLOW] ready=${ready.length} statuses=['
        '${profiles.map((p) => '${p.status.name}/${p.generationStatus.name}/'
            '${p.deploymentStatus.name}/sel=${p.isSelected}').join('; ')}]');
    if (ready.isNotEmpty) {
      debugPrint('[FLOW] RENDER StateE');
      final speakerCheck = ref.watch(speakerCheckResultProvider);
      final audioConfirmed = ref.watch(audioSpeakerConfirmedProvider);
      final planAsync = ref.watch(currentTunePlanProvider);
      // A brief loading flash is honest (we don't yet know the real
      // availability), rather than guessing from resultCards while the
      // actual TunePlan is still being fetched.
      if (planAsync.isLoading && !planAsync.hasValue) {
        return const Scaffold(
          backgroundColor: Color(0xFF0A0A0A),
          body: Center(
              child: CircularProgressIndicator(color: Colors.white38)),
        );
      }
      final plan = planAsync.valueOrNull;
      final availability =
          evaluateTuneAvailability(plan: plan, profile: ready.first);
      debugPrint('[TUNE_STATE] '
          'planExists=${plan != null} '
          'bandCount=${plan?.bands.length ?? 0} '
          'confidence=${ready.first.confidence} '
          'speakerConfirmed=$audioConfirmed '
          'availability=${availability.name}');
      // Proactive, not lazy: without this, the DSP flat-baseline workaround
      // (see _seedFlatBaselineSnapshot) only ever ran inside the Apply tap
      // handler, so the button's OWN LABEL always read "스피커 확인 필요" on
      // the very first render after a Tune was created — even though every
      // real condition (BLE connected, identity validated, TunePlan saved)
      // was already true — and functionally required one "wasted" tap
      // before the real one. Idempotent (checks dspStateSnapshotProvider !=
      // null itself), so calling it on every rebuild here is safe/cheap.
      WidgetsBinding.instance
          .addPostFrameCallback((_) => _seedFlatBaselineSnapshot());
      return _StateE(
        ko: ko,
        profile: ready.first,
        scan: scan,
        isConnected: isConnected,
        speakerCheck: speakerCheck,
        availability: availability,
        // Always actionable: when ready it applies, otherwise it re-checks live
        // state and routes the user (connect / Bluetooth / reconnect). Never a
        // dead disabled control.
        onApply: _onSpeakerButtonPressed,
        onFineTune: () => _openFineTune(ready.first, scan),
        onReMeasure: _reMeasure,
        onCompleteWithoutCorrection: () =>
            _completeWithoutCorrection(ready.first.id),
      );
    }

    // State C — scan done, no profile yet; visible even without BLE
    debugPrint('[FLOW] RENDER StateC (no ready profile)');
    return _StateC(
      ko: ko,
      scan: scan,
      isConnected: isConnected,
      onCreate: () => _createTune(scan),
      error: _createError,
    );
  }
}

List<RoomScanResultCard> resultCardsForPlan(
  List<RoomScanResultCard> measuredCards,
  TunePlan plan,
) {
  final hasLowBand = plan.bands.any((band) => band.frequencyHz <= 200);
  final hasUpperBand = plan.bands.any((band) => band.frequencyHz > 200);
  return measuredCards.where((card) {
    if (card.id == 'measured_bass') return hasLowBand;
    if (card.id == 'measured_balance') return hasUpperBand;
    if (card.id == 'measured_neutral') return plan.bands.isEmpty;
    return false;
  }).toList(growable: false);
}

// ── State A — No device, no scan ─────────────────────────────────────────────

class _StateA extends StatelessWidget {
  final bool ko;
  final VoidCallback? onGoConnect;
  const _StateA({required this.ko, this.onGoConnect});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(32, 60, 32, 40),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Spacer(flex: 2),
              Text(
                ko ? '먼저 스피커를 연결해 주세요.' : 'Connect your speaker first.',
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.w300,
                    height: 1.4),
              ),
              const SizedBox(height: 16),
              Text(
                ko
                    ? 'TUNAI 스피커를 연결하면\n공간에 맞는 나만의 사운드를 만들 수 있습니다.'
                    : 'Connect your TUNAI speaker to create\na personal sound made for your space.',
                style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.4),
                    fontSize: 14,
                    height: 1.65),
              ),
              const SizedBox(height: 36),
              if (onGoConnect != null)
                _TuneBigButton(
                    label: ko ? '스피커 연결하기' : 'Connect Speaker',
                    onTap: onGoConnect!),
              const Spacer(flex: 3),
            ],
          ),
        ),
      ),
    );
  }
}

// ── State B — No Room Analysis ────────────────────────────────────────────────────

class _StateB extends StatelessWidget {
  final bool ko;
  final VoidCallback? onGoRoom;
  const _StateB({required this.ko, this.onGoRoom});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(32, 60, 32, 40),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Spacer(flex: 2),
              Text(
                ko ? '먼저 공간을 알아볼게요.' : 'First, let’s understand your space.',
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.w300,
                    height: 1.4),
              ),
              const SizedBox(height: 16),
              Text(
                ko
                    ? '공간 분석을 먼저 완료하면\n나만의 사운드를 만들 수 있습니다.'
                    : 'Complete Space Analysis to create\nYour Sound.',
                style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.4),
                    fontSize: 14,
                    height: 1.65),
              ),
              const SizedBox(height: 36),
              if (onGoRoom != null)
                _TuneBigButton(
                    label: ko ? '공간 분석 시작' : 'Start Space Analysis',
                    onTap: onGoRoom!),
              const Spacer(flex: 3),
            ],
          ),
        ),
      ),
    );
  }
}

// ── State C — Room scan done, no profile ─────────────────────────────────────

class _StateC extends ConsumerWidget {
  final bool ko;
  final RoomScanResult scan;
  final VoidCallback onCreate;
  final bool isConnected;
  final String? error;
  const _StateC(
      {required this.ko,
      required this.scan,
      required this.onCreate,
      this.isConnected = true,
      this.error});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(32, 48, 32, 32),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      ko ? '공간 분석 완료' : 'Space Analysis Complete',
                      style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.4),
                          fontSize: 11,
                          letterSpacing: 2),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      ko
                          ? '공간에 맞는\n나만의 사운드를 만들 준비가 되었습니다.'
                          : 'Ready to create your\npersonal sound for this space.',
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 26,
                          fontWeight: FontWeight.w300,
                          height: 1.35,
                          letterSpacing: -0.2),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      ko
                          ? 'TUNAI가 공간 특성에 맞는 안전한 나만의 사운드를 만듭니다.\n복잡한 설정 없이, 그저 좋은 소리를 들으면 됩니다.'
                          : 'TUNAI shapes Your Sound for this space.\nNo complex setup — just press play and listen.',
                      style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.45),
                          fontSize: 14,
                          height: 1.65),
                    ),
                    const SizedBox(height: 32),
                    _ScanSummaryCard(ko: ko, scan: scan),
                    const SizedBox(height: 28),
                    Text(
                      ko ? '원하는 소리 느낌을 골라주세요' : 'Choose the sound you want',
                      style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.35),
                          fontSize: 10,
                          letterSpacing: 1.5),
                    ),
                    const SizedBox(height: 12),
                    const _PreferenceSelector(),
                    if (!isConnected) ...[
                      const SizedBox(height: 16),
                      _ConnectionNotice(ko: ko),
                    ],
                    if (error != null) ...[
                      const SizedBox(height: 16),
                      Text(
                        ko
                            ? '사운드 생성에 실패했습니다. 다시 시도해 주세요.\n$error'
                            : 'Could not create your Sound. Please try again.\n$error',
                        style: const TextStyle(
                            color: Color(0xFFFF5252),
                            fontSize: 13,
                            height: 1.5),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(32, 0, 32, 40),
              child: _TuneBigButton(
                label: ko ? '나만의 사운드 만들기' : 'Create Your Sound',
                onTap: onCreate,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ScanSummaryCard extends StatelessWidget {
  final bool ko;
  final RoomScanResult scan;
  const _ScanSummaryCard({required this.ko, required this.scan});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.white12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(ko ? '스캔 결과' : 'Scan Result',
            style: TextStyle(
                color: Colors.white.withValues(alpha: 0.35),
                fontSize: 10,
                letterSpacing: 1.5)),
        const SizedBox(height: 10),
        Row(children: [
          _ScanChip(text: ko ? roomTypeLabelKo(scan.roomType) : scan.roomType),
          const SizedBox(width: 8),
          _ScanChip(
              text: ko
                  ? '마이크: ${micProfileLabelKo(scan.micProfileName)}'
                  : 'Mic: ${scan.micProfileName}'),
        ]),
        const SizedBox(height: 8),
        _ScanChip(text: _confidenceLabel(scan.confidence, ko: ko)),
        if (scan.confidence == 'Low') ...[
          const SizedBox(height: 10),
          Text(
            ko
                ? '더 조용한 곳에서 다시 측정하면 더 정확한 사운드를 만들 수 있어요.'
                : 'Measuring again in a quieter spot can improve accuracy.',
            style: TextStyle(
                color: Colors.white.withValues(alpha: 0.35),
                fontSize: 11,
                height: 1.5),
          ),
        ],
      ]),
    );
  }
}

/// Translates the internal High/Medium/Low confidence label (from
/// `_confidenceFromMeasurement`, computed from real signal/timing/mic
/// metrics) into consumer language — never shown as a raw technical score.
String _confidenceLabel(String confidence, {required bool ko}) {
  switch (confidence) {
    case 'High':
      return ko ? '측정 신호 좋음' : 'Clear measurement';
    case 'Medium':
      return ko ? '측정 신호 보통' : 'Fair measurement';
    default:
      return ko ? '측정 신호 약함' : 'Weak measurement';
  }
}

class _ScanChip extends StatelessWidget {
  final String text;
  const _ScanChip({required this.text});
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
            border: Border.all(color: Colors.white12),
            borderRadius: BorderRadius.circular(3)),
        child: Text(text,
            style: TextStyle(
                color: Colors.white.withValues(alpha: 0.45), fontSize: 10)),
      );
}

/// Lets the user pick their sound character before "Create Your Sound" —
/// plain consumer language only (see SoundPreference.label/description),
/// never PEQ/gain/intensity terms.
class _PreferenceSelector extends ConsumerWidget {
  const _PreferenceSelector();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ko = Localizations.localeOf(context).languageCode == 'ko';
    final selected = ref.watch(soundPreferenceProvider);
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final preference in SoundPreference.values)
          _PreferenceChip(
            label: preference.label(ko: ko),
            description: preference.description(ko: ko),
            selected: preference == selected,
            onTap: () =>
                ref.read(soundPreferenceProvider.notifier).state = preference,
          ),
      ],
    );
  }
}

class _PreferenceChip extends StatelessWidget {
  final String label;
  final String description;
  final bool selected;
  final VoidCallback onTap;

  const _PreferenceChip({
    required this.label,
    required this.description,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          constraints: const BoxConstraints(maxWidth: 150),
          decoration: BoxDecoration(
            color: selected
                ? Colors.white.withValues(alpha: 0.1)
                : Colors.white.withValues(alpha: 0.03),
            border: Border.all(
              color: selected ? Colors.white54 : Colors.white12,
            ),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: TextStyle(
                  color: selected
                      ? Colors.white
                      : Colors.white.withValues(alpha: 0.6),
                  fontSize: 13,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                description,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.32),
                  fontSize: 10,
                  height: 1.3,
                ),
              ),
            ],
          ),
        ),
      );
}

// ── State D — Creating ────────────────────────────────────────────────────────

class _StateD extends StatelessWidget {
  final bool ko;
  const _StateD({required this.ko});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(32, 60, 32, 40),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                ko
                    ? '이 공간에 맞는 안전한\n나만의 사운드를 만들고 있습니다.'
                    : 'Creating Your Sound\nfor this space.',
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.w300,
                    height: 1.4),
              ),
              const Spacer(),
              const LinearProgressIndicator(
                backgroundColor: Colors.white12,
                color: Colors.white38,
                minHeight: 1.5,
              ),
              const SizedBox(height: 24),
              Text(
                ko
                    ? '공간 특성을 분석하고 있습니다...'
                    : 'Shaping the sound for your space...',
                style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.35),
                    fontSize: 12,
                    letterSpacing: 0.5),
              ),
              const Spacer(flex: 3),
            ],
          ),
        ),
      ),
    );
  }
}

// ── State E — Profile ready ───────────────────────────────────────────────────

class _StateE extends StatelessWidget {
  final bool ko;
  final ConsumerSoundProfile profile;
  final RoomScanResult scan;
  final VoidCallback? onApply;
  final bool isConnected;
  final SpeakerCheckResult? speakerCheck;
  final VoidCallback? onFineTune;
  final VoidCallback onReMeasure;
  final VoidCallback onCompleteWithoutCorrection;
  /// The single, already-computed judgment (see tune_availability.dart) —
  /// this widget is now a pure dispatcher on it, never re-derives its own
  /// competing signal from `profile.resultCards` or confidence directly.
  final TuneAvailability availability;
  const _StateE(
      {required this.ko,
      required this.profile,
      required this.scan,
      required this.onApply,
      this.isConnected = true,
      this.speakerCheck,
      this.onFineTune,
      required this.onReMeasure,
      required this.onCompleteWithoutCorrection,
      required this.availability});

  @override
  Widget build(BuildContext context) {
    switch (availability) {
      case TuneAvailability.lowConfidence:
        return _StateELowConfidence(ko: ko, onReMeasure: onReMeasure);
      case TuneAvailability.noCorrectionNeeded:
        return _StateEBalanced(
          ko: ko,
          profile: profile,
          onReMeasure: onReMeasure,
          onComplete: onCompleteWithoutCorrection,
        );
      case TuneAvailability.readyToApply:
        return _StateEReadyToApply(
          ko: ko,
          profile: profile,
          isConnected: isConnected,
          speakerCheck: speakerCheck,
          onApply: onApply,
          onFineTune: onFineTune,
        );
    }
  }
}

/// Real correction was generated — the original Apply flow, unchanged in
/// substance from before, just extracted into its own widget now that
/// State E branches three ways.
class _StateEReadyToApply extends ConsumerWidget {
  final bool ko;
  final ConsumerSoundProfile profile;
  final bool isConnected;
  final SpeakerCheckResult? speakerCheck;
  final VoidCallback? onApply;
  final VoidCallback? onFineTune;
  const _StateEReadyToApply({
    required this.ko,
    required this.profile,
    required this.isConnected,
    required this.speakerCheck,
    required this.onApply,
    required this.onFineTune,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final snapshot = ref.watch(spectrumSnapshotProvider);
    final audioConfirmed = ref.watch(audioSpeakerConfirmedProvider);
    final audioStale = ref.watch(audioSpeakerConfirmationStaleProvider);
    final readyToApply =
        speakerCheck?.readyToApply == true && audioConfirmed;
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(32, 48, 32, 32),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      Container(
                          width: 8,
                          height: 8,
                          decoration: const BoxDecoration(
                              color: Color(0xFF69F0AE),
                              shape: BoxShape.circle)),
                      const SizedBox(width: 10),
                      Text(ko ? '공간 맞춤' : 'MADE FOR YOUR SPACE',
                          style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.45),
                              fontSize: 11,
                              letterSpacing: 1.5)),
                    ]),
                    const SizedBox(height: 20),
                    Text(
                      ko ? '나만의 사운드가 준비되었습니다.' : 'Your Sound is ready.',
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 26,
                          fontWeight: FontWeight.w300,
                          height: 1.35,
                          letterSpacing: -0.2),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      ko
                          ? '이 공간에 맞게 안전하게 조정된 나만의 사운드입니다.\n적용하면 바로 들을 수 있습니다.'
                          : 'Your personalized sound is ready.\nApply it to your speaker and start listening.',
                      style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.45),
                          fontSize: 14,
                          height: 1.65),
                    ),
                    const SizedBox(height: 32),
                    if (profile.soundScoreBefore != null &&
                        profile.soundScoreAfter != null) ...[
                      if (profile.soundScoreImprovement != null &&
                          profile.soundScoreImprovement! > 0)
                        _SoundScoreCard(
                          ko: ko,
                          before: profile.soundScoreBefore!,
                          after: profile.soundScoreAfter!,
                        )
                      else
                        // Real bands exist but the score delta didn't
                        // register as an improvement — still never show
                        // "X → X, +0" as if it were a result.
                        _NoImprovementNotice(ko: ko),
                      const SizedBox(height: 24),
                    ],
                    // This screen is "Your Sound is ready — Apply it" — Apply
                    // hasn't happened yet, so Listen is not reachable yet
                    // either.
                    AcousticTimeline(
                      currentStep: AcousticTimelineStep.acousticTune,
                      ko: ko,
                    ),
                    const SizedBox(height: 28),
                    Text(
                      ko ? '나의 사운드' : 'YOUR SOUND',
                      style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.35),
                          fontSize: 11,
                          letterSpacing: 1.5),
                    ),
                    const SizedBox(height: 12),
                    ...profile.resultCards
                        .map((card) => _ResultCard(card: card, ko: ko)),
                    // Only rendered when a real measured curve exists for
                    // this session (spectrumSnapshotProvider is in-memory,
                    // set by measure_screen.dart at scan time and by
                    // _createTune() at Tune-generation time) — never a
                    // fabricated graph. `after` is included only when it was
                    // actually synthesized from this profile's real TunePlan
                    // bands; otherwise only the Before curve draws.
                    if (snapshot.before != null) ...[
                      const SizedBox(height: 24),
                      Text(
                        ko ? 'Room Balance' : 'Room Balance',
                        style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.35),
                            fontSize: 11,
                            letterSpacing: 1.5),
                      ),
                      const SizedBox(height: 14),
                      ConsumerResponseChart(
                        before: snapshot.before!,
                        after: snapshot.afterAi,
                        ko: ko,
                      ),
                    ],
                    const SizedBox(height: 12),
                    _AiExplainSection(profile: profile, ko: ko),
                    if (!isConnected) ...[
                      const SizedBox(height: 16),
                      _ConnectionNotice(ko: ko),
                    ],
                    const SizedBox(height: 16),
                    if (!readyToApply)
                      _SpeakerCheckNotice(
                        ko: ko,
                        check: speakerCheck,
                        audioConfirmed: audioConfirmed,
                        audioStale: audioStale,
                      ),
                    if (onFineTune != null) ...[
                      const SizedBox(height: 20),
                      GestureDetector(
                        onTap: onFineTune,
                        child: Center(
                          child: Text(
                            ko ? '더 세밀하게 조정하기' : 'Fine-tune further',
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.35),
                              fontSize: 12,
                              decoration: TextDecoration.underline,
                              decorationColor:
                                  Colors.white.withValues(alpha: 0.15),
                            ),
                          ),
                        ),
                      ),
                    ],
                    // Extra breathing room so the last content never feels
                    // crowded against the fixed bottom button below.
                    const SizedBox(height: 12),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(32, 16, 32, 40),
              child: _TuneBigButton(
                // "실제 적용 가능한 경우에만 동작" — the button's own label and
                // tap target both reflect the live speakerCheck status; it is
                // never a dead/misleading control (see resolveSpeakerButtonAction,
                // which _onSpeakerButtonPressed always re-derives from live
                // state regardless of what's shown here).
                label: readyToApply
                    ? (ko ? '스피커에 적용' : 'Apply to Speaker')
                    : (ko ? '스피커 확인 필요' : 'Check Speaker'),
                onTap: onApply,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// "보정 불필요" — the room measured with no correctable buildup at all
/// (TunePlan had zero bands, a real structural fact — see
/// tune_availability.dart's `TuneAvailability.noCorrectionNeeded`). Never
/// shows a fake comparison or a "X → X, +0" score; offers exactly the two
/// real choices the user can make: accept this as-is, or measure again.
class _StateEBalanced extends ConsumerWidget {
  final bool ko;
  final ConsumerSoundProfile profile;
  final VoidCallback onReMeasure;
  final VoidCallback onComplete;
  const _StateEBalanced({
    required this.ko,
    required this.profile,
    required this.onReMeasure,
    required this.onComplete,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final snapshot = ref.watch(spectrumSnapshotProvider);
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(32, 48, 32, 32),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      Container(
                          width: 8,
                          height: 8,
                          decoration: const BoxDecoration(
                              color: Color(0xFF69F0AE),
                              shape: BoxShape.circle)),
                      const SizedBox(width: 10),
                      Text(ko ? '공간 분석 완료' : 'SPACE ANALYSIS COMPLETE',
                          style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.45),
                              fontSize: 11,
                              letterSpacing: 1.5)),
                    ]),
                    const SizedBox(height: 20),
                    Text(
                      ko ? '공간 분석이 완료되었습니다.' : 'Space analysis complete.',
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 26,
                          fontWeight: FontWeight.w300,
                          height: 1.35,
                          letterSpacing: -0.2),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      ko
                          ? '현재 스피커와 공간의 균형이 좋아\n큰 조정이 필요한 부분은 발견되지 않았습니다.'
                          : 'Your speaker and space are already well balanced'
                              '—we found nothing that needed a big change.',
                      style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.45),
                          fontSize: 14,
                          height: 1.65),
                    ),
                    const SizedBox(height: 20),
                    // Never present "no correction" as a failure: TUNAI did
                    // analyze the space and made a real decision (to leave it
                    // alone), so this line names that decision instead of
                    // reading like a null result.
                    Text(
                      ko
                          ? '좋은 소리는 무조건 바꾸는 것이 아니라\n필요한 부분만 조정하는 것입니다.'
                          : 'A great sound isn\'t about changing everything'
                              '—it\'s about adjusting only what needs it.',
                      style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.3),
                          fontSize: 12,
                          height: 1.6,
                          fontStyle: FontStyle.italic),
                    ),
                    const SizedBox(height: 32),
                    AcousticTimeline(
                      currentStep: AcousticTimelineStep.acousticTune,
                      ko: ko,
                    ),
                    const SizedBox(height: 28),
                    Text(
                      ko ? '분석 결과' : 'ANALYSIS RESULT',
                      style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.35),
                          fontSize: 11,
                          letterSpacing: 1.5),
                    ),
                    const SizedBox(height: 12),
                    _AnalysisChecklistCard(ko: ko, confidence: profile.confidence),
                    // Real measured curve only — never a fake "after" line,
                    // since there are no TunePlan bands to synthesize one
                    // from in this branch (TuneAvailability.noCorrectionNeeded).
                    if (snapshot.before != null) ...[
                      const SizedBox(height: 24),
                      Text(
                        'Room Balance',
                        style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.35),
                            fontSize: 11,
                            letterSpacing: 1.5),
                      ),
                      const SizedBox(height: 14),
                      ConsumerResponseChart(before: snapshot.before!, ko: ko),
                    ],
                    const SizedBox(height: 12),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(32, 16, 32, 40),
              child: Column(
                children: [
                  _TuneBigButton(
                    label: ko ? '완료' : 'Done',
                    onTap: onComplete,
                  ),
                  const SizedBox(height: 14),
                  GestureDetector(
                    onTap: onReMeasure,
                    child: Text(
                      ko ? '다시 측정하기' : 'Measure again',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.4),
                        fontSize: 13,
                        decoration: TextDecoration.underline,
                        decorationColor: Colors.white.withValues(alpha: 0.15),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// "측정 신뢰도 부족" — also zero bands, but the confidence label already
/// computed from real signal/timing metrics (see room_scan_result.dart's
/// `_confidenceFromMeasurement`) is 'Low' — meaning the empty result is more
/// likely explained by a weak/noisy capture than a genuinely balanced room.
/// Distinguished from `_StateEBalanced` so the user gets the RIGHT next
/// step (re-measure, not "accept as done").
class _StateELowConfidence extends StatelessWidget {
  final bool ko;
  final VoidCallback onReMeasure;
  const _StateELowConfidence({required this.ko, required this.onReMeasure});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(32, 60, 32, 40),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Spacer(flex: 2),
              Icon(Icons.graphic_eq,
                  color: Colors.white.withValues(alpha: 0.25), size: 32),
              const SizedBox(height: 24),
              Text(
                ko ? '측정 신뢰도가 부족합니다.' : "The measurement wasn't reliable enough.",
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.w300,
                    height: 1.4),
              ),
              const SizedBox(height: 16),
              Text(
                ko
                    ? '측정 중 소음이 많았거나 신호가 약했던 것 같습니다.\n더 조용한 곳에서 다시 측정하면 정확한 결과를 얻을 수 있습니다.'
                    : 'There may have been too much background noise, or the '
                        'signal was too weak.\nMeasuring again somewhere '
                        'quieter should give a clearer result.',
                style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.45),
                    fontSize: 14,
                    height: 1.65),
              ),
              const SizedBox(height: 36),
              _TuneBigButton(
                label: ko ? '다시 측정하기' : 'Measure again',
                onTap: onReMeasure,
              ),
              const Spacer(flex: 3),
            ],
          ),
        ),
      ),
    );
  }
}

/// Shows what TUNAI actually checked, even when nothing needed adjusting —
/// three lines, each derived from a real, already-computed fact (never a
/// generated/fake analysis). Only rendered from [_StateEBalanced], which is
/// itself only reached when [profile.resultCards] holds nothing but the
/// 'measured_neutral' card — i.e. structurally, no bass buildup card and no
/// balance card were triggered for this measurement, and confidence is not
/// 'Low' (that case renders [_StateELowConfidence] instead).
class _AnalysisChecklistCard extends StatelessWidget {
  final bool ko;
  final String confidence;
  const _AnalysisChecklistCard({required this.ko, required this.confidence});

  @override
  Widget build(BuildContext context) {
    final confidenceLabel = confidence == 'High'
        ? (ko ? '매우 충분' : 'Excellent')
        : (ko ? '충분' : 'Good');
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.white12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _AnalysisChecklistRow(
            label: ko ? '공간 균형' : 'Space Balance',
            value: ko ? '안정적' : 'Stable',
          ),
          const SizedBox(height: 12),
          _AnalysisChecklistRow(
            label: ko ? '저음 응답' : 'Bass Response',
            value: ko ? '양호' : 'Good',
          ),
          const SizedBox(height: 12),
          _AnalysisChecklistRow(
            label: ko ? '측정 신뢰도' : 'Measurement Confidence',
            value: confidenceLabel,
          ),
        ],
      ),
    );
  }
}

class _AnalysisChecklistRow extends StatelessWidget {
  final String label;
  final String value;
  const _AnalysisChecklistRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Icon(Icons.check_circle_outline,
            color: Color(0xFF69F0AE), size: 16),
        const SizedBox(width: 10),
        Expanded(
          child: Text(label,
              style: const TextStyle(color: Colors.white70, fontSize: 13)),
        ),
        Text(value,
            style: TextStyle(
                color: Colors.white.withValues(alpha: 0.5), fontSize: 13)),
      ],
    );
  }
}

// ── Apply lifecycle state widgets ────────────────────────────────────────────

class _StateApplying extends StatelessWidget {
  final bool ko;
  const _StateApplying({required this.ko});

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: const Color(0xFF0A0A0A),
        body: SafeArea(
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(
                    color: Color(0xFF69F0AE),
                    strokeWidth: 1.5,
                  ),
                ),
                const SizedBox(height: 24),
                Text(
                  key: const Key('consumer_apply_applying'),
                  ko
                      ? '나만의 사운드를 스피커에 적용하고 있습니다.'
                      : 'Applying your personal sound to the speaker...',
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 16,
                    fontWeight: FontWeight.w300,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  ko ? '잠시 기다려 주세요.' : 'Please wait.',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.35),
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
}

/// Shown after a non-applied outcome.
///
/// [safe] = true  → rollback succeeded; original settings are active.
/// [safe] = false → rollback also failed; speaker may be in a partial state.
class _StateApplyResult extends StatelessWidget {
  final bool ko;
  final bool safe;
  final VoidCallback onRetry;
  const _StateApplyResult({
    required this.ko,
    required this.safe,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    final headline = safe
        ? (ko ? '적용하지 못했습니다.' : 'Could not apply.')
        : (ko ? '적용하지 못했습니다.' : 'Could not apply.');
    final body = safe
        ? (ko
            ? '이전 설정을 유지했습니다. 다시 시도해 주세요.'
            : 'Your previous settings are still active. Please try again.')
        : (ko
            ? '스피커를 재연결하고 다시 시도해 주세요.'
            : 'Please reconnect your speaker and try again.');
    final retryLabel = ko ? '다시 시도' : 'Try again';

    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(32, 48, 32, 40),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Spacer(),
              Text(
                key: Key(
                    safe ? 'consumer_apply_restored' : 'consumer_apply_failed'),
                headline,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 26,
                  fontWeight: FontWeight.w300,
                  height: 1.35,
                  letterSpacing: -0.2,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                body,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.45),
                  fontSize: 14,
                  height: 1.65,
                ),
              ),
              const Spacer(),
              _TuneBigButton(label: retryLabel, onTap: onRetry),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Speaker Check notice ──────────────────────────────────────────────────────

class _SpeakerCheckNotice extends StatelessWidget {
  final bool ko;
  final SpeakerCheckResult? check;
  final bool audioConfirmed;
  final bool audioStale;
  const _SpeakerCheckNotice({
    required this.ko,
    this.check,
    this.audioConfirmed = true,
    this.audioStale = false,
  });

  String _message() {
    final status = check?.status;
    if (status == SpeakerCheckStatus.speakerNotConnected) {
      return ko ? '스피커 연결을 확인해 주세요.' : 'Check speaker connection.';
    }
    if (status == SpeakerCheckStatus.identityUnconfirmed ||
        status == SpeakerCheckStatus.speakerMismatch) {
      return ko
          ? '연결된 스피커를 확인할 수 없습니다.'
          : 'Speaker identity could not be confirmed.';
    }
    // Connection/identity/DSP-readiness are all fine — only the user's audio
    // confirmation ("did you hear it from your speaker") is missing or no
    // longer matches this connection (see speaker_verification_session.dart).
    if ((status == null || status == SpeakerCheckStatus.readyToApply) &&
        !audioConfirmed) {
      return audioStale
          ? (ko
              ? '스피커 연결이 변경되었습니다. 확인음을 다시 재생해 주세요.'
              : 'Your speaker connection has changed. Play the confirmation '
                  'tone again.')
          : (ko
              ? 'ROOM 탭에서 스피커 확인을 먼저 완료해 주세요.'
              : 'Complete the speaker check in the ROOM tab first.');
    }
    // soundStateNotVerified / originalValuesUnavailable / null
    return ko
        ? '적용하기 전에 스피커를 확인해야 합니다.'
        : 'Check your speaker before applying.';
  }

  @override
  Widget build(BuildContext context) => Container(
        key: const Key('consumer_dsp_state_verification_required'),
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.03),
          border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          _message(),
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.55),
            fontSize: 13,
            height: 1.5,
          ),
        ),
      );
}

/// AI Explain — a plain-language "why" for the Tune, expandable and
/// collapsed by default so it never crowds the main result. Built entirely
/// from real, already-computed facts already on [profile] (preference,
/// room type, whether a deeper analysis pass was used, the same
/// [RoomScanResultCard] descriptions already shown above) — never the raw
/// AI explanation text from the backend (that stays server-side only; see
/// AiTuneOrchestrator/AiTuningService), and never a PEQ/DSP/Hz/dB/frequency
/// term.
class _AiExplainSection extends StatelessWidget {
  final ConsumerSoundProfile profile;
  final bool ko;
  const _AiExplainSection({required this.profile, required this.ko});

  @override
  Widget build(BuildContext context) {
    final roomLabel = ko ? roomTypeLabelKo(profile.roomType) : profile.roomType;
    final reasons = [
      for (final card in profile.resultCards) card.description(ko: ko),
    ];
    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        tilePadding: EdgeInsets.zero,
        childrenPadding: const EdgeInsets.only(bottom: 4),
        title: Text(
          ko ? '왜 이렇게 만들었나요?' : 'Why this sound?',
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.45),
            fontSize: 12,
          ),
        ),
        iconColor: Colors.white38,
        collapsedIconColor: Colors.white38,
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  ko
                      ? '$roomLabel에서 측정한 결과를 바탕으로, 안전한 범위 안에서 소리를 조정했습니다.'
                      : 'Based on what was measured in your $roomLabel, the sound was shaped safely within a tested range.',
                  style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.42),
                      fontSize: 12,
                      height: 1.6),
                ),
                if (reasons.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(
                    ko
                        ? '${reasons.join(' ')} ${profile.preference.label(ko: true)} 느낌을 살렸습니다.'
                        : '${reasons.join(' ')} Shaped for a ${profile.preference.label(ko: false).toLowerCase()} feel.',
                    style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.42),
                        fontSize: 12,
                        height: 1.6),
                  ),
                ],
                if (profile.usedAiRecommendation) ...[
                  const SizedBox(height: 6),
                  Text(
                    ko
                        ? '공간과 스피커의 특성을 함께 살펴 더 깊이 분석했습니다.'
                        : 'Your space and speaker were analyzed together for a deeper result.',
                    style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.42),
                        fontSize: 12,
                        height: 1.6),
                  ),
                ],
                const SizedBox(height: 6),
                _HistoryContextLine(profile: profile, ko: ko),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Closed Loop UX: a single extra sentence, shown only when there is real
/// prior Apply history (see tune_outcome_history.dart) to compare against —
/// never a fabricated "improvement" claim. Loads asynchronously and renders
/// nothing while pending or when there's nothing relevant to say, so it
/// never blocks or clutters the main explanation above.
class _HistoryContextLine extends StatefulWidget {
  final ConsumerSoundProfile profile;
  final bool ko;
  const _HistoryContextLine({required this.profile, required this.ko});

  @override
  State<_HistoryContextLine> createState() => _HistoryContextLineState();
}

class _HistoryContextLineState extends State<_HistoryContextLine> {
  TuneOutcomeRecord? _priorOutcome;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final history = await TuneOutcomeHistory.load();
      final prior = history
          .where((o) => o.tunePlanId != widget.profile.tunePlanId)
          .toList();
      if (mounted && prior.isNotEmpty) {
        setState(() => _priorOutcome = prior.first);
      }
    } catch (_) {
      // Silently skip — this is a supplementary line, never a blocking error.
    }
  }

  @override
  Widget build(BuildContext context) {
    final prior = _priorOutcome;
    final after = widget.profile.soundScoreAfter;
    if (prior == null || after == null || prior.soundScoreAfter == null) {
      return const SizedBox.shrink();
    }
    if (after <= prior.soundScoreAfter!) return const SizedBox.shrink();
    return Text(
      widget.ko
          ? '지난번보다 더 편안한 청취 경험으로 조정되었습니다.'
          : "This adjustment goes further than last time's, for a more comfortable listening experience.",
      style: TextStyle(
          color: Colors.white.withValues(alpha: 0.42),
          fontSize: 12,
          height: 1.6),
    );
  }
}

class _ResultCard extends StatelessWidget {
  final RoomScanResultCard card;
  final bool ko;
  const _ResultCard({required this.card, required this.ko});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
              width: 6,
              height: 6,
              decoration: const BoxDecoration(
                  color: Color(0xFF69F0AE), shape: BoxShape.circle)),
          const SizedBox(width: 8),
          Text(card.label(ko: ko),
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w300)),
        ]),
        const SizedBox(height: 6),
        Text(card.description(ko: ko),
            style: TextStyle(
                color: Colors.white.withValues(alpha: 0.4),
                fontSize: 12,
                height: 1.5)),
      ]),
    );
  }
}

// ── State F — Profile active ──────────────────────────────────────────────────

class _StateF extends StatelessWidget {
  final bool ko;
  final ConsumerSoundProfile profile;
  final VoidCallback onGoListen;
  final VoidCallback onReset;
  final VoidCallback? onFineTune;
  const _StateF(
      {required this.ko,
      required this.profile,
      required this.onGoListen,
      required this.onReset,
      this.onFineTune});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(32, 48, 32, 32),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      Container(
                          width: 8,
                          height: 8,
                          decoration: const BoxDecoration(
                              color: Color(0xFF69F0AE),
                              shape: BoxShape.circle)),
                      const SizedBox(width: 10),
                      Text(ko ? '나만의 사운드 적용됨' : 'Your Sound Active',
                          style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.45),
                              fontSize: 11,
                              letterSpacing: 1.5)),
                    ]),
                    const SizedBox(height: 20),
                    Text(
                      ko ? '완료되었습니다.' : 'Done.',
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 26,
                          fontWeight: FontWeight.w300,
                          height: 1.35,
                          letterSpacing: -0.2),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      ko
                          ? '이제 이 공간만을 위한 사운드를 즐겨보세요.\nLISTEN에서 Before / After를 직접 들어보세요.'
                          : 'Enjoy your personalized sound for this space.\nGo to LISTEN to compare before and after.',
                      style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.45),
                          fontSize: 14,
                          height: 1.65),
                    ),
                    const SizedBox(height: 32),
                    if (profile.soundScoreBefore != null &&
                        profile.soundScoreAfter != null) ...[
                      if (profile.soundScoreImprovement != null &&
                          profile.soundScoreImprovement! > 0)
                        _SoundScoreCard(
                          ko: ko,
                          before: profile.soundScoreBefore!,
                          after: profile.soundScoreAfter!,
                        )
                      else
                        _NoImprovementNotice(ko: ko),
                      const SizedBox(height: 24),
                    ],
                    AcousticTimeline(
                      currentStep: AcousticTimelineStep.savedProfile,
                      ko: ko,
                    ),
                    const SizedBox(height: 28),
                    Text(
                      ko ? '조정 내용' : 'Applied adjustments',
                      style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.35),
                          fontSize: 11,
                          letterSpacing: 1.5),
                    ),
                    const SizedBox(height: 12),
                    ...profile.resultCards
                        .map((card) => _ResultCard(card: card, ko: ko)),
                    const SizedBox(height: 12),
                    _AiExplainSection(profile: profile, ko: ko),
                    const SizedBox(height: 20),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        GestureDetector(
                          onTap: () => _confirmReset(context),
                          child: Text(
                            ko ? '다시 만들기' : 'Create new profile',
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.3),
                              fontSize: 12,
                              decoration: TextDecoration.underline,
                              decorationColor:
                                  Colors.white.withValues(alpha: 0.15),
                            ),
                          ),
                        ),
                        if (onFineTune != null) ...[
                          const SizedBox(width: 20),
                          GestureDetector(
                            onTap: onFineTune,
                            child: Text(
                              ko ? '세부 조정' : 'Fine-tune',
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.3),
                                fontSize: 12,
                                decoration: TextDecoration.underline,
                                decorationColor:
                                    Colors.white.withValues(alpha: 0.15),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(32, 0, 32, 40),
              child: _TuneBigButton(
                label: ko ? 'LISTEN으로 이동' : 'Go to LISTEN',
                onTap: onGoListen,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmReset(BuildContext context) async {
    final ko = Localizations.localeOf(context).languageCode == 'ko';
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        title: Text(ko ? '프로파일 초기화' : 'Reset Profile',
            style: const TextStyle(color: Colors.white, fontSize: 15)),
        content: Text(
          ko
              ? '현재 나만의 사운드를 비활성화하고 새로 만들겠습니까?'
              : 'Deactivate the current personal sound and create a new one?',
          style:
              const TextStyle(color: Colors.white60, fontSize: 13, height: 1.5),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(ko ? '취소' : 'Cancel',
                  style: const TextStyle(color: Colors.white38))),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(ko ? '확인' : 'Confirm',
                  style: const TextStyle(color: Colors.white70))),
        ],
      ),
    );
    if (ok == true) onReset();
  }
}

// ── Connection notice (no hardware) ──────────────────────────────────────────

class _ConnectionNotice extends StatelessWidget {
  final bool ko;
  const _ConnectionNotice({required this.ko});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.white12),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(children: [
        const Icon(Icons.bluetooth_disabled, color: Colors.white24, size: 14),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            ko
                ? '나만의 사운드가 준비되었습니다. 스피커를 연결하면 이 설정으로 들을 수 있습니다.'
                : 'Your Sound is ready. Connect your speaker to listen with it.',
            style: const TextStyle(
                color: Colors.white38, fontSize: 11, height: 1.5),
          ),
        ),
      ]),
    );
  }
}

// ── Sound Score card ─────────────────────────────────────────────────────────

/// Shown instead of [_SoundScoreCard] whenever the real computed Before/
/// After scores are equal (or the Tune has no bands at all) — this is a
/// genuine, real outcome (a room that measured close to already balanced,
/// or a measurement too weak to find a clear correction), never a bug to
/// paper over with a "72 → 72, +0" number that reads as broken.
class _NoImprovementNotice extends StatelessWidget {
  final bool ko;
  const _NoImprovementNotice({required this.ko});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.03),
        border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(
          ko ? '자연스러운 균형을 유지했습니다' : 'Kept a natural balance',
          style: const TextStyle(
              color: Colors.white70, fontSize: 13, fontWeight: FontWeight.w400),
        ),
        const SizedBox(height: 8),
        Text(
          ko
              ? 'TUNAI가 공간을 확인한 결과, 큰 변화보다는 지금의 자연스러운 균형을\n유지하는 방향으로 조정을 마쳤습니다.'
              : 'After analyzing your space, TUNAI kept the adjustments minimal '
                  'to preserve the natural balance you already had.',
          style: TextStyle(
              color: Colors.white.withValues(alpha: 0.4),
              fontSize: 12,
              height: 1.6),
        ),
      ]),
    );
  }
}

class _SoundScoreCard extends StatelessWidget {
  final bool ko;
  final int before;
  final int after;
  const _SoundScoreCard(
      {required this.ko, required this.before, required this.after});

  @override
  Widget build(BuildContext context) {
    final improvement = after - before;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: const Color(0xFF69F0AE).withValues(alpha: 0.04),
        border:
            Border.all(color: const Color(0xFF69F0AE).withValues(alpha: 0.2)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(
          ko ? 'Sound Score' : 'Sound Score',
          style: TextStyle(
              color: Colors.white.withValues(alpha: 0.35),
              fontSize: 10,
              letterSpacing: 1.5),
        ),
        const SizedBox(height: 10),
        Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text('$before',
                  style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.4),
                      fontSize: 22,
                      fontWeight: FontWeight.w300)),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: Icon(Icons.arrow_forward,
                    color: Colors.white.withValues(alpha: 0.25), size: 14),
              ),
              Text('$after',
                  style: const TextStyle(
                      color: Color(0xFF69F0AE),
                      fontSize: 28,
                      fontWeight: FontWeight.w300)),
              const SizedBox(width: 10),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0xFF69F0AE).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  '+$improvement',
                  style: const TextStyle(
                      color: Color(0xFF69F0AE),
                      fontSize: 12,
                      fontWeight: FontWeight.w500),
                ),
              ),
            ]),
      ]),
    );
  }
}

// ── Common button ─────────────────────────────────────────────────────────────

class _TuneBigButton extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;
  const _TuneBigButton({required this.label, this.onTap});

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 18),
        decoration: BoxDecoration(
          color: enabled ? Colors.white : Colors.transparent,
          border: !enabled ? Border.all(color: Colors.white24) : null,
          borderRadius: BorderRadius.circular(4),
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: TextStyle(
            color:
                enabled ? Colors.black : Colors.white.withValues(alpha: 0.45),
            fontSize: 14,
            fontWeight: FontWeight.w500,
            letterSpacing: 1.2,
          ),
        ),
      ),
    );
  }
}

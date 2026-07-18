import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../ble/ble_controller.dart';
import '../../core/consumer_dsp_deployment.dart';
import '../../core/dsp_state_synchronization.dart';
import '../../core/room_scan_result.dart';
import '../../core/consumer_sound_profile.dart';
import '../../core/room_measurement.dart';
import '../../core/speaker_check_gate.dart';
import '../../core/speaker_state_verification.dart';
import '../../core/tune_deployment_plan.dart';
import '../../core/tune_plan.dart';
import '../../shared/acoustic_timeline.dart';

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

  bool get _isKo => Localizations.localeOf(context).languageCode == 'ko';

  void _resetApplyPhase() {
    ref.read(consumerApplyPhaseProvider.notifier).state =
        ConsumerApplyPhase.idle;
  }

  Future<void> _applyTune() async {
    final speakerCheck = ref.read(speakerCheckResultProvider);
    final snapshot = ref.read(dspStateSnapshotProvider);
    final profile = ref.read(selectedConsumerProfileProvider);
    if (!speakerCheck.readyToApply || snapshot == null || profile == null) {
      return;
    }

    final tunePlan = await TunePlanStore.load();
    if (!mounted || tunePlan == null) return;

    final expectedId = speakerCheck.confirmedSpeakerId!;

    final originalValues = <TuneDeploymentOriginalValues>[];
    for (var i = 0; i < tunePlan.bands.length; i++) {
      final state = snapshot.stateFor(
        DspPeqStateRequest(
          channel: ConsumerDspDeploymentExecutor.confirmedTunePlanChannel,
          bandId: i,
        ),
      );
      if (state == null || !mounted) return;
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

    ref.read(consumerApplyPhaseProvider.notifier).state = switch (result.outcome) {
      ConsumerDspDeploymentOutcome.applied => ConsumerApplyPhase.idle,
      ConsumerDspDeploymentOutcome.restored => ConsumerApplyPhase.restored,
      ConsumerDspDeploymentOutcome.failed => ConsumerApplyPhase.failed,
      ConsumerDspDeploymentOutcome.blocked => ConsumerApplyPhase.idle,
    };
  }

  Future<void> _createTune(RoomScanResult scan) async {
    if (_creating) return;
    setState(() => _creating = true);
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
      plan = const TunePlanner(now: DateTime.now).generate(measurement);
      await TunePlanStore.save(plan);
      final ko = _isKo;
      final roomLabel = ko ? roomTypeLabelKo(scan.roomType) : scan.roomType;
      final now = DateTime.now();
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
        resultCards: _resultCardsForPlan(scan.cards, plan),
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
    } catch (_) {
      if (plan != null) await TunePlanStore.clear();
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

    // State F — active profile exists (shown regardless of BLE connection)
    if (active != null &&
        active.deploymentStatus == TuneDeploymentStatus.applied) {
      return _StateF(
          ko: ko,
          profile: active,
          onGoListen: widget.onApplied,
          onReset: () async {
            _resetApplyPhase();
            await ref
                .read(consumerSoundProfileProvider.notifier)
                .deactivateAll();
          });
    }

    // Apply lifecycle states (session-scoped, not persisted)
    final applyPhase = ref.watch(consumerApplyPhaseProvider);
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
    if (ready.isNotEmpty) {
      final speakerCheck = ref.watch(speakerCheckResultProvider);
      return _StateE(
        ko: ko,
        profile: ready.first,
        scan: scan,
        isConnected: isConnected,
        speakerCheck: speakerCheck,
        onApply: speakerCheck.readyToApply ? _applyTune : null,
      );
    }

    // State C — scan done, no profile yet; visible even without BLE
    return _StateC(
      ko: ko,
      scan: scan,
      isConnected: isConnected,
      onCreate: () => _createTune(scan),
    );
  }
}

List<RoomScanResultCard> _resultCardsForPlan(
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
                ko ? '아직 공간 분석이 없습니다.' : 'No Room Analysis yet.',
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
                    : 'Run a Room Analysis first to create\nYour Sound.',
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

class _StateC extends StatelessWidget {
  final bool ko;
  final RoomScanResult scan;
  final VoidCallback onCreate;
  final bool isConnected;
  const _StateC(
      {required this.ko,
      required this.scan,
      required this.onCreate,
      this.isConnected = true});

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
                          : 'TUNAI creates a safe, room-matched personal sound.\nNo complex settings — just better sound.',
                      style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.45),
                          fontSize: 14,
                          height: 1.65),
                    ),
                    const SizedBox(height: 32),
                    _ScanSummaryCard(ko: ko, scan: scan),
                    if (!isConnected) ...[
                      const SizedBox(height: 16),
                      _ConnectionNotice(ko: ko),
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
      ]),
    );
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
                    : 'Creating a safe personal sound\nfor this room.',
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
                    : 'Analysing room characteristics...',
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
  const _StateE(
      {required this.ko,
      required this.profile,
      required this.scan,
      required this.onApply,
      this.isConnected = true,
      this.speakerCheck});

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
                      Text(ko ? '공간 맞춤' : 'Room Matched',
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
                          : 'A safe, room-matched personal sound has been created.\nApply it to start listening.',
                      style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.45),
                          fontSize: 14,
                          height: 1.65),
                    ),
                    const SizedBox(height: 32),
                    if (profile.soundScoreBefore != null &&
                        profile.soundScoreAfter != null) ...[
                      _SoundScoreCard(
                        ko: ko,
                        before: profile.soundScoreBefore!,
                        after: profile.soundScoreAfter!,
                      ),
                      const SizedBox(height: 24),
                    ],
                    AcousticTimeline(
                      currentStep: AcousticTimelineStep.listen,
                      ko: ko,
                    ),
                    const SizedBox(height: 28),
                    Text(
                      ko ? 'TUNAI가 찾아낸 것' : 'What TUNAI found',
                      style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.35),
                          fontSize: 11,
                          letterSpacing: 1.5),
                    ),
                    const SizedBox(height: 12),
                    ...profile.resultCards
                        .map((card) => _ResultCard(card: card, ko: ko)),
                    if (!isConnected) ...[
                      const SizedBox(height: 16),
                      _ConnectionNotice(ko: ko),
                    ],
                    const SizedBox(height: 16),
                    if (speakerCheck == null ||
                        !speakerCheck!.readyToApply)
                      _SpeakerCheckNotice(ko: ko, check: speakerCheck),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(32, 0, 32, 40),
              child: _TuneBigButton(
                label: speakerCheck?.readyToApply == true
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
                key: Key(safe
                    ? 'consumer_apply_restored'
                    : 'consumer_apply_failed'),
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
  const _SpeakerCheckNotice({required this.ko, this.check});

  String _message() {
    final status = check?.status;
    if (status == SpeakerCheckStatus.speakerNotConnected) {
      return ko
          ? '스피커 연결을 확인해 주세요.'
          : 'Check speaker connection.';
    }
    if (status == SpeakerCheckStatus.identityUnconfirmed ||
        status == SpeakerCheckStatus.speakerMismatch) {
      return ko
          ? '연결된 스피커를 확인할 수 없습니다.'
          : 'Speaker identity could not be confirmed.';
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
  const _StateF(
      {required this.ko,
      required this.profile,
      required this.onGoListen,
      required this.onReset});

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
                      _SoundScoreCard(
                        ko: ko,
                        before: profile.soundScoreBefore!,
                        after: profile.soundScoreAfter!,
                      ),
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
                    const SizedBox(height: 20),
                    GestureDetector(
                      onTap: () => _confirmReset(context),
                      child: Center(
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

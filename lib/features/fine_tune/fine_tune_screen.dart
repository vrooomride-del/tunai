import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/audio_analyzer.dart' show ResonancePeak;
import '../../core/consumer_sound_profile.dart';
import '../../core/fine_tune_adjustments.dart';
import '../../core/room_measurement.dart';
import '../../core/room_scan_result.dart';
import '../../core/sound_score_calculator.dart';
import '../../core/spectrum_snapshot.dart';
import '../../core/speaker_check_gate.dart' show dspStateSnapshotProvider;
import '../../core/tune_plan.dart';
import '../ai/ai_screen.dart' show resultCardsForPlan, currentTunePlanProvider;
import '../../shared/widgets.dart';

/// Fine Tune — five plain-language sliders (Bass/Warm/Vocal/Space/Detail)
/// that let the user nudge the ALREADY-generated, already-safety-checked
/// Tune further, without ever exposing PEQ/DSP/gain/Hz/Q. Every slider maps
/// to a real [FineTuneAdjustments] knob (see that file's doc comment) — none
/// invent a new frequency region or fabricated effect.
///
/// Purely a rule-based refinement layer: it always regenerates through the
/// same [TunePlanner] + [TuneSafetyBounds] pipeline the base Tune already
/// went through, saves a new candidate [ConsumerSoundProfile] (not yet
/// applied), and hands control back to the existing TUNE Apply flow — it
/// never calls the AI Orchestrator, never touches DSP Apply, BLE, or the
/// Safety Validator gate itself.
class FineTuneScreen extends ConsumerStatefulWidget {
  final ConsumerSoundProfile baseProfile;
  final RoomScanResult scan;

  const FineTuneScreen({
    super.key,
    required this.baseProfile,
    required this.scan,
  });

  @override
  ConsumerState<FineTuneScreen> createState() => _FineTuneScreenState();
}

class _FineTuneScreenState extends ConsumerState<FineTuneScreen> {
  double _bass = 1.0;
  double _warm = 1.0;
  double _vocal = 1.0;
  double _space = 1.0;
  int _detail = FineTuneAdjustments.maxDetailBandLimit;

  RoomMeasurement? _measurement;
  bool _loading = true;
  bool _saving = false;
  String? _error;

  TunePlan? _previewPlan;
  int? _beforeScore;
  int? _afterScore;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final measurement = await RoomMeasurementStore.load();
    if (!mounted) return;
    if (measurement == null || measurement.id != widget.baseProfile.measurementId) {
      setState(() {
        _loading = false;
        _error = 'measurement_unavailable';
      });
      return;
    }
    setState(() {
      _measurement = measurement;
      _beforeScore = SoundScoreCalculator.compute(measurement.frequencyBins)?.total;
      _loading = false;
    });
    _recompute();
  }

  FineTuneAdjustments get _adjustments => FineTuneAdjustments(
        bassWeight: _bass,
        warmWeight: _warm,
        vocalWeight: _vocal,
        spaceWeight: _space,
        detailBandLimit: _detail,
      );

  void _recompute() {
    final measurement = _measurement;
    if (measurement == null) return;
    final plan = const TunePlanner(now: DateTime.now).generate(
      measurement,
      preference: widget.baseProfile.preference,
      fineTune: _adjustments,
    );
    final planPeaks = [
      for (final band in plan.bands)
        ResonancePeak(frequency: band.frequencyHz, gain: band.gainDb, q: band.q),
    ];
    final afterBins =
        SpectrumSnapshotController.previewWithPeaks(measurement.frequencyBins, planPeaks);
    setState(() {
      _previewPlan = plan;
      _afterScore = SoundScoreCalculator.compute(afterBins)?.total;
    });
  }

  Future<void> _save() async {
    final measurement = _measurement;
    final plan = _previewPlan;
    if (measurement == null || plan == null || _saving) return;
    final ko = Localizations.localeOf(context).languageCode == 'ko';
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await TunePlanStore.save(plan);
      // See currentTunePlanProvider's doc comment in ai_screen.dart —
      // TunePlanStore holds only one "current" plan, so every writer must
      // invalidate the shared read immediately after saving.
      ref.invalidate(currentTunePlanProvider);
      ref.invalidate(dspStateSnapshotProvider);
      final roomLabel = ko
          ? roomTypeLabelKo(widget.scan.roomType)
          : widget.scan.roomType;
      final now = DateTime.now();
      final planPeaks = [
        for (final band in plan.bands)
          ResonancePeak(frequency: band.frequencyHz, gain: band.gainDb, q: band.q),
      ];
      final profile = ConsumerSoundProfile(
        id: plan.id,
        name: '$roomLabel Your Sound',
        roomType: widget.scan.roomType,
        createdAt: now,
        updatedAt: now,
        micProfileName: widget.scan.micProfileName,
        confidence: widget.scan.confidence,
        isActive: false,
        status: ConsumerProfileStatus.ready,
        resultCards: resultCardsForPlan(widget.scan.cards, plan),
        soundScoreBefore: _beforeScore,
        soundScoreAfter: _afterScore,
        preference: widget.baseProfile.preference,
        usedAiRecommendation: false,
        speakerProfileId: widget.baseProfile.speakerProfileId,
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
      // If Fine Tune was opened from an already-applied profile, the new
      // candidate must surface as "ready to apply" rather than staying
      // hidden behind the still-active old one — deactivate it so the TUNE
      // tab naturally falls through to the ready state for the new profile.
      // No DSP is touched: this only clears local isActive bookkeeping, the
      // speaker keeps playing whatever was last actually deployed until the
      // user explicitly applies the new one.
      if (widget.baseProfile.isActive) {
        await ref.read(consumerSoundProfileProvider.notifier).deactivateAll();
      }
      ref.read(spectrumSnapshotProvider.notifier).applyPeaks(planPeaks);
      if (mounted) Navigator.of(context).pop();
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ko = Localizations.localeOf(context).languageCode == 'ko';
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      body: SafeArea(
        child: Column(
          children: [
            TunaiTopBar(subtitle: ko ? '세부 조정' : 'FINE TUNE'),
            Expanded(
              child: _loading
                  ? const Center(
                      child: CircularProgressIndicator(color: Colors.white38))
                  : _error != null && _previewPlan == null
                      ? _FineTuneUnavailable(ko: ko)
                      : _buildBody(ko),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBody(bool ko) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(28, 12, 28, 32),
      children: [
        Text(
          ko ? '나만의 사운드를\n더 세밀하게.' : 'Shape your sound\nfurther.',
          style: const TextStyle(
              color: Colors.white,
              fontSize: 24,
              fontWeight: FontWeight.w300,
              height: 1.3),
        ),
        const SizedBox(height: 10),
        Text(
          ko
              ? '이미 안전하게 만들어진 나만의 사운드를 기준으로,\n원하는 방향으로 살짝 조정할 수 있습니다.'
              : 'Starting from your already-safe Tune,\nnudge it further in the direction you want.',
          style: TextStyle(
              color: Colors.white.withValues(alpha: 0.42),
              fontSize: 13,
              height: 1.6),
        ),
        const SizedBox(height: 24),
        if (_beforeScore != null && _afterScore != null)
          _FineTuneScoreCard(ko: ko, before: _beforeScore!, after: _afterScore!),
        const SizedBox(height: 28),
        _FineTuneSlider(
          ko: ko,
          titleKo: '저음',
          titleEn: 'Bass',
          leftKo: '그대로',
          leftEn: 'Natural',
          rightKo: '정리됨',
          rightEn: 'Controlled',
          value: _bass,
          onChanged: (v) => setState(() => _bass = v),
          onChangeEnd: (_) => _recompute(),
        ),
        _FineTuneSlider(
          ko: ko,
          titleKo: '중저음',
          titleEn: 'Warm',
          leftKo: '따뜻하게',
          leftEn: 'Warm',
          rightKo: '깨끗하게',
          rightEn: 'Clean',
          value: _warm,
          onChanged: (v) => setState(() => _warm = v),
          onChangeEnd: (_) => _recompute(),
        ),
        _FineTuneSlider(
          ko: ko,
          titleKo: '보컬',
          titleEn: 'Vocal',
          leftKo: '부드럽게',
          leftEn: 'Gentle',
          rightKo: '또렷하게',
          rightEn: 'Forward',
          value: _vocal,
          onChanged: (v) => setState(() => _vocal = v),
          onChangeEnd: (_) => _recompute(),
        ),
        _FineTuneSlider(
          ko: ko,
          titleKo: '공간감',
          titleEn: 'Space',
          leftKo: '넓고 부드럽게',
          leftEn: 'Broad',
          rightKo: '정밀하게',
          rightEn: 'Precise',
          value: _space,
          onChanged: (v) => setState(() => _space = v),
          onChangeEnd: (_) => _recompute(),
        ),
        const SizedBox(height: 6),
        Text(
          ko ? '디테일' : 'Detail',
          style: TextStyle(
              color: Colors.white.withValues(alpha: 0.5),
              fontSize: 12,
              letterSpacing: 0.5),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            for (var level = 1; level <= FineTuneAdjustments.maxDetailBandLimit; level++) ...[
              Expanded(
                child: _DetailOption(
                  label: _detailLabel(level, ko: ko),
                  selected: _detail == level,
                  onTap: () {
                    setState(() => _detail = level);
                    _recompute();
                  },
                ),
              ),
              if (level != FineTuneAdjustments.maxDetailBandLimit)
                const SizedBox(width: 8),
            ],
          ],
        ),
        const SizedBox(height: 8),
        Text(
          ko
              ? '큰 문제 하나만 정리할지, 여러 곳을 세밀하게 정리할지 선택하세요.'
              : 'Fix just the biggest issue, or several in more detail.',
          style: TextStyle(
              color: Colors.white.withValues(alpha: 0.32),
              fontSize: 11,
              height: 1.5),
        ),
        if (_error != null) ...[
          const SizedBox(height: 16),
          Text(
            ko ? '저장하지 못했습니다. 다시 시도해 주세요.' : 'Could not save. Please try again.',
            style: const TextStyle(color: Color(0xFFFF5252), fontSize: 12),
          ),
        ],
        const SizedBox(height: 28),
        OutlineButton(
          label: _saving ? (ko ? '저장 중...' : 'Saving...') : (ko ? '이 사운드로 저장' : 'Save this sound'),
          loading: _saving,
          enabled: !_saving && _previewPlan != null,
          onTap: _previewPlan == null ? null : _save,
        ),
      ],
    );
  }

  String _detailLabel(int level, {required bool ko}) {
    switch (level) {
      case 1:
        return ko ? '간단히' : 'Simple';
      case 2:
        return ko ? '보통' : 'Balanced';
      default:
        return ko ? '세밀하게' : 'Detailed';
    }
  }
}

class _FineTuneUnavailable extends StatelessWidget {
  final bool ko;
  const _FineTuneUnavailable({required this.ko});

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text(
            ko
                ? '지금은 세부 조정을 할 수 없습니다.\n공간 분석을 다시 진행해 주세요.'
                : "Fine Tune isn't available right now.\nPlease run Space Analysis again.",
            textAlign: TextAlign.center,
            style: TextStyle(
                color: Colors.white.withValues(alpha: 0.45),
                fontSize: 14,
                height: 1.6),
          ),
        ),
      );
}

class _FineTuneScoreCard extends StatelessWidget {
  final bool ko;
  final int before;
  final int after;
  const _FineTuneScoreCard(
      {required this.ko, required this.before, required this.after});

  @override
  Widget build(BuildContext context) {
    final improvement = after - before;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: const Color(0xFF69F0AE).withValues(alpha: 0.04),
        border: Border.all(color: const Color(0xFF69F0AE).withValues(alpha: 0.2)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          Text(ko ? 'Sound Score' : 'Sound Score',
              style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.4), fontSize: 11)),
          const Spacer(),
          Text('$after',
              style: const TextStyle(
                  color: Color(0xFF69F0AE),
                  fontSize: 22,
                  fontWeight: FontWeight.w300)),
          const SizedBox(width: 8),
          Text(
            improvement >= 0 ? '+$improvement' : '$improvement',
            style: TextStyle(
                color: improvement >= 0
                    ? const Color(0xFF69F0AE)
                    : Colors.white38,
                fontSize: 12,
                fontWeight: FontWeight.w500),
          ),
        ],
      ),
    );
  }
}

class _FineTuneSlider extends StatelessWidget {
  final bool ko;
  final String titleKo;
  final String titleEn;
  final String leftKo;
  final String leftEn;
  final String rightKo;
  final String rightEn;
  final double value;
  final ValueChanged<double> onChanged;
  final ValueChanged<double> onChangeEnd;

  const _FineTuneSlider({
    required this.ko,
    required this.titleKo,
    required this.titleEn,
    required this.leftKo,
    required this.leftEn,
    required this.rightKo,
    required this.rightEn,
    required this.value,
    required this.onChanged,
    required this.onChangeEnd,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            ko ? titleKo : titleEn,
            style: TextStyle(
                color: Colors.white.withValues(alpha: 0.5),
                fontSize: 12,
                letterSpacing: 0.5),
          ),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 2,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 16),
              activeTrackColor: Colors.white70,
              inactiveTrackColor: Colors.white12,
              thumbColor: Colors.white,
              overlayColor: Colors.white10,
            ),
            child: Slider(
              value: value,
              min: 0.0,
              max: 1.0,
              onChanged: onChanged,
              onChangeEnd: onChangeEnd,
            ),
          ),
          Row(
            children: [
              Text(ko ? leftKo : leftEn,
                  style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.3), fontSize: 11)),
              const Spacer(),
              Text(ko ? rightKo : rightEn,
                  style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.3), fontSize: 11)),
            ],
          ),
        ],
      ),
    );
  }
}

class _DetailOption extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _DetailOption(
      {required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          height: 42,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected
                ? Colors.white.withValues(alpha: 0.1)
                : Colors.white.withValues(alpha: 0.03),
            border: Border.all(color: selected ? Colors.white54 : Colors.white12),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: selected ? Colors.white : Colors.white.withValues(alpha: 0.5),
              fontSize: 12,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
            ),
          ),
        ),
      );
}

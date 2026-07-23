import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/acoustic_analysis.dart';
import '../../core/acoustic_analysis_provider.dart';
import '../../core/acoustic_intent.dart' show ListeningGoal;
import '../../core/acoustic_profile.dart';
import '../../core/personal_optimization_context.dart';
import '../../core/sound_explanation.dart';
import '../../core/tune_session.dart';
import '../../core/consumer_dsp_deployment.dart';
import '../../core/consumer_sound_profile.dart';
import '../../core/tune_deployment_plan.dart';
import '../../core/tune_plan.dart';
import '../../core/tune_result_summary.dart';
import '../../shared/widgets.dart';
import '../ai/ai_screen.dart' show currentTunePlanProvider;
import '../ble/ble_controller.dart';

class ListenScreen extends ConsumerWidget {
  const ListenScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ko = Localizations.localeOf(context).languageCode == 'ko';
    final profile = ref.watch(activeConsumerProfileProvider);
    final connected =
        ref.watch(bleProvider).connection == BleConnectionState.connected;

    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const TunaiTopBar(subtitle: 'LISTEN'),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(28, 28, 28, 40),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      ko ? '나의 사운드를\n들어보세요.' : 'Listen to\nYour Sound.',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 32,
                        height: 1.18,
                        fontWeight: FontWeight.w300,
                        letterSpacing: -0.6,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      profile == null
                          ? (ko
                              ? '공간에 맞춘 나만의 사운드가 여기에 표시됩니다.'
                              : 'Your sound, shaped for your space, will appear here.')
                          : (connected
                              ? (ko
                                  ? '지금 나만의 사운드로 재생하고 있습니다.'
                                  : 'Your speaker is playing with Your Sound.')
                              : (ko
                                  ? '스피커를 연결하면 나만의 사운드로 들을 수 있습니다.'
                                  : 'Connect your speaker to listen with Your Sound.')),
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.42),
                        fontSize: 14,
                        height: 1.6,
                      ),
                    ),
                    const SizedBox(height: 36),
                    _CurrentSoundCard(
                      profile: profile,
                      connected: connected,
                      ko: ko,
                    ),
                    if (profile != null) ...[
                      const SizedBox(height: 16),
                      _AcousticOptimizationCard(profile: profile, ko: ko),
                      _WhyThisSoundCard(profile: profile, ko: ko),
                      _AiAcousticAnalysisCard(ko: ko),
                      _SoundTasteCard(ko: ko),
                      _TuneFeedbackCard(profile: profile, ko: ko),
                    ],
                    if (profile != null &&
                        profile.soundScoreBefore != null &&
                        profile.soundScoreAfter != null) ...[
                      const SizedBox(height: 16),
                      if (profile.soundScoreImprovement != null &&
                          profile.soundScoreImprovement! > 0)
                        _ListenSoundScoreCard(
                          ko: ko,
                          before: profile.soundScoreBefore!,
                          after: profile.soundScoreAfter!,
                        )
                      else
                        // Never repeat "72 → 72, +0" here either — same
                        // honest framing as the TUNE tab's result screen.
                        _ListenBalanceMaintainedCard(ko: ko),
                    ],
                    if (profile != null) ...[
                      const SizedBox(height: 20),
                      _OriginalTunaiToggleCard(profile: profile, ko: ko),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// "내 공간에 맞춘 변화" — describes, in consumer language, what the deployed
/// Tune actually did. Every line is derived from the real, current [TunePlan]'s
/// bands via [TuneResultSummary]; if there is no plan, it does not match this
/// profile, or it has no bands, the card renders NOTHING rather than showing a
/// fixed marketing claim. It never touches DSP, volume, or the comparison
/// state — it is purely a readout of data the Tune already contains.
class _AcousticOptimizationCard extends ConsumerWidget {
  final ConsumerSoundProfile profile;
  final bool ko;

  const _AcousticOptimizationCard({required this.profile, required this.ko});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final planAsync = ref.watch(currentTunePlanProvider);
    final plan = planAsync.valueOrNull;
    // Only describe a plan that is genuinely THIS profile's deployed plan.
    if (plan == null || plan.id != profile.tunePlanId) {
      return const SizedBox.shrink();
    }
    final summary = TuneResultSummary.of(plan);
    if (!summary.hasAnyChange) return const SizedBox.shrink();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(22, 20, 22, 22),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.035),
        border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            ko ? '내 공간에 맞춘 변화' : 'Shaped for your space',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.38),
              fontSize: 10,
              letterSpacing: 2.2,
            ),
          ),
          const SizedBox(height: 14),
          for (var i = 0; i < summary.points.length; i++) ...[
            if (i > 0) const SizedBox(height: 10),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  margin: const EdgeInsets.only(top: 6, right: 12),
                  width: 5,
                  height: 5,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: i == 0 ? 0.7 : 0.35),
                    shape: BoxShape.circle,
                  ),
                ),
                Expanded(
                  child: Text(
                    summary.points[i].label(ko: ko),
                    style: TextStyle(
                      color: Colors.white
                          .withValues(alpha: i == 0 ? 0.86 : 0.62),
                      fontSize: i == 0 ? 15 : 13.5,
                      height: 1.45,
                      fontWeight: i == 0 ? FontWeight.w400 : FontWeight.w300,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// Loads the recorded [TuneSession] for a plan id (feedback state included).
final _tuneSessionProvider =
    FutureProvider.family<TuneSession?, String>((ref, planId) async {
  return TuneSessionStore.load(planId);
});

/// "이 변화가 마음에 드나요?" — minimal feedback capture (Phase 6). Selection
/// only, saved locally to the [TuneSession]. There is NO learning server yet;
/// nothing leaves the device. Hidden when no session was recorded for this
/// Tune. Never blocks or affects the audio flow.
class _TuneFeedbackCard extends ConsumerStatefulWidget {
  final ConsumerSoundProfile profile;
  final bool ko;
  const _TuneFeedbackCard({required this.profile, required this.ko});

  @override
  ConsumerState<_TuneFeedbackCard> createState() => _TuneFeedbackCardState();
}

class _TuneFeedbackCardState extends ConsumerState<_TuneFeedbackCard> {
  TuneFeedback? _localChoice;

  @override
  Widget build(BuildContext context) {
    final planId = widget.profile.tunePlanId;
    if (planId == null) return const SizedBox.shrink();
    final session = ref.watch(_tuneSessionProvider(planId)).valueOrNull;
    if (session == null) return const SizedBox.shrink();
    final ko = widget.ko;
    final choice = _localChoice ?? session.feedback;

    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(22, 18, 22, 20),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.035),
          border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
          borderRadius: BorderRadius.circular(18),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              ko ? '이 변화가 마음에 드나요?' : 'How does this sound to you?',
              style: const TextStyle(
                  color: Colors.white, fontSize: 15, fontWeight: FontWeight.w400),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: _FeedbackButton(
                    label: ko ? '좋아요' : 'I like it',
                    icon: Icons.thumb_up_alt_outlined,
                    selected: choice == TuneFeedback.liked,
                    onTap: () => _choose(planId, TuneFeedback.liked),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _FeedbackButton(
                    label: ko ? '아쉬워요' : 'Not quite',
                    icon: Icons.thumb_down_alt_outlined,
                    selected: choice == TuneFeedback.disliked,
                    onTap: () => _choose(planId, TuneFeedback.disliked),
                  ),
                ),
              ],
            ),
            if (choice != TuneFeedback.none) ...[
              const SizedBox(height: 12),
              Text(
                ko
                    ? '의견 감사합니다. 더 나은 사운드를 위해 참고할게요.'
                    : 'Thanks — we’ll keep this in mind for better sound.',
                style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.45), fontSize: 12),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _choose(String planId, TuneFeedback feedback) async {
    setState(() => _localChoice = feedback);
    // Best-effort; never blocks or errors into the flow.
    await TuneSessionStore.setFeedback(planId, feedback);
  }
}

class _FeedbackButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;
  const _FeedbackButton({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected
              ? const Color(0xFF69F0AE).withValues(alpha: 0.08)
              : Colors.white.withValues(alpha: 0.03),
          border: Border.all(
            color: selected
                ? const Color(0xFF69F0AE).withValues(alpha: 0.5)
                : Colors.white24,
          ),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon,
                size: 15,
                color: selected ? const Color(0xFF69F0AE) : Colors.white60),
            const SizedBox(width: 8),
            Text(label,
                style: TextStyle(
                    color: selected ? Colors.white : Colors.white70,
                    fontSize: 13.5)),
          ],
        ),
      ),
    );
  }
}

/// Loads the stored per-Tune [PersonalOptimizationContext] for a plan id and
/// turns it into a deterministic [SoundExplanation]. No network, no AI. Keyed
/// by (planId, ko) so KO and EN render their own generated copy.
final _soundExplanationProvider =
    FutureProvider.family<SoundExplanation?, ({String planId, bool ko})>(
        (ref, key) async {
  final context = await OptimizationContextStore.load(key.planId);
  if (context == null) return null;
  final explanation =
      const SoundExplanationGenerator().generate(context, ko: key.ko);
  return explanation.hasContent ? explanation : null;
});

/// "왜 이렇게 조정했나요?" — the Explainable Sound Experience. Fully
/// DETERMINISTIC (rules over stored perceptual context; no AI call), so it
/// always reads the same for the same Tune, instantly and offline. Rendered
/// directly below "내 공간에 맞춘 변화". Hidden when there is no stored context
/// (e.g. a Tune created before this existed) — never a fabricated reason.
///
class _WhyThisSoundCard extends ConsumerWidget {
  final ConsumerSoundProfile profile;
  final bool ko;
  const _WhyThisSoundCard({required this.profile, required this.ko});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final planId = profile.tunePlanId;
    if (planId == null) return const SizedBox.shrink();
    final explanation = ref
        .watch(_soundExplanationProvider((planId: planId, ko: ko)))
        .valueOrNull;
    if (explanation == null || !explanation.hasContent) {
      return const SizedBox.shrink();
    }

    final rows = <(String, String)>[
      if (explanation.roomMessage != null)
        (ko ? '공간' : 'Space', explanation.roomMessage!),
      if (explanation.factoryMessage != null)
        (ko ? '스피커' : 'Speaker', explanation.factoryMessage!),
      if (explanation.preferenceMessage != null)
        (ko ? '취향' : 'Taste', explanation.preferenceMessage!),
    ];

    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(22, 20, 22, 22),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.035),
          border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
          borderRadius: BorderRadius.circular(18),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'TUNAI ACOUSTIC INTELLIGENCE',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.38),
                fontSize: 10,
                letterSpacing: 2.0,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              ko ? '왜 이렇게 조정했나요?' : 'Why it sounds this way',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w400,
              ),
            ),
            const SizedBox(height: 16),
            for (var i = 0; i < rows.length; i++) ...[
              if (i > 0) const SizedBox(height: 14),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 44,
                    child: Text(
                      rows[i].$1,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.45),
                        fontSize: 12,
                        height: 1.5,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      rows[i].$2,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.82),
                        fontSize: 13.5,
                        height: 1.5,
                        fontWeight: FontWeight.w300,
                      ),
                    ),
                  ),
                ],
              ),
            ],
            if (explanation.overallMessage != null) ...[
              const SizedBox(height: 16),
              Container(height: 0.5, color: Colors.white10),
              const SizedBox(height: 14),
              Text(
                explanation.overallMessage!,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.6),
                  fontSize: 12.5,
                  height: 1.55,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// "AI Acoustic Analysis" — the Acoustic Intelligence Layer's output.
///
/// Shown ONLY when the AI call succeeds and returns real content (see
/// [acousticAnalysisProvider] / [AcousticAnalysis.hasContent]). While the
/// call is in flight, and on any failure, this renders nothing — the
/// deterministic "내 공간에 맞춘 변화" card above already carries the
/// must-have "what changed" explanation with no network dependency, so a
/// missing AI card never leaves the screen empty. The AI never produces DSP
/// values; everything here is plain-language interpretation and placement
/// advice.
class _AiAcousticAnalysisCard extends ConsumerWidget {
  final bool ko;
  const _AiAcousticAnalysisCard({required this.ko});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final analysis = ref.watch(acousticAnalysisProvider).valueOrNull;
    if (analysis == null || !analysis.hasContent) {
      return const SizedBox.shrink();
    }

    final lines = <String>[
      if (analysis.summary != null) analysis.summary!,
      ...analysis.changes,
      if (analysis.placementAdvice != null) analysis.placementAdvice!,
      if (analysis.listeningAdvice != null) analysis.listeningAdvice!,
      if (analysis.confidenceExplanation != null)
        analysis.confidenceExplanation!,
    ];

    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(22, 20, 22, 22),
        decoration: BoxDecoration(
          color: const Color(0xFF7C4DFF).withValues(alpha: 0.06),
          border:
              Border.all(color: const Color(0xFF7C4DFF).withValues(alpha: 0.22)),
          borderRadius: BorderRadius.circular(18),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.auto_awesome,
                    color: Color(0xFFB39DFF), size: 15),
                const SizedBox(width: 8),
                Text(
                  ko ? 'AI 음향 분석' : 'AI Acoustic Analysis',
                  style: const TextStyle(
                    color: Color(0xFFB39DFF),
                    fontSize: 10,
                    letterSpacing: 2.2,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              ko ? '공간 분석 결과' : 'What we found in your space',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.9),
                fontSize: 16,
                fontWeight: FontWeight.w400,
              ),
            ),
            const SizedBox(height: 14),
            for (var i = 0; i < lines.length; i++) ...[
              if (i > 0) const SizedBox(height: 10),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    margin: const EdgeInsets.only(top: 6, right: 12),
                    width: 5,
                    height: 5,
                    decoration: BoxDecoration(
                      color: const Color(0xFFB39DFF).withValues(alpha: 0.6),
                      shape: BoxShape.circle,
                    ),
                  ),
                  Expanded(
                    child: Text(
                      lines[i],
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.78),
                        fontSize: 13.5,
                        height: 1.5,
                        fontWeight: FontWeight.w300,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Provider for the stored [AcousticProfile] (local only). Structure/UI
/// foundation — reading a saved taste, never affecting any correction.
final _storedAcousticProfileProvider =
    FutureProvider<AcousticProfile?>((ref) => AcousticProfileStore.load());

/// "나의 사운드 취향" — shows the user's saved listening taste in plain
/// language. Structure-only foundation: it reflects a stored preference and
/// does NOT change any tuning. Hidden entirely when no taste has been saved,
/// so it never shows a fabricated default.
class _SoundTasteCard extends ConsumerWidget {
  final bool ko;
  const _SoundTasteCard({required this.ko});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(_storedAcousticProfileProvider).valueOrNull;
    if (profile == null) return const SizedBox.shrink();

    final lines = <String>[
      profile.listeningTaste.description(ko: ko),
      if (profile.listeningGoal != null)
        _goalPhrase(profile.listeningGoal!, ko: ko),
    ];

    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(22, 20, 22, 22),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.035),
          border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
          borderRadius: BorderRadius.circular(18),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              ko ? '나의 사운드 취향' : 'My sound taste',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.38),
                fontSize: 10,
                letterSpacing: 2.2,
              ),
            ),
            const SizedBox(height: 14),
            for (var i = 0; i < lines.length; i++) ...[
              if (i > 0) const SizedBox(height: 10),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    margin: const EdgeInsets.only(top: 6, right: 12),
                    width: 5,
                    height: 5,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.4),
                      shape: BoxShape.circle,
                    ),
                  ),
                  Expanded(
                    child: Text(
                      lines[i],
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.7),
                        fontSize: 13.5,
                        height: 1.45,
                        fontWeight: FontWeight.w300,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  static String _goalPhrase(ListeningGoal goal, {required bool ko}) =>
      switch (goal) {
        ListeningGoal.music => ko ? '음악 감상 중심' : 'Focused on music',
        ListeningGoal.movie => ko ? '영화·영상 감상 중심' : 'Focused on movies',
        ListeningGoal.desktop => ko ? '가까이서 듣는 환경' : 'Close-up listening',
        ListeningGoal.longListening =>
          ko ? '오래 들어도 편안하게' : 'Comfortable for long sessions',
      };
}

class _CurrentSoundCard extends StatelessWidget {
  final ConsumerSoundProfile? profile;
  final bool connected;
  final bool ko;

  const _CurrentSoundCard({
    required this.profile,
    required this.connected,
    required this.ko,
  });

  @override
  Widget build(BuildContext context) {
    final active = profile != null;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(22, 22, 22, 24),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.035),
        border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                ko ? '현재 사운드' : 'CURRENT SOUND',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.38),
                  fontSize: 10,
                  letterSpacing: 2.2,
                ),
              ),
              const Spacer(),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: active
                      ? const Color(0xFF69F0AE).withValues(alpha: 0.1)
                      : Colors.white.withValues(alpha: 0.04),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color:
                            active ? const Color(0xFF69F0AE) : Colors.white24,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 7),
                    Text(
                      active
                          ? (ko ? '활성' : 'ACTIVE')
                          : (ko ? '준비 전' : 'NOT READY'),
                      style: TextStyle(
                        color:
                            active ? const Color(0xFF69F0AE) : Colors.white38,
                        fontSize: 9,
                        letterSpacing: 1.1,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 30),
          Text(
            profile?.name ?? (ko ? '나만의 사운드가 없습니다' : 'No sound yet'),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 22,
              height: 1.3,
              fontWeight: FontWeight.w300,
            ),
          ),
          const SizedBox(height: 9),
          Text(
            profile == null
                ? (ko
                    ? '공간 분석을 완료하면 나만의 사운드를 만들 수 있습니다.'
                    : 'Complete Space Analysis to create Your Sound.')
                : (ko
                    ? '${profile!.roomTypeLabel}에 맞춘 나의 사운드 · '
                        '${profile!.preference.label(ko: true)}'
                    : 'Your Sound for ${profile!.roomTypeLabelEn} · '
                        '${profile!.preference.label(ko: false)}'),
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.4),
              fontSize: 13,
              height: 1.5,
            ),
          ),
          if (active && !connected) ...[
            const SizedBox(height: 22),
            Container(height: 0.5, color: Colors.white10),
            const SizedBox(height: 18),
            Row(
              children: [
                const Icon(Icons.speaker_outlined,
                    color: Colors.white38, size: 17),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    ko ? '스피커 연결 대기 중' : 'Waiting for your speaker',
                    style: const TextStyle(
                      color: Colors.white54,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// Closes the loop from Room Scan → Tune → Apply back to LISTEN: the same
/// real Sound Score already computed and stored on the active profile at
/// Tune-creation time (see `ai_screen.dart`'s `_createTune`/`SoundScoreCalculator`
/// — no new scoring here, no fabricated number) shown at the point the user
/// actually goes to listen to the result.
class _ListenSoundScoreCard extends StatelessWidget {
  final bool ko;
  final int before;
  final int after;
  const _ListenSoundScoreCard(
      {required this.ko, required this.before, required this.after});

  @override
  Widget build(BuildContext context) {
    final improvement = after - before;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
      decoration: BoxDecoration(
        color: const Color(0xFF69F0AE).withValues(alpha: 0.04),
        border:
            Border.all(color: const Color(0xFF69F0AE).withValues(alpha: 0.2)),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Sound Score',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.38),
                    fontSize: 10,
                    letterSpacing: 1.6,
                  ),
                ),
                const SizedBox(height: 6),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Text('$before',
                        style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.4),
                            fontSize: 16,
                            fontWeight: FontWeight.w300)),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: Icon(Icons.arrow_forward,
                          color: Colors.white.withValues(alpha: 0.25),
                          size: 12),
                    ),
                    Text('$after',
                        style: const TextStyle(
                            color: Color(0xFF69F0AE),
                            fontSize: 22,
                            fontWeight: FontWeight.w300)),
                  ],
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: const Color(0xFF69F0AE).withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              improvement >= 0 ? '+$improvement' : '$improvement',
              style: const TextStyle(
                  color: Color(0xFF69F0AE),
                  fontSize: 12,
                  fontWeight: FontWeight.w500),
            ),
          ),
        ],
      ),
    );
  }
}

class _ListenBalanceMaintainedCard extends StatelessWidget {
  final bool ko;
  const _ListenBalanceMaintainedCard({required this.ko});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.03),
        border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          const Icon(Icons.check_circle_outline,
              color: Color(0xFF69F0AE), size: 16),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              ko ? '자연스러운 균형을 유지했습니다' : 'Kept a natural balance',
              style: const TextStyle(color: Colors.white70, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Original / TUNAI Sound A/B toggle ────────────────────────────────────────

enum _ToggleSide { original, tunaiSound }

/// Manual live A/B comparison between the flat baseline ("Original") and the
/// deployed tune ("TUNAI Sound"). No PEQ/FFT/DSP terms are ever shown — the
/// two states are exposed purely as Original vs TUNAI Sound.
///
/// Rebuilds the same [TuneDeploymentPlan]s used by TUNE's Apply flow directly
/// from the stored [TunePlan] using the app-wide "flat baseline = same
/// frequency/Q, gain 0dB" convention (see `AiScreen._seedFlatBaselineSnapshot`)
/// — no new measurement or DSP address is introduced, and master volume is
/// never touched by the toggle, so any perceived volume difference reflects
/// only the real EQ curve, not the toggle itself.
class _OriginalTunaiToggleCard extends ConsumerStatefulWidget {
  final ConsumerSoundProfile profile;
  final bool ko;

  const _OriginalTunaiToggleCard({required this.profile, required this.ko});

  @override
  ConsumerState<_OriginalTunaiToggleCard> createState() =>
      _OriginalTunaiToggleCardState();
}

class _OriginalTunaiToggleCardState
    extends ConsumerState<_OriginalTunaiToggleCard> {
  bool _switching = false;
  _ToggleSide? _pendingTarget;
  String? _error;

  /// Starting side always matches the profile's last known confidence:
  /// `applied` means the device currently holds the tuned values.
  _ToggleSide? _side;

  _ToggleSide _resolveSide() {
    if (_side != null) return _side!;
    return widget.profile.deploymentStatus == TuneDeploymentStatus.applied
        ? _ToggleSide.tunaiSound
        : _ToggleSide.original;
  }

  Future<List<TuneDeploymentPlan>?> _rebuildPlans() async {
    final plan = await TunePlanStore.load();
    if (plan == null || plan.id != widget.profile.tunePlanId) return null;
    if (plan.bands.isEmpty) return null;
    const channel = ConsumerDspDeploymentExecutor.confirmedTunePlanChannel;
    return [
      for (var bandId = 0; bandId < plan.bands.length; bandId++)
        TuneDeploymentPlan(
          channel: channel,
          bandId: bandId,
          frequencyHz: plan.bands[bandId].frequencyHz.round(),
          gainDb: plan.bands[bandId].gainDb,
          q: plan.bands[bandId].q,
          enable: true,
          originalValues: TuneDeploymentOriginalValues(
            frequencyHz: plan.bands[bandId].frequencyHz.round(),
            gainDb: 0.0,
            q: plan.bands[bandId].q,
            enable: true,
          ),
        ),
    ];
  }

  bool get _available {
    final ble = ref.watch(bleProvider);
    final service = ref.read(consumerBleServiceProvider);
    return ble.connection == BleConnectionState.connected &&
        service.supportedIdentityValidated &&
        service.validatedDeviceIdentifier == ble.selectedDeviceIdentifier &&
        widget.profile.tunePlanId != null &&
        widget.profile.deploymentStatus != TuneDeploymentStatus.unknown;
  }

  Future<void> _switchTo(_ToggleSide target) async {
    if (_switching || target == _resolveSide()) return;
    final ble = ref.read(bleProvider);
    final deviceId = ble.selectedDeviceIdentifier;
    if (deviceId == null || deviceId.isEmpty) return;

    setState(() {
      _switching = true;
      _pendingTarget = target;
      _error = null;
    });

    final plans = await _rebuildPlans();
    if (!mounted) return;
    if (plans == null) {
      setState(() {
        _switching = false;
        _pendingTarget = null;
        _error = widget.ko
            ? '지금은 전환할 수 없습니다. TUNE 탭에서 다시 적용해 주세요.'
            : "Can't switch right now. Reapply from the TUNE tab.";
      });
      return;
    }

    final service = ref.read(consumerBleServiceProvider);
    final executor = ConsumerDspDeploymentExecutor(
        transport: ConsumerBleDspTransport(service));
    final result = target == _ToggleSide.original
        ? await executor.restoreOriginal(
            plans: plans,
            expectedDeviceIdentifier: deviceId,
            explicitlyConfirmed: true,
          )
        : await executor.execute(
            plans: plans,
            expectedDeviceIdentifier: deviceId,
            explicitlyConfirmed: true,
          );
    if (!mounted) return;

    final succeeded = target == _ToggleSide.original
        ? result.outcome == ConsumerDspDeploymentOutcome.restored
        : result.outcome == ConsumerDspDeploymentOutcome.applied;

    if (succeeded) {
      await ref.read(consumerSoundProfileProvider.notifier).recordDspDeployment(
            widget.profile.id,
            ConsumerDspDeploymentRecord(
              tunePlanId: widget.profile.tunePlanId!,
              deviceIdentifier: deviceId,
              attemptedAt: DateTime.now(),
              bandCount: plans.length,
              result: target == _ToggleSide.original
                  ? ConsumerDspDeploymentRecordResult.restored
                  : ConsumerDspDeploymentRecordResult.applied,
              dspApplied: target == _ToggleSide.tunaiSound,
            ),
          );
      if (!mounted) return;
      setState(() {
        _side = target;
        _switching = false;
        _pendingTarget = null;
      });
    } else {
      setState(() {
        _switching = false;
        _pendingTarget = null;
        _error = widget.ko ? '전환하지 못했습니다.' : 'Could not switch.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final ko = widget.ko;
    final available = _available;
    final side = _resolveSide();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(22, 20, 22, 20),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.035),
        border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            ko ? '비교해서 들어보세요' : 'Compare the difference',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.38),
              fontSize: 10,
              letterSpacing: 2.2,
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _ToggleButton(
                  label: ko ? 'Original' : 'Original',
                  selected: side == _ToggleSide.original,
                  enabled: available && !_switching,
                  busy: _pendingTarget == _ToggleSide.original,
                  onTap: () => _switchTo(_ToggleSide.original),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _ToggleButton(
                  label: 'TUNAI Sound',
                  selected: side == _ToggleSide.tunaiSound,
                  enabled: available && !_switching,
                  busy: _pendingTarget == _ToggleSide.tunaiSound,
                  onTap: () => _switchTo(_ToggleSide.tunaiSound),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            !available
                ? (ko
                    ? '스피커를 연결하면 비교해서 들을 수 있습니다.'
                    : 'Connect your speaker to compare.')
                : (_error ??
                    (ko
                        ? '두 소리를 번갈아 들으며 비교해보세요.'
                        : 'Switch back and forth to compare.')),
            style: TextStyle(
              color: _error != null
                  ? const Color(0xFFFF5252)
                  : Colors.white.withValues(alpha: 0.4),
              fontSize: 12,
              height: 1.5,
            ),
          ),
          if (available &&
              _error == null &&
              side == _ToggleSide.tunaiSound &&
              widget.profile.resultCards.isNotEmpty) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final card in widget.profile.resultCards.take(2))
                  _WhatChangedTag(label: card.label(ko: ko)),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// Small plain-language tag (e.g. "Bass Control", "Vocal Clarity") drawn from
/// the profile's already-computed [RoomScanResultCard]s — the same real,
/// TunePlan-band-derived labels shown on the TUNE apply-success screen. No
/// new scoring or acoustic analysis is introduced here.
class _WhatChangedTag extends StatelessWidget {
  final String label;

  const _WhatChangedTag({required this.label});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: const Color(0xFF69F0AE).withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          label,
          style: const TextStyle(
            color: Color(0xFF69F0AE),
            fontSize: 11,
          ),
        ),
      );
}

class _ToggleButton extends StatelessWidget {
  final String label;
  final bool selected;
  final bool enabled;
  final bool busy;
  final VoidCallback onTap;

  const _ToggleButton({
    required this.label,
    required this.selected,
    required this.enabled,
    required this.busy,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(12),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          height: 46,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected
                ? Colors.white.withValues(alpha: 0.12)
                : Colors.white.withValues(alpha: 0.03),
            border: Border.all(
              color: selected ? Colors.white54 : Colors.white12,
            ),
            borderRadius: BorderRadius.circular(12),
          ),
          child: busy
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    color: Colors.white54,
                    strokeWidth: 1.5,
                  ),
                )
              : Text(
                  label,
                  style: TextStyle(
                    color: enabled ? Colors.white : Colors.white24,
                    fontSize: 13,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                  ),
                ),
        ),
      );
}


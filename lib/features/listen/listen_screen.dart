import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fl_chart/fl_chart.dart';
import '../../core/audio_analyzer.dart';
import '../../core/spectrum_snapshot.dart';
import '../../core/sound_profile_store.dart';
import '../../core/consumer_sound_profile.dart';
import '../../main.dart' show currentTabIndexProvider;
import '../health/speaker_health_screen.dart';
import '../../shared/widgets.dart';
import '../../shared/spectrum_chart.dart';
import '../../shared/preset_bar.dart';
import '../dsp/master_volume_controller.dart';
import '../ble/ble_controller.dart';
/// main.dart의 screens 리스트 순서상 LISTEN 탭의 인덱스 — 다른 탭으로 이동하면
/// Loop를 자동 정지하기 위해 필요
const _kListenTabIndex = 3;

/// LISTEN 탭 — Before/After A/B 비교 + 3색 스펙트럼 오버레이.
/// "와... 진짜 달라졌네"를 사용자가 직접 느끼게 하는 화면.
class ListenScreen extends ConsumerStatefulWidget {
  const ListenScreen({super.key});
  @override
  ConsumerState<ListenScreen> createState() => _ListenScreenState();
}

class _ListenScreenState extends ConsumerState<ListenScreen> {
  bool _showAfter = true;
  bool _loop = false;
  Timer? _timer;

  // Before/After 각각 이만큼 보여준 뒤 자동 전환 (요청: 1.5초씩)
  static const _loopInterval = Duration(milliseconds: 1500);

  Future<void> _saveConsumerProfile(BuildContext context, WidgetRef ref) async {
    final ko = Localizations.localeOf(context).languageCode == 'ko';
    final active = ref.read(activeConsumerProfileProvider);
    if (active == null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(ko
            ? '저장할 Sound Profile이 없습니다. 먼저 TUNE에서 Acoustic Tune을 만들어 주세요.'
            : 'No Sound Profile to save. Create an Acoustic Tune in TUNE first.'),
        duration: const Duration(seconds: 3),
      ));
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(ko ? 'Sound Profile이 저장되었습니다.' : 'Sound Profile saved.'),
      duration: const Duration(seconds: 2),
    ));
  }

  void _setLoop(bool v) {
    setState(() => _loop = v);
    _timer?.cancel();
    if (v) {
      _timer = Timer.periodic(_loopInterval, (_) {
        setState(() => _showAfter = !_showAfter);
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final snap = ref.watch(spectrumSnapshotProvider);
    final hasBefore = snap.before != null;
    final hasAfter = snap.afterAi != null;
    final activeConsumer = ref.watch(activeConsumerProfileProvider);

    // 다른 탭으로 이동하면 Loop 자동 정지 — IndexedStack은 이 화면을 dispose하지
    // 않으므로 currentTabIndexProvider로 탭 이탈을 감지해야 한다.
    ref.listen<int>(currentTabIndexProvider, (prev, next) {
      if (next != _kListenTabIndex && _loop) _setLoop(false);
    });

    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      body: SafeArea(
        child: Column(
          children: [
            const TunaiTopBar(subtitle: 'LISTEN'),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 6, 24, 0),
              child: Builder(builder: (ctx) {
                final ko = Localizations.localeOf(ctx).languageCode == 'ko';
                return Text(
                  ko ? '현재 사운드 프로파일로 들어보세요.' : 'Listen with your current Sound Profile.',
                  style: TextStyle(color: Colors.white.withValues(alpha: 0.3), fontSize: 11, height: 1.5),
                );
              }),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: PresetBar(onSave: _saveConsumerProfile),
            ),
            const SizedBox(height: 4),
            const _MasterVolumeSection(),
            const SizedBox(height: 4),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
                child: !hasBefore && activeConsumer != null
                    ? _ConsumerActiveView(profile: activeConsumer)
                    : !hasBefore
                        ? const _EmptyState()
                        : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                        const _CurrentProfileSection(),
                        const SizedBox(height: 16),
                        _AbToggle(
                          showAfter: _showAfter,
                          loop: _loop,
                          hasAfter: hasAfter,
                          onSelect: hasAfter ? (v) => setState(() { _showAfter = v; _setLoop(false); }) : null,
                          onLoopChanged: hasAfter ? _setLoop : null,
                        ),
                        const SizedBox(height: 12),
                        SectionCard(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                            Builder(builder: (ctx) {
                              final ko = Localizations.localeOf(ctx).languageCode == 'ko';
                              return Text(
                                _showAfter && hasAfter ? 'Acoustic Tune' : (ko ? '기본 사운드' : 'Original Sound'),
                                style: const TextStyle(color: Colors.white60, fontSize: 12, letterSpacing: 2),
                              );
                            }),
                            const SizedBox(height: 8),
                            SpectrumChart(
                              bins: (_showAfter && hasAfter ? snap.afterAi : snap.before) ?? const [],
                              peaks: const [],
                              showAxisLabels: false,
                              showTechnicalLabel: false,
                            ),
                          ]),
                        ),
                        const SizedBox(height: 20),
                        Builder(builder: (ctx) {
                          final ko = Localizations.localeOf(ctx).languageCode == 'ko';
                          return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(
                              ko ? '소리의 변화' : 'Sound Comparison',
                              style: const TextStyle(color: Colors.white38, fontSize: 11, letterSpacing: 2),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              ko
                                  ? '원래 소리와 TUNAI Sound Profile을 비교해 보세요.'
                                  : 'Compare the original sound with your TUNAI Sound Profile.',
                              style: TextStyle(color: Colors.white.withValues(alpha: 0.25), fontSize: 11, height: 1.4),
                            ),
                          ]);
                        }),
                        const SizedBox(height: 8),
                        SectionCard(child: _OverlayChart(snap: snap)),
                        const SizedBox(height: 8),
                        const _Legend(),
                      ]),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Listening Level ───────────────────────────────────────────

// Maps internal dB value to consumer level label.
// Internal range: -70 to 0 dB. Presets: -60 (Low), -50 (Comfortable), -40 (Lively).
String _levelLabel(double db, {required bool ko}) {
  if (db <= -55) return ko ? '낮게' : 'Low';
  if (db <= -45) return ko ? '편안하게' : 'Comfortable';
  return ko ? '크게' : 'Lively';
}

class _MasterVolumeSection extends ConsumerWidget {
  const _MasterVolumeSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final vol = ref.watch(masterVolumeProvider);
    final ctrl = ref.read(masterVolumeProvider.notifier);

    // Preset dB values kept internal; labels shown to consumer.
    const presets = [(-60.0, '낮게', 'Low'), (-50.0, '편안하게', 'Comfortable'), (-40.0, '크게', 'Lively')];

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Builder(builder: (ctx) {
        final isKo = Localizations.localeOf(ctx).languageCode == 'ko';
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  isKo ? '듣기 음량' : 'Listening Level',
                  style: const TextStyle(color: Colors.white54, fontSize: 11, letterSpacing: 2),
                ),
                const SizedBox(width: 12),
                Text(
                  isKo
                      ? '현재 음량: ${_levelLabel(vol, ko: true)}'
                      : 'Current level: ${_levelLabel(vol, ko: false)}',
                  style: const TextStyle(color: Colors.white70, fontSize: 11),
                ),
                const Spacer(),
                for (final (db, labelKo, labelEn) in presets) ...[
                  const SizedBox(width: 6),
                  GestureDetector(
                    onTap: () => ctrl.setVolume(db),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        border: Border.all(
                            color: vol == db ? Colors.white54 : Colors.white24, width: 0.5),
                        borderRadius: BorderRadius.circular(3),
                      ),
                      child: Text(
                        isKo ? labelKo : labelEn,
                        style: TextStyle(
                          color: vol == db ? Colors.white70 : Colors.white38,
                          fontSize: 10, letterSpacing: 0.5,
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
            SliderTheme(
              data: SliderTheme.of(context).copyWith(
                trackHeight: 1.5,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
                overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
                activeTrackColor: Colors.white54,
                inactiveTrackColor: Colors.white12,
                thumbColor: Colors.white,
                overlayColor: Colors.white12,
              ),
              child: Slider(
                value: vol,
                min: -70, max: 0,
                onChanged: (v) => ctrl.updateUiOnly(v),
                onChangeEnd: (v) => ctrl.setVolume(v),
              ),
            ),
          ],
        );
      }),
    );
  }
}

// ── Current Profile ──────────────────────────────────────────────────────────

class _CurrentProfileSection extends ConsumerWidget {
  const _CurrentProfileSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(appliedProfileProvider);
    final ko = Localizations.localeOf(context).languageCode == 'ko';

    if (profile == null) {
      return Container(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        decoration: BoxDecoration(
          color: const Color(0xFF111111),
          border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(
            ko ? '사운드 프로파일' : 'Sound Profile',
            style: TextStyle(color: Colors.white.withValues(alpha: 0.35), fontSize: 10, letterSpacing: 1.5),
          ),
          const SizedBox(height: 8),
          Text(
            ko ? '적용된 사운드 프로파일이 없습니다.' : 'No Sound Profile applied.',
            style: const TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.w300),
          ),
          const SizedBox(height: 4),
          Text(
            ko ? '공간 스캔으로 어쿠스틱 튠을 만들어 저장해보세요.' : 'Run a Room Scan to create your Acoustic Tune.',
            style: TextStyle(color: Colors.white.withValues(alpha: 0.4), fontSize: 12, height: 1.5),
          ),
        ]),
      );
    }

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.03),
        border: Border.all(color: Colors.white24),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Text(
            ko ? '현재 사운드 프로파일' : 'Current Sound Profile',
            style: TextStyle(color: Colors.white.withValues(alpha: 0.35), fontSize: 10, letterSpacing: 1.5),
          ),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
            decoration: BoxDecoration(
              color: const Color(0xFF69F0AE).withValues(alpha: 0.12),
              border: Border.all(color: const Color(0xFF69F0AE).withValues(alpha: 0.35)),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              ko ? '공간 맞춤' : 'Room Matched',
              style: const TextStyle(color: Color(0xFF69F0AE), fontSize: 9, letterSpacing: 1),
            ),
          ),
        ]),
        const SizedBox(height: 10),
        Text(
          profile.name,
          style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w300),
        ),
        const SizedBox(height: 8),
        Row(children: [
          _MetaChipListen(text: ko ? profile.roomTypeLabel : profile.roomTypeLabelEn),
          if (profile.soundScore != null) ...[
            const SizedBox(width: 8),
            _MetaChipListen(text: 'Score ${profile.soundScore}'),
          ],
        ]),
        const SizedBox(height: 12),
        const Divider(color: Colors.white10, height: 1),
        const SizedBox(height: 10),
        GestureDetector(
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const SpeakerHealthScreen()),
          ),
          child: Row(children: [
            Icon(Icons.health_and_safety_outlined, color: const Color(0xFF69F0AE).withValues(alpha: 0.6), size: 13),
            const SizedBox(width: 6),
            Text(
              ko ? '시스템 상태: 정상' : 'System Health: Normal',
              style: TextStyle(color: Colors.white.withValues(alpha: 0.4), fontSize: 11, letterSpacing: 0.5),
            ),
            const Spacer(),
            Icon(Icons.chevron_right, color: Colors.white.withValues(alpha: 0.2), size: 14),
          ]),
        ),
      ]),
    );
  }
}

class _MetaChipListen extends StatelessWidget {
  final String text;
  const _MetaChipListen({required this.text});
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
        decoration: BoxDecoration(
          border: Border.all(color: Colors.white12),
          borderRadius: BorderRadius.circular(3),
        ),
        child: Text(text, style: TextStyle(color: Colors.white.withValues(alpha: 0.4), fontSize: 10, letterSpacing: 0.5)),
      );
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();
  @override
  Widget build(BuildContext context) {
    final ko = Localizations.localeOf(context).languageCode == 'ko';
    return SectionCard(
      child: Column(children: [
        const Icon(Icons.graphic_eq, color: Colors.white24, size: 32),
        const SizedBox(height: 12),
        Text(
          ko ? '아직 사운드 프로파일이 없습니다.' : 'No Sound Profile yet.',
          style: const TextStyle(color: Colors.white70, fontSize: 14, fontWeight: FontWeight.w300),
        ),
        const SizedBox(height: 8),
        Text(
          ko
              ? 'Room Scan을 완료한 후 Acoustic Tune을 만들어보세요.\n원본 사운드와 Acoustic Tune을 여기서 비교할 수 있습니다.'
              : 'Run a Room Scan first, then create an Acoustic Tune.\nOriginal Sound and Acoustic Tune will appear here for comparison.',
          style: const TextStyle(color: Colors.white38, fontSize: 12, height: 1.6),
          textAlign: TextAlign.center,
        ),
      ]),
    );
  }
}

// ── Consumer Sound Profile active view ───────────────────────────────────────

class _ConsumerActiveView extends ConsumerWidget {
  final ConsumerSoundProfile profile;
  const _ConsumerActiveView({required this.profile});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ko = Localizations.localeOf(context).languageCode == 'ko';
    final ble = ref.watch(bleProvider);
    final isConnected = ble.connection == BleConnectionState.connected;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Container(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.03),
          border: Border.all(color: Colors.white24),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Text(
              ko ? '현재 사운드 프로파일' : 'Current Sound Profile',
              style: TextStyle(color: Colors.white.withValues(alpha: 0.35), fontSize: 10, letterSpacing: 1.5),
            ),
            const Spacer(),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
              decoration: BoxDecoration(
                color: const Color(0xFF69F0AE).withValues(alpha: 0.12),
                border: Border.all(color: const Color(0xFF69F0AE).withValues(alpha: 0.35)),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                ko ? '사용 중' : 'Active',
                style: const TextStyle(color: Color(0xFF69F0AE), fontSize: 9, letterSpacing: 1),
              ),
            ),
          ]),
          const SizedBox(height: 10),
          Text(profile.name,
              style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w300)),
          const SizedBox(height: 8),
          Row(children: [
            _MetaChipListen(text: ko ? profile.roomTypeLabel : profile.roomTypeLabelEn),
            const SizedBox(width: 8),
            _MetaChipListen(text: ko ? '마이크: ${profile.micLabel(ko)}' : 'Mic: ${profile.micLabel(ko)}'),
          ]),
        ]),
      ),
      const SizedBox(height: 20),
      if (profile.soundScoreBefore != null && profile.soundScoreAfter != null) ...[
        _ListenSoundScoreCard(
          ko: ko,
          before: profile.soundScoreBefore!,
          after: profile.soundScoreAfter!,
        ),
        const SizedBox(height: 20),
      ],
      Text(
        ko ? '적용된 조정' : 'Applied adjustments',
        style: TextStyle(color: Colors.white.withValues(alpha: 0.35), fontSize: 11, letterSpacing: 1.5),
      ),
      const SizedBox(height: 12),
      ...profile.resultCards.map((card) => Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        decoration: BoxDecoration(
          border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Container(width: 6, height: 6,
                decoration: const BoxDecoration(color: Color(0xFF69F0AE), shape: BoxShape.circle)),
            const SizedBox(width: 8),
            Text(card.label(ko: ko),
                style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w300)),
          ]),
          const SizedBox(height: 6),
          Text(card.description(ko: ko),
              style: TextStyle(color: Colors.white.withValues(alpha: 0.4), fontSize: 12, height: 1.5)),
        ]),
      )),
      if (!isConnected) ...[
        const SizedBox(height: 8),
        Container(
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
                    ? 'Sound Profile이 준비되었습니다. 스피커를 연결하면 이 설정으로 들을 수 있습니다.'
                    : 'Sound Profile is ready. Connect your speaker to listen with this profile.',
                style: const TextStyle(color: Colors.white38, fontSize: 11, height: 1.5),
              ),
            ),
          ]),
        ),
      ],
    ]);
  }
}

class _ListenSoundScoreCard extends StatelessWidget {
  final bool ko;
  final int before;
  final int after;
  const _ListenSoundScoreCard({required this.ko, required this.before, required this.after});

  @override
  Widget build(BuildContext context) {
    final improvement = after - before;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: const Color(0xFF69F0AE).withValues(alpha: 0.04),
        border: Border.all(color: const Color(0xFF69F0AE).withValues(alpha: 0.18)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(
            'Sound Score',
            style: TextStyle(color: Colors.white.withValues(alpha: 0.35), fontSize: 10, letterSpacing: 1.5),
          ),
          const SizedBox(height: 6),
          Row(crossAxisAlignment: CrossAxisAlignment.baseline, textBaseline: TextBaseline.alphabetic, children: [
            Text('$before', style: TextStyle(color: Colors.white.withValues(alpha: 0.4), fontSize: 18, fontWeight: FontWeight.w300)),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Icon(Icons.arrow_forward, color: Colors.white.withValues(alpha: 0.25), size: 12),
            ),
            Text('$after', style: const TextStyle(color: Color(0xFF69F0AE), fontSize: 22, fontWeight: FontWeight.w300)),
          ]),
        ]),
        const Spacer(),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: const Color(0xFF69F0AE).withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(
            '+$improvement',
            style: const TextStyle(color: Color(0xFF69F0AE), fontSize: 13, fontWeight: FontWeight.w500),
          ),
        ),
      ]),
    );
  }
}

class _AbToggle extends StatelessWidget {
  final bool showAfter;
  final bool loop;
  final bool hasAfter;
  final ValueChanged<bool>? onSelect;
  final ValueChanged<bool>? onLoopChanged;
  const _AbToggle({required this.showAfter, required this.loop, required this.hasAfter, this.onSelect, this.onLoopChanged});

  @override
  Widget build(BuildContext context) {
    return Row(children: [
      Expanded(
        child: Row(children: [
          Expanded(child: Builder(builder: (ctx) {
            final ko = Localizations.localeOf(ctx).languageCode == 'ko';
            return _AbButton(label: ko ? '기본 사운드' : 'ORIGINAL SOUND', selected: !showAfter, onTap: onSelect == null ? null : () => onSelect!(false));
          })),
          const SizedBox(width: 8),
          Expanded(child: _AbButton(label: 'ACOUSTIC TUNE', selected: showAfter, enabled: hasAfter, onTap: onSelect == null ? null : () => onSelect!(true))),
        ]),
      ),
      const SizedBox(width: 12),
      GestureDetector(
        onTap: onLoopChanged == null ? null : () => onLoopChanged!(!loop),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            border: Border.all(color: loop ? Colors.white : Colors.white24),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Row(children: [
            Icon(loop ? Icons.pause_circle_outline : Icons.play_circle_outline,
                color: loop ? Colors.white : Colors.white38, size: 14),
            const SizedBox(width: 4),
            Text('LOOP', style: TextStyle(color: loop ? Colors.white : Colors.white38, fontSize: 10, letterSpacing: 1)),
          ]),
        ),
      ),
    ]);
  }
}

class _AbButton extends StatelessWidget {
  final String label;
  final bool selected;
  final bool enabled;
  final VoidCallback? onTap;
  const _AbButton({required this.label, required this.selected, this.enabled = true, this.onTap});

  @override
  Widget build(BuildContext context) {
    final active = enabled && onTap != null;
    return GestureDetector(
      onTap: active ? onTap : null,
      child: Container(
        height: 40,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          border: Border.all(color: selected && active ? Colors.white : Colors.white24),
          borderRadius: BorderRadius.circular(6),
          color: selected && active ? Colors.white.withValues(alpha: 0.08) : Colors.transparent,
        ),
        child: Text(label,
            style: TextStyle(color: !active ? Colors.white12 : selected ? Colors.white : Colors.white54, fontSize: 12, letterSpacing: 2)),
      ),
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend();
  @override
  Widget build(BuildContext context) {
    final ko = Localizations.localeOf(context).languageCode == 'ko';
    return Row(children: [
      _LegendDot(color: Colors.white38, label: ko ? '원본 사운드' : 'Original Sound'),
      const SizedBox(width: 16),
      const _LegendDot(color: Colors.greenAccent, label: 'Acoustic Tune'),
      const SizedBox(width: 16),
      _LegendDot(color: Colors.lightBlueAccent, label: ko ? '현재' : 'Current'),
    ]);
  }
}

class _LegendDot extends StatelessWidget {
  final Color color;
  final String label;
  const _LegendDot({required this.color, required this.label});
  @override
  Widget build(BuildContext context) {
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Container(width: 8, height: 8, decoration: BoxDecoration(shape: BoxShape.circle, color: color)),
      const SizedBox(width: 6),
      Text(label, style: const TextStyle(color: Colors.white38, fontSize: 10)),
    ]);
  }
}

/// 회색(Before) · 초록(After AI) · 파랑(현재) 3색 오버레이
class _OverlayChart extends StatelessWidget {
  final SpectrumSnapshot snap;
  const _OverlayChart({required this.snap});

  List<FlSpot> _spotsOf(List<FrequencyBin>? bins) {
    if (bins == null) return const [];
    return bins
        .where((b) => b.frequency >= 20 && b.frequency <= 500)
        .map((b) => FlSpot(b.frequency, b.magnitude.clamp(-60.0, 20.0)))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final beforeSpots = _spotsOf(snap.before);
    final afterSpots = _spotsOf(snap.afterAi);
    final currentSpots = _spotsOf(snap.current);
    if (beforeSpots.isEmpty) return const SizedBox.shrink();

    return SizedBox(
      height: 260,
      child: LineChart(LineChartData(
        backgroundColor: Colors.transparent,
        gridData: FlGridData(show: true, drawVerticalLine: false, getDrawingHorizontalLine: (_) => const FlLine(color: Colors.white10, strokeWidth: 0.5)),
        titlesData: const FlTitlesData(
          bottomTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
          leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
          topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
        ),
        borderData: FlBorderData(show: false),
        minX: 20, maxX: 500, minY: -60, maxY: 20,
        lineBarsData: [
          LineChartBarData(spots: beforeSpots, isCurved: true, color: Colors.white38, barWidth: 1.2, dotData: const FlDotData(show: false)),
          if (afterSpots.isNotEmpty)
            LineChartBarData(spots: afterSpots, isCurved: true, color: Colors.greenAccent, barWidth: 1.2, dotData: const FlDotData(show: false)),
          if (currentSpots.isNotEmpty)
            LineChartBarData(spots: currentSpots, isCurved: true, color: Colors.lightBlueAccent, barWidth: 1.0, dotData: const FlDotData(show: false)),
        ],
      )),
    );
  }
}

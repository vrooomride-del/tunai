import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../measurement/measurement_controller.dart';
import '../ble/ble_controller.dart';
import '../../core/speaker_profile.dart';
import '../../core/install_location.dart';
import '../../core/spectrum_snapshot.dart';
import '../../shared/widgets.dart';
import '../../shared/spectrum_chart.dart';
import '../../shared/preset_bar.dart';

/// MEASURE 탭 — 공간 측정 UX.
/// 측정 완료 시 [onMeasured]로 AI 탭 자동 전환을 요청한다.
class MeasureScreen extends ConsumerWidget {
  final VoidCallback onMeasured;
  const MeasureScreen({super.key, required this.onMeasured});

  bool _isKo(BuildContext ctx) =>
      Localizations.localeOf(ctx).languageCode == 'ko';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mState = ref.watch(measurementProvider);
    final bState = ref.watch(bleProvider);
    final ko = _isKo(context);

    ref.listen<MeasurementState>(measurementProvider, (prev, next) {
      if (next.step == MeasurementStep.done && prev?.step != MeasurementStep.done) {
        if (next.scmsBins.isNotEmpty) {
          ref.read(spectrumSnapshotProvider.notifier).setBefore(next.scmsBins);
        }
        onMeasured();
      }
    });

    final step = mState.step;
    final isRunning = step != MeasurementStep.idle
        && step != MeasurementStep.done && step != MeasurementStep.error;
    final isConnected = bState.connection == BleConnectionState.connected;

    // 측정 중 → 진행 화면
    if (isRunning) {
      return _MeasuringView(mState: mState, ko: ko);
    }

    // 측정 완료 → 결과 화면 (onMeasured로 AI 탭 이동 전까지 잠깐 표시)
    if (step == MeasurementStep.done) {
      return _ResultView(
        mState: mState,
        ko: ko,
        onOptimize: onMeasured,
        onReMeasure: () => ref.read(measurementProvider.notifier).reset(),
      );
    }

    // 측정 대기 → Ready 화면
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      body: SafeArea(
        child: Column(
          children: [
            // ADVANCED 기능용 PresetBar + 위치 선택은 스크롤 영역에
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(32, 0, 32, 32),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 48),
                    Text(
                      ko ? 'TUNAI가 당신의 공간을 들어봅니다.' : 'Let TUNAI listen to your room.',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 26,
                        fontWeight: FontWeight.w300,
                        height: 1.35,
                        letterSpacing: -0.2,
                      ),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      ko
                          ? '평소 듣는 자리에 앉아 주세요.\n잠시 공간을 조용히 유지해 주세요.'
                          : 'Sit where you usually listen.\nKeep the room quiet for a moment.',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.45),
                        fontSize: 14,
                        height: 1.65,
                      ),
                    ),
                    const SizedBox(height: 40),
                    const _LocationPicker(),
                    if (!isConnected) ...[
                      const SizedBox(height: 20),
                      Text(
                        ko ? '스피커를 먼저 연결해주세요 (CONNECT 탭)' : 'Connect your speaker first (CONNECT tab)',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.35),
                          fontSize: 12,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ],
                    if (step == MeasurementStep.error && mState.error != null) ...[
                      const SizedBox(height: 16),
                      Text(
                        mState.error!,
                        style: const TextStyle(color: Color(0xFFFF5252), fontSize: 13, height: 1.5),
                      ),
                    ],
                    const SizedBox(height: 40),
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 0),
                      child: PresetBar(),
                    ),
                  ],
                ),
              ),
            ),

            // ── 하단 버튼 ────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(32, 0, 32, 40),
              child: _MeasureButton(
                ko: ko,
                isConnected: isConnected,
                onTap: isConnected
                    ? () => ref
                        .read(measurementProvider.notifier)
                        .startMeasurement(
                          speakerProfile: ref.read(speakerProfileProvider),
                        )
                    : null,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── 측정 진행 화면 (Screen 7) ─────────────────────────────────────────────────
class _MeasuringView extends StatefulWidget {
  final MeasurementState mState;
  final bool ko;
  const _MeasuringView({required this.mState, required this.ko});
  @override
  State<_MeasuringView> createState() => _MeasuringViewState();
}

class _MeasuringViewState extends State<_MeasuringView> {
  int _phaseIdx = 0;
  late final List<(String, String)> _phases;

  @override
  void initState() {
    super.initState();
    _phases = const [
      ('Checking bass response', '저역 반응을 확인하고 있습니다'),
      ('Detecting room reflections', '공간 반사를 감지하고 있습니다'),
      ('Balancing stereo image', '스테레오 이미지를 정렬하고 있습니다'),
      ('Creating your Acoustic Tune', '어쿠스틱 튠을 생성하고 있습니다'),
    ];
    _tick();
  }

  Future<void> _tick() async {
    for (var i = 0; i < _phases.length; i++) {
      await Future.delayed(const Duration(seconds: 2));
      if (!mounted) return;
      setState(() => _phaseIdx = i);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ko = widget.ko;
    final progress = ((_phaseIdx + 1) / _phases.length).clamp(0.0, 1.0);
    final phaseText = ko ? _phases[_phaseIdx].$2 : _phases[_phaseIdx].$1;

    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(32, 60, 32, 40),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                ko ? '공간의 소리를 이해하고 있습니다...' : 'TUNAI is understanding your room...',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 26,
                  fontWeight: FontWeight.w300,
                  height: 1.35,
                ),
              ),
              const Spacer(flex: 2),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 400),
                child: Text(
                  phaseText,
                  key: ValueKey(_phaseIdx),
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.55),
                    fontSize: 14,
                    height: 1.5,
                  ),
                ),
              ),
              const SizedBox(height: 20),
              LinearProgressIndicator(
                value: progress,
                backgroundColor: Colors.white12,
                color: Colors.white38,
                minHeight: 1.5,
              ),
              if (widget.mState.message.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(
                  widget.mState.message,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.25),
                    fontSize: 11,
                  ),
                ),
              ],
              const Spacer(flex: 3),
            ],
          ),
        ),
      ),
    );
  }
}

// ── 측정 결과 화면 (Screen 8) ─────────────────────────────────────────────────
class _ResultView extends StatelessWidget {
  final MeasurementState mState;
  final bool ko;
  final VoidCallback onOptimize;
  final VoidCallback onReMeasure;
  const _ResultView({
    required this.mState,
    required this.ko,
    required this.onOptimize,
    required this.onReMeasure,
  });

  @override
  Widget build(BuildContext context) {
    final peaks = mState.peaks;
    // placeholder 결과 카드 (peaks 없으면 기본 설명)
    final findings = peaks.isNotEmpty
        ? peaks
            .take(3)
            .map((p) => ko
                ? '${p.frequency.toStringAsFixed(0)}Hz 부근 ${p.gain < 0 ? '딥' : '피크'} ${p.gain.toStringAsFixed(1)}dB 감지'
                : '${p.gain < 0 ? 'Dip' : 'Peak'} of ${p.gain.toStringAsFixed(1)}dB near ${p.frequency.toStringAsFixed(0)}Hz')
            .toList()
        : [
            ko ? '90Hz 부근 저역 부밍 감지' : 'Bass buildup near 90Hz',
            ko ? '180Hz 부근 책상 반사 감지' : 'Desk reflection around 180Hz',
            ko ? '좌우 밸런스 차이 감지' : 'Left/right balance difference',
          ];

    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(32, 60, 32, 32),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      ko
                          ? 'TUNAI가 공간이 소리에\n미치는 영향을 찾았습니다.'
                          : 'TUNAI found what your\nroom is doing to the sound.',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 26,
                        fontWeight: FontWeight.w300,
                        height: 1.35,
                        letterSpacing: -0.2,
                      ),
                    ),
                    const SizedBox(height: 36),
                    ...findings.map((f) => _FindingCard(text: f)),
                    if (mState.scmsBins.isNotEmpty) ...[
                      const SizedBox(height: 24),
                      SpectrumChart(bins: mState.scmsBins, peaks: mState.peaks),
                    ],
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(32, 0, 32, 16),
              child: _BigButton(
                label: ko ? '어쿠스틱 튠 생성' : 'Create Acoustic Tune',
                onTap: onOptimize,
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(32, 0, 32, 32),
              child: GestureDetector(
                onTap: onReMeasure,
                child: Center(
                  child: Text(
                    ko ? '다시 공간 스캔' : 'Scan again',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.3),
                      fontSize: 13,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FindingCard extends StatelessWidget {
  final String text;
  const _FindingCard({required this.text});
  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.white12),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(children: [
        Container(
          width: 6,
          height: 6,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.5),
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Text(
            text,
            style: TextStyle(color: Colors.white.withValues(alpha: 0.7), fontSize: 13, height: 1.4),
          ),
        ),
      ]),
    );
  }
}

// ── 공용 위젯 ─────────────────────────────────────────────────────────────────
class _MeasureButton extends StatelessWidget {
  final bool ko;
  final bool isConnected;
  final VoidCallback? onTap;
  const _MeasureButton({required this.ko, required this.isConnected, this.onTap});
  @override
  Widget build(BuildContext context) {
    return _BigButton(
      label: ko ? '공간 스캔 시작' : 'Start Room Scan',
      onTap: onTap,
    );
  }
}

class _BigButton extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;
  const _BigButton({required this.label, this.onTap});
  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 18),
        decoration: BoxDecoration(
          color: enabled ? Colors.white : Colors.white12,
          borderRadius: BorderRadius.circular(4),
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: TextStyle(
            color: enabled ? Colors.black : Colors.white24,
            fontSize: 14,
            fontWeight: FontWeight.w500,
            letterSpacing: 1.5,
          ),
        ),
      ),
    );
  }
}

/// 🏠 설치 위치를 먼저 선택 — 방이 Driver보다 중요하다
class _LocationPicker extends ConsumerWidget {
  const _LocationPicker();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selected = ref.watch(installLocationProvider);
    final ko = Localizations.localeOf(context).languageCode == 'ko';
    return SectionCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('스피커가 놓인 공간을 알려주세요', style: TextStyle(color: Colors.white, fontSize: 14, letterSpacing: 0.5)),
        const SizedBox(height: 4),
        const Text('TUNAI가 이 정보를 바탕으로 소리를 분석합니다.', style: TextStyle(color: Colors.white38, fontSize: 11)),
        const SizedBox(height: 12),
        ...InstallLocation.values.map((loc) {
          final isSelected = selected == loc;
          return GestureDetector(
            onTap: () => ref.read(installLocationProvider.notifier).state = loc,
            child: Container(
              margin: const EdgeInsets.only(bottom: 6),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                border: Border.all(color: isSelected ? Colors.white : Colors.white12),
                borderRadius: BorderRadius.circular(6),
                color: isSelected ? Colors.white.withValues(alpha: 0.05) : Colors.transparent,
              ),
              child: Row(children: [
                Icon(isSelected ? Icons.radio_button_checked : Icons.radio_button_off,
                    color: isSelected ? Colors.white : Colors.white24, size: 16),
                const SizedBox(width: 10),
                Text(ko ? loc.label : loc.labelEn, style: TextStyle(color: isSelected ? Colors.white : Colors.white60, fontSize: 13)),
              ]),
            ),
          );
        }),
        if (selected == InstallLocation.custom) ...[
          const SizedBox(height: 6),
          TextField(
            style: const TextStyle(color: Colors.white, fontSize: 13),
            decoration: const InputDecoration(
              hintText: '예: 침실 책장 위, 캠핑카 등',
              hintStyle: TextStyle(color: Colors.white24),
              enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: Colors.white24)),
              focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: Colors.white54)),
              contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            ),
            onChanged: (v) => ref.read(installLocationCustomTextProvider.notifier).state = v,
          ),
        ],
      ]),
    );
  }
}


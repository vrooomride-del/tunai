import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../measurement/measurement_controller.dart';
import '../ble/ble_controller.dart';
import '../../core/speaker_profile.dart';
import '../../core/install_location.dart';
import '../../core/spectrum_snapshot.dart';
import '../../core/mic_calibration_service.dart';
import '../../core/room_scan_result.dart';
import '../../core/room_measurement.dart';
import '../../shared/widgets.dart';
import '../../shared/acoustic_timeline.dart';

/// ROOM 탭 — 공간 측정 UX.
/// 측정 완료 시 [onMeasured]로 TUNE 탭 자동 전환을 요청한다.
class MeasureScreen extends ConsumerStatefulWidget {
  final VoidCallback onMeasured;
  const MeasureScreen({super.key, required this.onMeasured});
  @override
  ConsumerState<MeasureScreen> createState() => _MeasureScreenState();
}

class _MeasureScreenState extends ConsumerState<MeasureScreen>
    with WidgetsBindingObserver {
  // true = show Mic Check card before scan starts
  bool _showMicCheck = false;
  bool _committingResult = false;
  late final MeasurementController _measurementController;

  bool get _isKo => Localizations.localeOf(context).languageCode == 'ko';

  @override
  void initState() {
    super.initState();
    _measurementController = ref.read(measurementProvider.notifier);
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) {
      _measurementController.cancelLoop();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _measurementController.cancelLoop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final mState = ref.watch(measurementProvider);
    final bState = ref.watch(bleProvider);
    final ko = _isKo;
    final step = mState.step;
    final isRunning = step != MeasurementStep.idle
        && step != MeasurementStep.done && step != MeasurementStep.error;
    final isConnected = bState.connection == BleConnectionState.connected;

    ref.listen<MeasurementState>(measurementProvider, (prev, next) async {
      if (next.step == MeasurementStep.done && prev?.step != MeasurementStep.done) {
        final measurement = next.measurement;
        if (_committingResult || measurement == null || !measurement.isValid) {
          return;
        }
        _committingResult = true;
        if (next.scmsBins.isNotEmpty) {
          ref.read(spectrumSnapshotProvider.notifier).setBefore(next.scmsBins);
        }
        try {
          await RoomMeasurementStore.save(measurement);
          await ref
              .read(roomScanResultProvider.notifier)
              .saveResult(RoomScanResult.fromMeasurement(measurement));
          if (mounted) widget.onMeasured();
        } catch (_) {
          if (mounted) {
            ref.read(measurementProvider.notifier).markPersistenceFailure();
          }
        } finally {
          _committingResult = false;
        }
      }
    });

    ref.listen<BleState>(bleProvider, (previous, next) {
      final wasConnected = previous?.connection == BleConnectionState.connected;
      if (wasConnected &&
          next.connection != BleConnectionState.connected &&
          isRunning) {
        ref.read(measurementProvider.notifier).cancelLoop();
      }
    });

    if (isRunning) {
      return _MeasuringView(
        mState: mState,
        ko: ko,
        onCancel: () => ref.read(measurementProvider.notifier).cancelLoop(),
      );
    }

    if (step == MeasurementStep.done) {
      return _ResultView(
        mState: mState,
        ko: ko,
        onOptimize: widget.onMeasured,
        onReMeasure: () {
          ref.read(measurementProvider.notifier).reset();
          setState(() => _showMicCheck = false);
        },
      );
    }

    // ── Ready state — show Mic Check or main ready screen ──────────────────
    if (_showMicCheck) {
      return _MicCheckView(
        ko: ko,
        onContinue: () {
          setState(() => _showMicCheck = false);
          ref.read(measurementProvider.notifier).startMeasurement(
            speakerProfile: ref.read(speakerProfileProvider),
          );
        },
        onBack: () => setState(() => _showMicCheck = false),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(32, 0, 32, 32),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 48),
                    Text(
                      ko ? '당신의 공간이 소리를 결정합니다.' : 'Your room shapes your sound.',
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
                          ? '벽, 가구, 스피커 배치에 따라 소리는 달라집니다.\n\nTUNAI가 공간을 분석하고 당신만의 사운드를 만들어드립니다.'
                          : 'Walls, furniture, and placement affect how your speaker sounds.\n\nTUNAI analyzes your listening space and creates a personalized sound profile.',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.45),
                        fontSize: 14,
                        height: 1.65,
                      ),
                    ),
                    const SizedBox(height: 40),
                    const _LocationPicker(),
                    const SizedBox(height: 20),
                    // Mic status card
                    _MicStatusCard(ko: ko),
                    if (!isConnected) ...[
                      const SizedBox(height: 16),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.white12),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Row(children: [
                          const Icon(Icons.bluetooth_disabled, color: Colors.white24, size: 16),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              ko
                                  ? '스피커를 먼저 연결해주세요 (CONNECT 탭)'
                                  : 'Connect your speaker first (CONNECT tab)',
                              style: const TextStyle(color: Colors.white38, fontSize: 12),
                            ),
                          ),
                        ]),
                      ),
                    ],
                    if (step == MeasurementStep.error && mState.error != null) ...[
                      const SizedBox(height: 16),
                      Text(mState.error!,
                          style: const TextStyle(color: Color(0xFFFF5252), fontSize: 13, height: 1.5)),
                    ],
                    const SizedBox(height: 40),
                  ],
                ),
              ),
            ),
            // ── 하단 버튼 ────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(32, 0, 32, 40),
              child: _BigButton(
                label: ko ? '공간 분석 시작' : 'Start Room Analysis',
                onTap: isConnected
                    ? () => setState(() => _showMicCheck = true)
                    : null,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Mic Check step ─────────────────────────────────────────────────────────────
class _MicCheckView extends ConsumerWidget {
  final bool ko;
  final VoidCallback onContinue;
  final VoidCallback onBack;
  const _MicCheckView({required this.ko, required this.onContinue, required this.onBack});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final micAsync = ref.watch(micCalibrationProfileProvider);
    final mic = micAsync.valueOrNull;

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
                      ko ? '휴대폰 마이크 확인' : 'Phone Mic Check',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 26,
                        fontWeight: FontWeight.w300,
                        height: 1.35,
                      ),
                    ),
                    const SizedBox(height: 32),
                    // Mic status
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.white12),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        PhoneMicCheckStatusLine(
                          status: mic != null
                              ? mic.statusLabel(ko: ko)
                              : (ko ? '마이크 확인 중...' : 'Checking microphone...'),
                        ),
                        if (mic != null) ...[
                          const SizedBox(height: 8),
                          Text(
                            mic.confidenceLabel(ko: ko),
                            style: const TextStyle(color: Colors.white38, fontSize: 11),
                          ),
                        ],
                      ]),
                    ),
                    const SizedBox(height: 28),
                    // Instructions
                    _Instruction(
                      icon: Icons.place_outlined,
                      text: ko
                          ? '휴대폰을 청취 위치에 놓아주세요.'
                          : 'Place your phone at the listening position.',
                    ),
                    _Instruction(
                      icon: Icons.back_hand_outlined,
                      text: ko
                          ? '마이크를 손으로 가리지 마세요.'
                          : 'Keep the microphone uncovered.',
                    ),
                    _Instruction(
                      icon: Icons.volume_off_outlined,
                      text: ko
                          ? '가능한 조용한 상태에서 진행해 주세요.'
                          : 'Make the room as quiet as possible.',
                    ),
                    const SizedBox(height: 32),
                    // Noise level placeholder
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.white12),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Row(children: [
                        const Icon(Icons.sensors, color: Colors.white24, size: 14),
                        const SizedBox(width: 10),
                        Text(
                          ko ? '주변 소음 감지 — 준비 중' : 'Ambient noise detection — coming soon',
                          style: const TextStyle(color: Colors.white24, fontSize: 11),
                        ),
                      ]),
                    ),
                    const SizedBox(height: 28),
                    // Mic Strategy
                    ConsumerMicStrategySection(ko: ko),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(32, 0, 32, 16),
              child: _BigButton(
                label: ko ? '공간 분석 시작' : 'Start Room Analysis',
                onTap: onContinue,
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(32, 0, 32, 32),
              child: GestureDetector(
                onTap: onBack,
                child: Center(
                  child: Text(
                    ko ? '뒤로' : 'Back',
                    style: const TextStyle(color: Colors.white30, fontSize: 13),
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

class _Instruction extends StatelessWidget {
  final IconData icon;
  final String text;
  const _Instruction({required this.icon, required this.text});
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 14),
    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Icon(icon, color: Colors.white38, size: 16),
      const SizedBox(width: 12),
      Expanded(
        child: Text(text,
            style: TextStyle(
                color: Colors.white.withValues(alpha: 0.6), fontSize: 13, height: 1.5)),
      ),
    ]),
  );
}

// ── Mic status compact card for the Ready screen ───────────────────────────────
class _MicStatusCard extends ConsumerWidget {
  final bool ko;
  const _MicStatusCard({required this.ko});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final micAsync = ref.watch(micCalibrationProfileProvider);
    return micAsync.when(
      data: (mic) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        decoration: BoxDecoration(
          border: Border.all(color: Colors.white12),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(children: [
          const Icon(Icons.mic, color: Colors.white38, size: 14),
          const SizedBox(width: 10),
          Expanded(child: Text(
            mic.statusLabel(ko: ko),
            style: const TextStyle(color: Colors.white54, fontSize: 11),
          )),
        ]),
      ),
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
    );
  }
}

// ── 측정 진행 화면 ─────────────────────────────────────────────────────────────
class _MeasuringView extends StatefulWidget {
  final MeasurementState mState;
  final bool ko;
  final VoidCallback onCancel;
  const _MeasuringView({
    required this.mState,
    required this.ko,
    required this.onCancel,
  });
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
      ('Creating Your Sound', '나만의 사운드를 생성하고 있습니다'),
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
              GestureDetector(
                onTap: widget.onCancel,
                child: Center(
                  child: Text(
                    ko ? '취소' : 'Cancel',
                    style: const TextStyle(color: Colors.white38, fontSize: 13),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── 측정 결과 화면 ─────────────────────────────────────────────────────────────
class _ResultView extends ConsumerWidget {
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
  Widget build(BuildContext context, WidgetRef ref) {
    final result = ref.watch(roomScanResultProvider);
    final cards = result?.cards ?? const <RoomScanResultCard>[];

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
                    // Listening Environment Summary — consumer-safe, no Hz/dB/chart
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.white12),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Row(children: [
                        const Icon(Icons.check_circle_outline, color: Color(0xFF69F0AE), size: 14),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            ko
                                ? 'TUNAI가 공간의 소리 특성을 정리했습니다.'
                                : 'TUNAI summarized your room\'s sound characteristics.',
                            style: const TextStyle(color: Colors.white54, fontSize: 12, height: 1.4),
                          ),
                        ),
                      ]),
                    ),
                    const SizedBox(height: 24),
                    AcousticTimeline(
                      currentStep: AcousticTimelineStep.acousticTune,
                      ko: ko,
                    ),
                    const SizedBox(height: 24),
                    Text(
                      ko ? '청취 환경 요약' : 'Listening Environment Summary',
                      style: TextStyle(color: Colors.white.withValues(alpha: 0.35), fontSize: 11, letterSpacing: 1.5),
                    ),
                    const SizedBox(height: 10),
                    ...cards.map((card) => _ResultCard(card: card, ko: ko)),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(32, 0, 32, 16),
              child: _BigButton(
                label: ko ? '나만의 사운드 생성' : 'Create Your Sound',
                onTap: onOptimize,
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(32, 0, 32, 32),
              child: GestureDetector(
                onTap: onReMeasure,
                child: Center(
                  child: Text(
                    ko ? '다시 공간 분석' : 'Scan again',
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

class _ResultCard extends StatelessWidget {
  final RoomScanResultCard card;
  final bool ko;
  const _ResultCard({required this.card, required this.ko});
  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: 10),
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    decoration: BoxDecoration(
      border: Border.all(color: Colors.white12),
      borderRadius: BorderRadius.circular(6),
    ),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(card.label(ko: ko),
          style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w400)),
      const SizedBox(height: 4),
      Text(card.description(ko: ko),
          style: TextStyle(color: Colors.white.withValues(alpha: 0.45), fontSize: 12, height: 1.4)),
    ]),
  );
}

// ── Mic Strategy Section ──────────────────────────────────────────────────────

@visibleForTesting
class PhoneMicCheckStatusLine extends StatelessWidget {
  final String status;
  const PhoneMicCheckStatusLine({super.key, required this.status});

  @override
  Widget build(BuildContext context) => Row(children: [
    const Icon(Icons.mic, color: Colors.white54, size: 16),
    const SizedBox(width: 10),
    Expanded(
      child: Text(
        status,
        softWrap: true,
        style: const TextStyle(color: Colors.white, fontSize: 13),
      ),
    ),
  ]);
}

class ConsumerMicStrategySection extends StatelessWidget {
  final bool ko;
  const ConsumerMicStrategySection({super.key, required this.ko});

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(
        ko ? '측정 마이크' : 'Measurement Mic',
        style: TextStyle(color: Colors.white.withValues(alpha: 0.35), fontSize: 11, letterSpacing: 1.5),
      ),
      const SizedBox(height: 10),
      // Phone Mic — default, active
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          border: Border.all(color: Colors.white38),
          borderRadius: BorderRadius.circular(6),
          color: Colors.white.withValues(alpha: 0.04),
        ),
        child: LayoutBuilder(builder: (context, constraints) {
          final details = Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Phone Mic', style: TextStyle(color: Colors.white, fontSize: 13)),
            const SizedBox(height: 2),
            Text(ko ? '빠른 측정에 적합합니다.' : 'Best for quick setup.',
              style: TextStyle(color: Colors.white.withValues(alpha: 0.45), fontSize: 11, height: 1.4)),
          ]));
          final badge = Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
            decoration: BoxDecoration(
              color: const Color(0xFF69F0AE).withValues(alpha: 0.12),
              border: Border.all(color: const Color(0xFF69F0AE).withValues(alpha: 0.35)),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              ko ? '사용 중' : 'Active',
              maxLines: 1,
              style: const TextStyle(color: Color(0xFF69F0AE), fontSize: 9, letterSpacing: 1),
            ),
          );
          final detailsRow = Row(children: [
            const Icon(Icons.smartphone, color: Colors.white70, size: 16),
            const SizedBox(width: 12),
            details,
          ]);
          if (constraints.maxWidth < 250) {
            return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              detailsRow,
              const SizedBox(height: 8),
              Align(alignment: Alignment.centerRight, child: badge),
            ]);
          }
          return Row(children: [
            const Icon(Icons.smartphone, color: Colors.white70, size: 16),
            const SizedBox(width: 12),
            details,
            const SizedBox(width: 8),
            badge,
          ]);
        }),
      ),
      const SizedBox(height: 6),
      // USB Measurement Mic — optional
      _MicOptionRow(
        ko: ko,
        icon: Icons.usb,
        nameEn: 'USB Measurement Mic',
        nameKo: 'USB Measurement Mic',
        descEn: 'Optional mode for more precise measurement.',
        descKo: '더 정확한 측정을 위한 옵션입니다.',
      ),
      const SizedBox(height: 6),
      // TUNAI CAL-MIC — optional
      _MicOptionRow(
        ko: ko,
        icon: Icons.mic_external_on,
        nameEn: 'TUNAI CAL-MIC',
        nameKo: 'TUNAI CAL-MIC',
        descEn: 'Supports automatic calibration.',
        descKo: '자동 캘리브레이션을 지원합니다.',
      ),
      const SizedBox(height: 12),
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          border: Border.all(color: Colors.white12),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(
          ko
              ? '정밀 측정을 원하시나요? 지원되는 USB 측정 마이크를 연결하면 Precision Scan을 사용할 수 있습니다.'
              : 'Want a more precise scan? Connect a supported USB measurement microphone for Precision Scan.',
          style: TextStyle(color: Colors.white.withValues(alpha: 0.35), fontSize: 11, height: 1.5),
        ),
      ),
    ]);
  }
}

class _MicOptionRow extends StatelessWidget {
  final bool ko;
  final IconData icon;
  final String nameEn;
  final String nameKo;
  final String descEn;
  final String descKo;
  const _MicOptionRow({
    required this.ko,
    required this.icon,
    required this.nameEn,
    required this.nameKo,
    required this.descEn,
    required this.descKo,
  });

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    decoration: BoxDecoration(
      border: Border.all(color: Colors.white12),
      borderRadius: BorderRadius.circular(6),
    ),
    child: Row(children: [
      Icon(icon, color: Colors.white24, size: 16),
      const SizedBox(width: 12),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(ko ? nameKo : nameEn, style: const TextStyle(color: Colors.white54, fontSize: 13)),
        const SizedBox(height: 2),
        Text(ko ? descKo : descEn,
            style: TextStyle(color: Colors.white.withValues(alpha: 0.3), fontSize: 11, height: 1.4)),
      ])),
    ]),
  );
}

// ── 공용 위젯 ──────────────────────────────────────────────────────────────────
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

class _LocationPicker extends ConsumerWidget {
  const _LocationPicker();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selected = ref.watch(installLocationProvider);
    final ko = Localizations.localeOf(context).languageCode == 'ko';
    return SectionCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(
          ko ? '스피커가 놓인 공간을 알려주세요' : 'Where is your speaker?',
          style: const TextStyle(color: Colors.white, fontSize: 14, letterSpacing: 0.5),
        ),
        const SizedBox(height: 4),
        const Text('이 정보는 공간에 맞는 사운드를 준비하는 데 사용됩니다.',
            style: TextStyle(color: Colors.white38, fontSize: 11)),
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
                Text(ko ? loc.label : loc.labelEn,
                    style: TextStyle(
                        color: isSelected ? Colors.white : Colors.white60, fontSize: 13)),
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

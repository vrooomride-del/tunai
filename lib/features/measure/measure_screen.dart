import 'package:flutter/foundation.dart';
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

/// MEASURE 탭 — 설치 위치 선택(방이 Driver보다 먼저) + 마이크 측정.
/// 측정 완료 시 [onMeasured]로 AI 탭 자동 전환을 요청한다.
class MeasureScreen extends ConsumerWidget {
  final VoidCallback onMeasured;
  const MeasureScreen({super.key, required this.onMeasured});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mState = ref.watch(measurementProvider);
    final bState = ref.watch(bleProvider);

    ref.listen<MeasurementState>(measurementProvider, (prev, next) {
      if (next.step == MeasurementStep.done && prev?.step != MeasurementStep.done) {
        if (next.scmsBins.isNotEmpty) {
          ref.read(spectrumSnapshotProvider.notifier).setBefore(next.scmsBins);
        }
        onMeasured();
      }
    });

    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      body: SafeArea(
        child: Column(
          children: [
            const TunaiTopBar(subtitle: 'MEASURE'),
            const Padding(padding: EdgeInsets.symmetric(horizontal: 24), child: PresetBar()),
            const SizedBox(height: 8),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const _LocationPicker(),
                    const SizedBox(height: 16),
                    SectionCard(child: _MeasurePanel(mState: mState, bState: bState, ref: ref)),
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

/// 🏠 설치 위치를 먼저 선택 — 방이 Driver보다 중요하다
class _LocationPicker extends ConsumerWidget {
  const _LocationPicker();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selected = ref.watch(installLocationProvider);
    return SectionCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Row(children: [
          Text('🏠', style: TextStyle(fontSize: 14)),
          SizedBox(width: 6),
          Text('설치 위치를 먼저 선택하세요', style: TextStyle(color: Colors.white, fontSize: 14, letterSpacing: 1)),
        ]),
        const SizedBox(height: 2),
        const Text('방이 Driver보다 중요합니다', style: TextStyle(color: Colors.white38, fontSize: 11)),
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
                Text(loc.label, style: TextStyle(color: isSelected ? Colors.white : Colors.white60, fontSize: 13)),
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

class _MeasurePanel extends StatelessWidget {
  final MeasurementState mState;
  final BleState bState;
  final WidgetRef ref;
  const _MeasurePanel({required this.mState, required this.bState, required this.ref});

  @override
  Widget build(BuildContext context) {
    final ctrl = ref.read(measurementProvider.notifier);
    final step = mState.step;
    final isRunning = step != MeasurementStep.idle
        && step != MeasurementStep.done && step != MeasurementStep.error;
    final isConverging = step == MeasurementStep.converging;
    final isConnected = bState.connection == BleConnectionState.connected;

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (!isConnected)
        const Padding(
          padding: EdgeInsets.only(bottom: 12),
          child: Text('스피커를 먼저 연결하세요 (CONNECT 탭)', style: TextStyle(color: Colors.white38, fontSize: 12, letterSpacing: 1)),
        ),
      Row(children: [
        Expanded(child: Text(
          mState.error ?? (mState.message.isEmpty ? '핑크노이즈 재생 후 공간 음향을 분석합니다.' : mState.message),
          style: TextStyle(color: mState.error != null ? Colors.redAccent : Colors.white60, fontSize: 14, height: 1.5))),
        const SizedBox(width: 16),
        OutlineButton(
          label: isRunning ? (isConverging ? '수렴 중...' : '측정 중...') :
                 step == MeasurementStep.done ? 'RE-MEASURE' : 'MEASURE',
          loading: isRunning,
          enabled: isConnected || step == MeasurementStep.done || step == MeasurementStep.error,
          onTap: isRunning ? null : step == MeasurementStep.done || step == MeasurementStep.error
            ? ctrl.reset
            : isConnected ? () => ctrl.startMeasurement(speakerProfile: ref.read(speakerProfileProvider)) : null,
        ),
      ]),

      // Closed Loop 진행 상황
      if (isConverging && mState.iteration > 0)
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Row(children: [
            Expanded(child: LinearProgressIndicator(
              value: mState.iteration / 3,
              backgroundColor: Colors.white12,
              color: Colors.white38,
              minHeight: 2,
            )),
            const SizedBox(width: 12),
            Text('${mState.iteration}/3',
                style: const TextStyle(color: Colors.white38, fontSize: 10, letterSpacing: 1)),
            if (mState.residualErrorDb != null) ...[
              const SizedBox(width: 8),
              Text('잔류 ${mState.residualErrorDb!.toStringAsFixed(1)}dB',
                  style: const TextStyle(color: Colors.white24, fontSize: 10)),
            ],
          ]),
        ),

      // 수렴 결과 배지
      if (step == MeasurementStep.done && mState.iteration > 0) ...[
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            border: Border.all(color: mState.hasConverged ? Colors.white24 : Colors.white12),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Row(children: [
            Icon(mState.hasConverged ? Icons.check_circle_outline : Icons.info_outline,
                color: mState.hasConverged ? Colors.white54 : Colors.white24, size: 14),
            const SizedBox(width: 8),
            Text(
              mState.hasConverged
                  ? '수렴 완료 (${mState.iteration}회'
                    '${mState.residualErrorDb != null ? ', 잔류 ${mState.residualErrorDb!.toStringAsFixed(1)}dB' : ''})'
                  : '${mState.iteration}회 반복 완료 — 수동 미세 조정 가능',
              style: TextStyle(
                  color: mState.hasConverged ? Colors.white54 : Colors.white24,
                  fontSize: 10),
            ),
          ]),
        ),
      ],

      // Closed Loop 시작 버튼 (측정 전 + BLE 연결 시)
      if (step == MeasurementStep.idle && isConnected) ...[
        const SizedBox(height: 10),
        OutlineButton(
          label: 'AI Optimize (반복수렴)',
          onTap: () => ctrl.startClosedLoop(speakerProfile: ref.read(speakerProfileProvider)),
        ),
        const SizedBox(height: 4),
        const Text('DSP 적용 후 자동 재측정, 최대 3회 반복',
            style: TextStyle(color: Colors.white24, fontSize: 10, letterSpacing: 1)),
      ],
      if (kDebugMode) ...[
        const SizedBox(height: 12),
        OutlineButton(
          label: '🛠 더미 데이터 주입',
          onTap: () => ctrl.injectDummyData(),
        ),
      ],
      if (mState.scmsBins.isNotEmpty) ...[const SizedBox(height: 20), SpectrumChart(bins: mState.scmsBins, peaks: mState.peaks)],
      if (mState.peaks.isNotEmpty) ...[const SizedBox(height: 16), PeakTable(peaks: mState.peaks)],
    ]);
  }
}

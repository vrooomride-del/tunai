import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/audio_analyzer.dart';
import '../core/ai_tuning_service.dart';
import '../core/factory_preset.dart';
import '../core/my_tune_storage.dart';
import '../core/spectrum_snapshot.dart';
import '../features/ble/ble_controller.dart';
import '../features/dsp/dsp_compiler.dart';
import '../features/fine_tune/taste_preset.dart';
import '../features/tune/preset_bar_provider.dart';

/// 상단 프리셋 바 — [Factory] [My Tune] [AI Tune] [Near Wall] [Desk] [Studio]
/// 기존 보드선택 칩 자리를 대체. MEASURE/AI/LISTEN/FINE TUNE 상단에 노출.
class PresetBar extends ConsumerWidget {
  const PresetBar({super.key});

  List<ResonancePeak> _currentEffectivePeaks(WidgetRef ref) {
    final aiResult = ref.read(lastAiResultProvider);
    final aiPeaks = (aiResult?.bands ?? [])
        .where((b) => b['enabled'] != false)
        .map((b) => ResonancePeak(
              frequency: (b['frequency'] as num).toDouble(),
              gain: (b['gainDb'] as num).toDouble(),
              q: (b['q'] as num).toDouble(),
            ))
        .toList();
    final taste = ref.read(selectedTasteProvider)?.bands ?? const [];
    return [...aiPeaks, ...taste];
  }

  Future<void> _select(BuildContext context, WidgetRef ref, PresetBarSelection sel) async {
    ref.read(presetBarSelectionProvider.notifier).state = sel;

    List<ResonancePeak> peaks;
    switch (sel) {
      case PresetBarSelection.factory:
        // 읽기전용 Factory 레이어(factory_preset.dart) — 코드에 내장된 불변 값,
        // 저장/수정 대상이 아님(AOS 항목 C)
        peaks = kFactoryPresetFlat.bands;
        break;
      case PresetBarSelection.reference:
        // Factory와 동일한 플랫 EQ(무보정)로 정의 — 별도 기준 커브 데이터가
        // 생기면 그때 구분되는 로직을 넣을 것
        peaks = kFactoryPresetFlat.bands;
        break;
      case PresetBarSelection.aiTune:
        final result = ref.read(lastAiResultProvider);
        if (result == null) {
          _snack(context, 'AI 튜닝 결과가 없습니다 — AI 탭에서 먼저 튜닝하세요');
          return;
        }
        peaks = result.bands
            .where((b) => b['enabled'] != false)
            .map((b) => ResonancePeak(
                  frequency: (b['frequency'] as num).toDouble(),
                  gain: (b['gainDb'] as num).toDouble(),
                  q: (b['q'] as num).toDouble(),
                ))
            .toList();
        break;
      case PresetBarSelection.myTune:
        final saved = await MyTuneStorage.load();
        if (saved == null) {
          if (context.mounted) _snack(context, '저장된 My Tune이 없습니다 — 우측 저장 버튼으로 먼저 저장하세요');
          return;
        }
        peaks = saved;
        break;
      case PresetBarSelection.nearWall:
      case PresetBarSelection.desk:
      case PresetBarSelection.studio:
        peaks = kLocationPresetBands[sel] ?? const [];
        break;
    }

    final isConnected = ref.read(bleProvider).connection == BleConnectionState.connected;
    if (isConnected) {
      final packets = DspCompiler.compileAll(peaks);
      await ref.read(bleProvider.notifier).sendPackets(packets);
    }

    final snap = ref.read(spectrumSnapshotProvider);
    final base = snap.afterAi ?? snap.before;
    if (base != null) {
      final preview = SpectrumSnapshotController.previewWithPeaks(base, peaks);
      ref.read(spectrumSnapshotProvider.notifier).setCurrent(preview);
    }

    if (context.mounted) {
      _snack(context, isConnected ? '${sel.label} APPLY 완료' : '${sel.label} 선택됨 (연결 후 실제 적용 가능)');
    }
  }

  void _snack(BuildContext context, String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg), duration: const Duration(seconds: 2)));
  }

  Future<void> _save(BuildContext context, WidgetRef ref) async {
    final peaks = _currentEffectivePeaks(ref);
    if (peaks.isEmpty) {
      _snack(context, '저장할 튜닝이 없습니다 — AI 탭에서 먼저 튜닝하세요');
      return;
    }
    await MyTuneStorage.save(peaks);
    if (context.mounted) _snack(context, 'My Tune으로 저장됨 (${peaks.length}개 밴드)');
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selected = ref.watch(presetBarSelectionProvider);
    return SizedBox(
      height: 40,
      child: Row(children: [
        Expanded(
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: PresetBarSelection.values.map((sel) {
              final isSelected = selected == sel;
              return Padding(
                padding: const EdgeInsets.only(right: 8),
                child: GestureDetector(
                  onTap: () => _select(context, ref, sel),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      border: Border.all(color: isSelected ? Colors.white : Colors.white12),
                      borderRadius: BorderRadius.circular(20),
                      color: isSelected ? Colors.white.withValues(alpha: 0.08) : Colors.transparent,
                    ),
                    child: Text(sel.label,
                        style: TextStyle(color: isSelected ? Colors.white : Colors.white54, fontSize: 12, letterSpacing: 1)),
                  ),
                ),
              );
            }).toList(),
          ),
        ),
        const SizedBox(width: 8),
        GestureDetector(
          onTap: () => _save(context, ref),
          child: Container(
            width: 40,
            height: 40,
            alignment: Alignment.center,
            decoration: BoxDecoration(border: Border.all(color: Colors.white12), borderRadius: BorderRadius.circular(20)),
            child: const Icon(Icons.bookmark_border, color: Colors.white38, size: 16),
          ),
        ),
      ]),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'taste_preset.dart';
import '../ble/ble_controller.dart';
import '../dsp/dsp_compiler.dart';
import '../../core/ai_tuning_service.dart';
import '../../core/audio_analyzer.dart';
import '../../core/profiles/system_profile.dart';
import '../../core/spectrum_snapshot.dart';
import '../../shared/widgets.dart';
import '../../shared/preset_bar.dart';

/// FINE TUNE 탭 — AI가 만든 기본 EQ 위에 취향(Warm/Neutral/Studio/Vocal/Movie/Bright)을 얹는다.
class FineTuneScreen extends ConsumerStatefulWidget {
  const FineTuneScreen({super.key});
  @override
  ConsumerState<FineTuneScreen> createState() => _FineTuneScreenState();
}

class _FineTuneScreenState extends ConsumerState<FineTuneScreen> {
  bool _applying = false;

  void _select(TastePreset preset) {
    ref.read(selectedTasteProvider.notifier).state = preset;
    // 그래프 파란선(현재)을 즉시 미리보기로 갱신 — DSP 전송 전 로컬 프리뷰
    final snap = ref.read(spectrumSnapshotProvider);
    final base = snap.afterAi ?? snap.before;
    if (base != null) {
      final preview = SpectrumSnapshotController.previewWithPeaks(base, preset.bands);
      ref.read(spectrumSnapshotProvider.notifier).setCurrent(preview);
    }
  }

  Future<void> _apply(TastePreset preset) async {
    final isConnected = ref.read(bleProvider).connection == BleConnectionState.connected;
    if (!isConnected) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('스피커를 먼저 연결하세요')));
      return;
    }
    setState(() => _applying = true);
    final maxBands = ref.read(systemProfileProvider).maxPeqBands;
    final aiResult = ref.read(lastAiResultProvider);
    final aiPeaks = (aiResult?.bands ?? [])
        .where((b) => b['enabled'] != false)
        .map((b) => ResonancePeak(
              frequency: (b['frequency'] as num).toDouble(),
              gain: (b['gainDb'] as num).toDouble(),
              q: (b['q'] as num).toDouble(),
            ))
        .toList();
    final combined = [...aiPeaks, ...preset.bands].take(maxBands).toList();
    final packets = DspCompiler.compileAll(combined);
    await ref.read(bleProvider.notifier).sendPackets(packets);
    if (mounted) setState(() => _applying = false);
    if (mounted) {
      final ko = Localizations.localeOf(context).languageCode == 'ko';
      final name = ko ? preset.labelKo : preset.label;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(ko ? '$name 취향 적용 완료' : '$name applied')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final selected = ref.watch(selectedTasteProvider);
    final isConnected = ref.watch(bleProvider).connection == BleConnectionState.connected;
    final ko = Localizations.localeOf(context).languageCode == 'ko';
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      body: SafeArea(
        child: Column(
          children: [
            TunaiTopBar(subtitle: ko ? '취향 조정' : 'FINE TUNE'),
            const Padding(padding: EdgeInsets.symmetric(horizontal: 24), child: PresetBar()),
            const SizedBox(height: 8),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
                children: [
                  const Row(children: [
                    Text('🎵', style: TextStyle(fontSize: 14)),
                    SizedBox(width: 6),
                    Text('취향을 선택하세요', style: TextStyle(color: Colors.white, fontSize: 14, letterSpacing: 1)),
                  ]),
                  const SizedBox(height: 2),
                  const Text('Your Sound 위에 취향을 더합니다.', style: TextStyle(color: Colors.white38, fontSize: 11)),
                  const SizedBox(height: 12),
                  ...kTastePresets.map((preset) {
                    final isSelected = selected?.id == preset.id;
                    return GestureDetector(
                      onTap: () => _select(preset),
                      child: Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                        decoration: BoxDecoration(
                          border: Border.all(color: isSelected ? Colors.white : Colors.white12),
                          borderRadius: BorderRadius.circular(8),
                          color: isSelected ? Colors.white.withValues(alpha: 0.06) : Colors.transparent,
                        ),
                        child: Row(children: [
                          Expanded(
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text(ko ? preset.labelKo : preset.label,
                                  style: TextStyle(color: isSelected ? Colors.white : Colors.white70, fontSize: 15, letterSpacing: 1)),
                              const SizedBox(height: 2),
                              Text(preset.description, style: const TextStyle(color: Colors.white38, fontSize: 12)),
                            ]),
                          ),
                          if (isSelected) const Icon(Icons.check_circle, color: Colors.white, size: 18),
                        ]),
                      ),
                    );
                  }),
                  const SizedBox(height: 16),
                  OutlineButton(
                    label: _applying ? (ko ? '적용 중...' : 'Sending...') : (ko ? '스피커에 적용' : 'Apply to Speaker'),
                    loading: _applying,
                    enabled: selected != null && isConnected && !_applying,
                    onTap: selected == null || !isConnected ? null : () => _apply(selected),
                  ),
                  if (!isConnected)
                    const Padding(
                      padding: EdgeInsets.only(top: 8),
                      child: Text('스피커 연결 후 적용 가능합니다', style: TextStyle(color: Colors.white24, fontSize: 10, letterSpacing: 1)),
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

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../measurement/measurement_controller.dart';
import '../../shared/widgets.dart';
import '../../shared/spectrum_chart.dart';

/// LISTEN 탭 — Before/After 비교. 3색 오버레이는 Task 4에서 완성된다.
class ListenScreen extends ConsumerWidget {
  const ListenScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mState = ref.watch(measurementProvider);
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      body: SafeArea(
        child: Column(
          children: [
            const TunaiTopBar(subtitle: 'LISTEN'),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
                child: mState.scmsBins.isEmpty
                    ? const _EmptyState()
                    : SectionCard(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                          const Text('현재 스펙트럼', style: TextStyle(color: Colors.white60, fontSize: 12, letterSpacing: 2)),
                          const SizedBox(height: 12),
                          SpectrumChart(bins: mState.scmsBins, peaks: mState.peaks),
                        ]),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();
  @override
  Widget build(BuildContext context) {
    return const SectionCard(
      child: Column(children: [
        Icon(Icons.graphic_eq, color: Colors.white24, size: 32),
        SizedBox(height: 10),
        Text('AI 적용 후 Before/After 비교가 여기에 표시됩니다', style: TextStyle(color: Colors.white54, fontSize: 13), textAlign: TextAlign.center),
      ]),
    );
  }
}

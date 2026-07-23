// Consumer Result Graph — no technical terms (Hz/dB/Q/FFT/PEQ/DSP), and the
// "after" curve/legend must only appear when a real synthesized curve was
// actually provided (never a fabricated comparison).

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:tunai/core/audio_analyzer.dart';
import 'package:tunai/shared/consumer_response_chart.dart';

const _before = [
  FrequencyBin(frequency: 40, magnitude: -18),
  FrequencyBin(frequency: 80, magnitude: -6),
  FrequencyBin(frequency: 150, magnitude: -10),
  FrequencyBin(frequency: 300, magnitude: -12),
];

const _after = [
  FrequencyBin(frequency: 40, magnitude: -18),
  FrequencyBin(frequency: 80, magnitude: -10),
  FrequencyBin(frequency: 150, magnitude: -10),
  FrequencyBin(frequency: 300, magnitude: -12),
];

Widget _app(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  testWidgets('renders only the Before curve/legend when no after curve exists',
      (tester) async {
    await tester.pumpWidget(
        _app(const ConsumerResponseChart(before: _before, ko: true)));

    expect(find.text('현재 공간'), findsOneWidget);
    expect(find.text('TUNAI 예상 균형'), findsNothing);
  });

  testWidgets('renders both curves/legend when a real after curve is provided',
      (tester) async {
    await tester.pumpWidget(_app(
        const ConsumerResponseChart(before: _before, after: _after, ko: true)));

    expect(find.text('현재 공간'), findsOneWidget);
    expect(find.text('TUNAI 예상 균형'), findsOneWidget);
  });

  testWidgets('never shows technical terms', (tester) async {
    await tester.pumpWidget(_app(
        const ConsumerResponseChart(before: _before, after: _after, ko: true)));

    for (final term in ['Hz', 'dB', 'FFT', 'PEQ', 'DSP', ' Q ']) {
      expect(find.textContaining(term), findsNothing,
          reason: 'Consumer chart must never surface "$term"');
    }
  });

  testWidgets('renders nothing when there is no measured data at all',
      (tester) async {
    await tester
        .pumpWidget(_app(const ConsumerResponseChart(before: [], ko: true)));

    expect(find.byType(ConsumerResponseChart), findsOneWidget);
    expect(find.text('현재 공간'), findsNothing);
  });

  testWidgets(
      'a narrow, high-Q correction stays visually distinct from Before — '
      'the "after" curve is never smoothed away into an apparent overlap',
      (tester) async {
    // Fine-grained bins mimicking real FFT resolution (~0.67Hz) across a
    // narrow band, with a genuine Q=15-like -6dB dip only in `after` right
    // at 120Hz — narrower than the 1/6-octave smoothing window applied to
    // `before`. If `after` were smoothed the same way, this dip would be
    // averaged away almost entirely.
    final before = <FrequencyBin>[
      for (double f = 100; f <= 140; f += 0.67)
        FrequencyBin(frequency: f, magnitude: -10),
    ];
    final after = <FrequencyBin>[
      for (final b in before)
        FrequencyBin(
          frequency: b.frequency,
          magnitude: b.magnitude + ((b.frequency - 120).abs() < 1 ? -6 : 0),
        ),
    ];

    await tester.pumpWidget(
        _app(ConsumerResponseChart(before: before, after: after, ko: true)));

    final chart = tester.widget<LineChart>(find.byType(LineChart));
    final bars = chart.data.lineBarsData;
    expect(bars, hasLength(2));
    final afterSpots = bars[1].spots;
    final minAfterY =
        afterSpots.map((s) => s.y).reduce((a, b) => a < b ? a : b);
    // The real -6dB dip must survive essentially intact in the rendered
    // "after" curve (allow a small margin, but nowhere near smoothed away).
    expect(minAfterY, lessThan(-15.5));
  });
}

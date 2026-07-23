import 'package:flutter_test/flutter_test.dart';
import 'package:tunai/core/audio_analyzer.dart';
import 'package:tunai/core/spectrum_snapshot.dart';

/// Verifies the Room Scan → AI Tune → LISTEN "before/after" wiring: a
/// TunePlan's real bands (frequencyHz/gainDb/q), converted to [ResonancePeak]
/// exactly as `ai_screen.dart._createTune` does, produce a non-null `afterAi`
/// snapshot on top of the real measured `before` curve. This is the
/// connection that was previously broken (applyPeaks() was never called).
void main() {
  group('SpectrumSnapshotController before/after wiring', () {
    test('applyPeaks with TunePlan-shaped peaks populates afterAi from before',
        () {
      final controller = SpectrumSnapshotController();
      const measured = [
        FrequencyBin(frequency: 100, magnitude: -20),
        FrequencyBin(frequency: 200, magnitude: -10),
        FrequencyBin(frequency: 400, magnitude: -15),
      ];
      controller.setBefore(measured);
      expect(controller.state.before, measured);
      expect(controller.state.afterAi, isNull);

      // Same field mapping used in ai_screen.dart: TuneCorrectionBand
      // (frequencyHz, gainDb, q) → ResonancePeak (frequency, gain, q).
      const bandFrequencyHz = 200.0;
      const bandGainDb = -4.0;
      const bandQ = 2.0;
      controller.applyPeaks(const [
        ResonancePeak(frequency: bandFrequencyHz, gain: bandGainDb, q: bandQ),
      ]);

      expect(controller.state.before, measured);
      expect(controller.state.afterAi, isNotNull);
      expect(controller.state.current, controller.state.afterAi);

      // The 200Hz bin sits exactly at the peak center, so it receives the
      // full real (not fabricated) synthesized gain.
      final after200 =
          controller.state.afterAi!.firstWhere((b) => b.frequency == 200);
      expect(after200.magnitude, closeTo(-10 + bandGainDb, 0.001));
    });

    test('applyPeaks is a no-op without a prior before snapshot', () {
      final controller = SpectrumSnapshotController();
      controller
          .applyPeaks(const [ResonancePeak(frequency: 200, gain: -3, q: 2)]);
      expect(controller.state.before, isNull);
      expect(controller.state.afterAi, isNull);
    });

    test(
        'applyPeaks with an EMPTY peaks list (bandless TunePlan) leaves '
        'afterAi null — regression test for the real-device bug where an '
        'empty-band Tune still showed a "TUNAI 예상 균형" curve/legend '
        'identical to Before', () {
      final controller = SpectrumSnapshotController();
      const measured = [
        FrequencyBin(frequency: 100, magnitude: -20),
        FrequencyBin(frequency: 200, magnitude: -10),
      ];
      controller.setBefore(measured);

      controller.applyPeaks(const []);

      expect(controller.state.before, measured);
      expect(controller.state.afterAi, isNull,
          reason: 'no bands to synthesize from → no after curve, not a '
              'curve identical to before');
      expect(controller.state.current, measured);
    });

    test(
        'clearAfter() drops a stale afterAi from an earlier Tune while '
        'keeping the current Before curve', () {
      final controller = SpectrumSnapshotController();
      controller.setBefore(const [FrequencyBin(frequency: 100, magnitude: -20)]);
      controller
          .applyPeaks(const [ResonancePeak(frequency: 100, gain: -3, q: 2)]);
      expect(controller.state.afterAi, isNotNull);

      controller.clearAfter();

      expect(controller.state.before, isNotNull);
      expect(controller.state.afterAi, isNull);
      expect(controller.state.current, controller.state.before);
    });

    test('reset clears before/after/current', () {
      final controller = SpectrumSnapshotController();
      controller.setBefore(const [FrequencyBin(frequency: 100, magnitude: -20)]);
      controller
          .applyPeaks(const [ResonancePeak(frequency: 100, gain: -2, q: 2)]);
      expect(controller.state.afterAi, isNotNull);

      controller.reset();
      expect(controller.state.before, isNull);
      expect(controller.state.afterAi, isNull);
      expect(controller.state.current, isNull);
    });
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tunai/core/consumer_sound_profile.dart';
import 'package:tunai/core/sound_preference.dart';
import 'package:tunai/core/tune_outcome_history.dart';

TuneOutcomeRecord _record({
  required String tunePlanId,
  DateTime? recordedAt,
  ConsumerDspDeploymentRecordResult result =
      ConsumerDspDeploymentRecordResult.applied,
}) =>
    TuneOutcomeRecord(
      tunePlanId: tunePlanId,
      measurementId: 'measurement-1',
      preference: SoundPreference.warm,
      usedAiRecommendation: true,
      result: result,
      soundScoreBefore: 60,
      soundScoreAfter: 78,
      recordedAt: recordedAt ?? DateTime.utc(2026, 7, 21),
    );

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('TuneOutcomeHistory', () {
    test('empty by default', () async {
      expect(await TuneOutcomeHistory.load(), isEmpty);
    });

    test('records a real outcome and round-trips every field', () async {
      final entry = _record(tunePlanId: 'plan-1');
      await TuneOutcomeHistory.record(entry);

      final loaded = await TuneOutcomeHistory.load();
      expect(loaded, hasLength(1));
      expect(loaded.single.tunePlanId, 'plan-1');
      expect(loaded.single.measurementId, 'measurement-1');
      expect(loaded.single.preference, SoundPreference.warm);
      expect(loaded.single.usedAiRecommendation, isTrue);
      expect(loaded.single.result, ConsumerDspDeploymentRecordResult.applied);
      expect(loaded.single.soundScoreBefore, 60);
      expect(loaded.single.soundScoreAfter, 78);
      expect(loaded.single.recordedAt, entry.recordedAt);
    });

    test('most-recent first', () async {
      await TuneOutcomeHistory.record(_record(tunePlanId: 'plan-1'));
      await TuneOutcomeHistory.record(_record(tunePlanId: 'plan-2'));
      await TuneOutcomeHistory.record(_record(tunePlanId: 'plan-3'));

      final loaded = await TuneOutcomeHistory.load();
      expect(loaded.map((e) => e.tunePlanId).toList(),
          ['plan-3', 'plan-2', 'plan-1']);
    });

    test('keeps only the most recent maxEntries', () async {
      for (var i = 0; i < TuneOutcomeHistory.maxEntries + 3; i++) {
        await TuneOutcomeHistory.record(_record(tunePlanId: 'plan-$i'));
      }
      final loaded = await TuneOutcomeHistory.load();
      expect(loaded, hasLength(TuneOutcomeHistory.maxEntries));
      // The newest entries survive, oldest are dropped.
      expect(loaded.first.tunePlanId, 'plan-${TuneOutcomeHistory.maxEntries + 2}');
    });

    test('clear empties the history', () async {
      await TuneOutcomeHistory.record(_record(tunePlanId: 'plan-1'));
      await TuneOutcomeHistory.clear();
      expect(await TuneOutcomeHistory.load(), isEmpty);
    });
  });
}

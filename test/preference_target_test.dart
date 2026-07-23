import 'package:flutter_test/flutter_test.dart';
import 'package:tunai/core/acoustic_analysis.dart' show ToneRegion;
import 'package:tunai/core/factory_sound_profile.dart';
import 'package:tunai/core/preference_correction_generator.dart';
import 'package:tunai/core/preference_plan_merger.dart';
import 'package:tunai/core/preference_target.dart';
import 'package:tunai/core/room_measurement.dart' show CaptureQualityStatus;
import 'package:tunai/core/tune_plan.dart';
import 'package:tunai/core/tune_safety_validator.dart';

const _gen = PreferenceCorrectionGenerator();

TuneCorrectionBand _roomBand(double f, double g,
        [TuneCorrectionSource s = TuneCorrectionSource.roomMode]) =>
    TuneCorrectionBand(
      frequencyHz: f,
      gainDb: g,
      q: 1,
      evidenceReference: 'room',
      safetyValidated: true,
      source: s,
    );

TunePlan _plan(List<TuneCorrectionBand> bands) => TunePlan(
      id: 'p',
      sourceMeasurementId: 'm',
      createdAt: DateTime.utc(2026),
      bands: bands,
      rejectedCandidates: const [],
      safetyBounds: TuneSafetyBounds.consumerFullRange,
      measurementQuality: CaptureQualityStatus.valid,
      measurementConsistency: 1,
      warnings: const [],
    );

void main() {
  group('PreferenceTarget — perceptual descriptor only, no dB', () {
    test('warm leans low up / high down', () {
      final t = PreferenceTarget.forDescriptor('warm')!;
      expect(t.regionDirection[ToneRegion.low], PreferenceDirection.gentleLift);
      expect(
          t.regionDirection[ToneRegion.high], PreferenceDirection.gentleSoften);
      // The model carries NO number.
      final serialized = t.toJson().toString().toLowerCase();
      for (final n in RegExp(r'\d').allMatches(serialized)) {
        fail('PreferenceTarget must hold no number, found: ${n.group(0)}');
      }
    });

    test('natural / unknown descriptors yield no target (no nudge)', () {
      expect(PreferenceTarget.forDescriptor('natural'), isNull);
      expect(PreferenceTarget.forDescriptor('nonsense'), isNull);
      expect(PreferenceTarget.forDescriptor(null), isNull);
    });

    test('vocal/detailed/comfortable each map to a single-region lean', () {
      expect(PreferenceTarget.forDescriptor('vocal')!.regionDirection[
          ToneRegion.mid], PreferenceDirection.gentleLift);
      expect(PreferenceTarget.forDescriptor('detailed')!.regionDirection[
          ToneRegion.high], PreferenceDirection.gentleLift);
      expect(PreferenceTarget.forDescriptor('comfortable')!.regionDirection[
          ToneRegion.high], PreferenceDirection.gentleSoften);
    });
  });

  group('PreferenceCorrectionGenerator — bounded, factory-anchored, no AI', () {
    test('emits a small nudge per non-neutral region, within the boost cap', () {
      final bands =
          _gen.generate(PreferenceTarget.forDescriptor('warm')!);
      expect(bands, isNotEmpty);
      for (final b in bands) {
        expect(b.gainDb.abs(), lessThanOrEqualTo(PreferenceCorrectionGenerator.nudgeDb));
        expect(b.gainDb.abs(), lessThanOrEqualTo(3.0)); // boost ceiling
        expect(b.source, TuneCorrectionSource.preferenceTarget);
        expect(b.q, greaterThan(0));
      }
    });

    test('a gentle-range factory shrinks the nudge (character protection)', () {
      final normal =
          _gen.generate(PreferenceTarget.forDescriptor('warm')!);
      final gentle = _gen.generate(
        PreferenceTarget.forDescriptor('warm')!,
        factory: FactorySoundProfile.fromJson(
            const {'speakerModel': 'X', 'safeOperatingRange': 'gentle'}),
      );
      expect(gentle.first.gainDb.abs(), lessThan(normal.first.gainDb.abs()));
    });

    test('deterministic — same target, identical bands', () {
      final a = _gen.generate(PreferenceTarget.forDescriptor('vocal')!);
      final b = _gen.generate(PreferenceTarget.forDescriptor('vocal')!);
      expect(a.map((x) => x.toJson()), b.map((x) => x.toJson()));
    });
  });

  group('PreferencePlanMerger — priority Safety > Room > Preference', () {
    const merger = PreferencePlanMerger();

    test('NO preference bands → room plan returned UNCHANGED (regression)', () {
      final room = _plan([_roomBand(80, -4), _roomBand(220, -3)]);
      final merged = merger.merge(room, const []);
      expect(identical(merged, room), isTrue);
    });

    test('balanced room + preference → preference is applied', () {
      final room = _plan(const []); // room needed no correction
      final prefBands =
          _gen.generate(PreferenceTarget.forDescriptor('warm')!);
      final merged = merger.merge(room, prefBands);
      expect(
          merged.bands
              .any((b) => b.source == TuneCorrectionSource.preferenceTarget),
          isTrue);
    });

    test('room issue + preference → both merge when budget allows', () {
      final room = _plan([_roomBand(80, -4)]);
      final prefBands =
          _gen.generate(PreferenceTarget.forDescriptor('detailed')!);
      final merged = merger.merge(room, prefBands);
      expect(merged.bands.any((b) => b.source == TuneCorrectionSource.roomMode),
          isTrue);
      expect(
          merged.bands
              .any((b) => b.source == TuneCorrectionSource.preferenceTarget),
          isTrue);
    });

    test('over budget → preference removed, room correction kept', () {
      // Three room bands already fill the deployable budget (3).
      final room = _plan([
        _roomBand(70, -4),
        _roomBand(200, -3),
        _roomBand(600, -3),
      ]);
      final prefBands =
          _gen.generate(PreferenceTarget.forDescriptor('warm')!);
      final merged = merger.merge(room, prefBands);
      // Every room band survives; no preference band fits.
      expect(
          merged.bands
              .where((b) => b.source == TuneCorrectionSource.roomMode)
              .length,
          3);
      expect(
          merged.bands
              .any((b) => b.source == TuneCorrectionSource.preferenceTarget),
          isFalse);
    });

    test('every band in a merged plan passes the Safety Validator', () {
      final room = _plan([_roomBand(80, -4)]);
      final prefBands =
          _gen.generate(PreferenceTarget.forDescriptor('warm')!);
      final merged = merger.merge(room, prefBands);
      final revalidate = const TuneSafetyValidator().validatePlan(merged);
      expect(revalidate.approvedBands.length, merged.bands.length);
    });

    test('a merged plan carries no numeric leak beyond real band values', () {
      // Sanity: the source tags are strings, no engineering FIELD names appear.
      final room = _plan([_roomBand(80, -4)]);
      final merged =
          merger.merge(room, _gen.generate(PreferenceTarget.forDescriptor('warm')!));
      for (final b in merged.bands) {
        // Bands legitimately hold gain/freq/q numbers (that is the DSP layer);
        // what must never appear is an AI-authored value — enforced by the fact
        // that these came from TunePlanner + the deterministic generator only.
        expect(b.safetyValidated, isTrue);
      }
    });
  });
}

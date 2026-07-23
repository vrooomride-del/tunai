import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tunai/core/acoustic_intent.dart';
import 'package:tunai/core/acoustic_profile.dart';
import 'package:tunai/core/factory_sound_profile.dart';
import 'package:tunai/core/install_location.dart';
import 'package:tunai/core/listening_taste.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  group('AcousticProfile — structure-only personalization model', () {
    test('round-trips through JSON', () {
      const profile = AcousticProfile(
        roomType: 'Living Room',
        placement: InstallLocation.nearWall,
        listeningTaste: ListeningTaste.warm,
        listeningGoal: ListeningGoal.longListening,
        previousTuneIds: ['t1', 't2'],
      );
      final restored = AcousticProfile.fromJson(profile.toJson());
      expect(restored.roomType, 'Living Room');
      expect(restored.placement, InstallLocation.nearWall);
      expect(restored.listeningTaste, ListeningTaste.warm);
      expect(restored.listeningGoal, ListeningGoal.longListening);
      expect(restored.previousTuneIds, ['t1', 't2']);
    });

    test('defaults are safe and taste defaults to natural', () {
      final restored = AcousticProfile.fromJson({'roomType': 'Studio'});
      expect(restored.placement, isNull);
      expect(restored.listeningTaste, ListeningTaste.natural);
      expect(restored.previousTuneIds, isEmpty);
    });

    test('withTune appends real ids and dedups', () {
      const p = AcousticProfile(roomType: 'Room');
      final a = p.withTune('tune-1');
      final b = a.withTune('tune-1').withTune('tune-2');
      expect(a.previousTuneIds, ['tune-1']);
      expect(b.previousTuneIds, ['tune-1', 'tune-2']);
    });

    test('malformed previousTuneIds degrade to empty, never throw', () {
      final restored = AcousticProfile.fromJson({
        'roomType': 'Room',
        'previousTuneIds': [1, 'ok', null],
      });
      expect(restored.previousTuneIds, ['ok']);
    });
  });

  group('AcousticProfileStore — save / load (8.3)', () {
    test('saves and loads a profile', () async {
      const profile = AcousticProfile(
        roomType: 'Studio',
        placement: InstallLocation.desk,
        listeningTaste: ListeningTaste.detailed,
        listeningGoal: ListeningGoal.desktop,
        previousTuneIds: ['tune-a'],
      );
      await AcousticProfileStore.save(profile);
      final loaded = (await AcousticProfileStore.load())!;
      expect(loaded.roomType, 'Studio');
      expect(loaded.placement, InstallLocation.desk);
      expect(loaded.listeningTaste, ListeningTaste.detailed);
      expect(loaded.listeningGoal, ListeningGoal.desktop);
      expect(loaded.previousTuneIds, ['tune-a']);
    });

    test('load returns null when nothing is stored', () async {
      expect(await AcousticProfileStore.load(), isNull);
    });

    test('corrupt stored value loads as null rather than throwing', () async {
      SharedPreferences.setMockInitialValues(
          {'tunai_acoustic_profile_v1': 'not json {{{'});
      expect(await AcousticProfileStore.load(), isNull);
    });

    test('clear removes the stored profile', () async {
      await AcousticProfileStore.save(const AcousticProfile(roomType: 'X'));
      await AcousticProfileStore.clear();
      expect(await AcousticProfileStore.load(), isNull);
    });
  });

  group('FactorySoundProfile — factory sound INTENT (perceptual only)', () {
    test('TUNAI ONE default carries voicing intent, no tuning numbers', () {
      const p = FactorySoundProfile.tunaiOne;
      expect(p.speakerModel, 'TUNAI ONE');
      expect(p.targetCharacter, 'natural_balanced');
      expect(p.factoryIntent, 'accurate_long_listening');
      expect(p.listeningGoal, 'comfortable_detail');
      final json = p.toJson();
      final serialized = json.toString().toLowerCase();
      for (final forbidden in [
        'frequency', 'gain', 'q:', 'hz', 'db', 'bands', 'crossover', 'delay',
        'limiter', 'register',
      ]) {
        expect(serialized.contains(forbidden), isFalse);
      }
    });

    test('round-trips through JSON (delivered/stored read path)', () {
      // Consumer obtains a profile only by deserializing a Pro-authored one —
      // the value constructor is private on purpose (Pro authors, Consumer
      // reads). This mirrors a profile delivered as data.
      final p = FactorySoundProfile.fromJson(const {
        'speakerModel': 'TUNAI ONE',
        'targetCharacter': 'warm',
        'factoryIntent': 'musical',
        'listeningGoal': 'relaxed',
        'safeOperatingRange': 'gentle',
      });
      final back = FactorySoundProfile.fromJson(p.toJson());
      expect(back.speakerModel, 'TUNAI ONE');
      expect(back.targetCharacter, 'warm');
      expect(back.factoryIntent, 'musical');
      expect(back.listeningGoal, 'relaxed');
      expect(back.safeOperatingRange, 'gentle');
    });

    test('Consumer read-only access via the registry (Pro authors, Consumer '
        'reads)', () {
      expect(FactorySoundProfileRegistry.consumerReference().speakerModel,
          'TUNAI ONE');
      expect(FactorySoundProfileRegistry.forModel('TUNAI ONE'), isNotNull);
      expect(FactorySoundProfileRegistry.forModel('UNKNOWN'), isNull);
    });

    test('legacy field names still load (backward compat)', () {
      final back = FactorySoundProfile.fromJson({
        'model': 'TUNAI ONE',
        'factoryTarget': 'neutral',
        'safeCorrectionRange': 'moderate',
      });
      expect(back.speakerModel, 'TUNAI ONE');
      expect(back.targetCharacter, 'neutral');
      expect(back.safeOperatingRange, 'moderate');
    });
  });

  group('ListeningTaste', () {
    test('all values round-trip and default to natural on garbage', () {
      for (final t in ListeningTaste.values) {
        expect(ListeningTaste.fromJson(t.toJson()), t);
      }
      expect(ListeningTaste.fromJson('nonsense'), ListeningTaste.natural);
      expect(ListeningTaste.fromJson(null), ListeningTaste.natural);
    });

    test('labels exist in both locales and contain no engineering terms', () {
      for (final t in ListeningTaste.values) {
        for (final ko in [true, false]) {
          final label = t.label(ko: ko);
          final desc = t.description(ko: ko);
          expect(label.trim(), isNotEmpty);
          expect(desc.trim(), isNotEmpty);
          for (final term in ['dB', 'Hz', 'PEQ', 'EQ', 'DSP']) {
            expect(label.contains(term), isFalse);
            expect(desc.contains(term), isFalse);
          }
        }
      }
    });
  });

  group('AcousticProfile.intent storage (Phase 3-6)', () {
    test('a confirmed intent round-trips through save/load', () async {
      const profile = AcousticProfile(
        roomType: 'Living Room',
        listeningTaste: ListeningTaste.warm,
        intent: AcousticIntent(
          soundCharacter: SoundCharacter.warm,
          bassPreference: BassPreference.natural,
          listeningGoal: ListeningGoal.longListening,
          listeningFatigue: 'low',
          confidence: IntentConfidence.high,
        ),
      );
      await AcousticProfileStore.save(profile);
      final loaded = (await AcousticProfileStore.load())!;
      expect(loaded.intent, isNotNull);
      expect(loaded.intent!.soundCharacter, SoundCharacter.warm);
      expect(loaded.intent!.bassPreference, BassPreference.natural);
      expect(loaded.intent!.listeningGoal, ListeningGoal.longListening);
      expect(loaded.intent!.listeningFatigue, 'low');
    });

    test('a profile with no intent loads with intent == null', () async {
      await AcousticProfileStore.save(const AcousticProfile(roomType: 'X'));
      final loaded = (await AcousticProfileStore.load())!;
      expect(loaded.intent, isNull);
    });

    test('a stored intent carrying a forbidden DSP field is dropped on load', () async {
      // Simulate a corrupted/hand-edited store where a DSP value slipped into
      // the persisted intent. AcousticIntent.of must reject it → intent null.
      SharedPreferences.setMockInitialValues({
        'tunai_acoustic_profile_v1':
            '{"roomType":"R","listeningTaste":"warm","intent":{"soundCharacter":"warm","frequency":120},"previousTuneIds":[]}',
      });
      final loaded = (await AcousticProfileStore.load())!;
      expect(loaded.intent, isNull,
          reason: 'a DSP field in a stored intent must never survive load');
      expect(loaded.listeningTaste, ListeningTaste.warm);
    });
  });

}

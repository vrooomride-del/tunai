import 'package:flutter_test/flutter_test.dart';
import 'package:tunai/core/acoustic_intent.dart';
import 'package:tunai/core/correction_plan.dart';

void main() {
  group('AcousticIntent — JSON generation (8.1)', () {
    test('parses the documented example', () {
      final intent = AcousticIntent.of({
        'soundCharacter': 'warm',
        'listeningFatigue': 'low',
        'bassPreference': 'natural',
        'vocalPreference': 'natural',
        'confidence': 'high',
      })!;
      expect(intent.soundCharacter, SoundCharacter.warm);
      expect(intent.listeningFatigue, 'low');
      expect(intent.bassPreference, BassPreference.natural);
      expect(intent.vocalPreference, VocalPreference.natural);
      expect(intent.confidence, IntentConfidence.high);
    });

    test('round-trips through toJson()', () {
      const intent = AcousticIntent(
        soundCharacter: SoundCharacter.relaxed,
        listeningGoal: ListeningGoal.longListening,
        confidence: IntentConfidence.medium,
      );
      final back = AcousticIntent.of(intent.toJson())!;
      expect(back.soundCharacter, SoundCharacter.relaxed);
      expect(back.listeningGoal, ListeningGoal.longListening);
      expect(back.confidence, IntentConfidence.medium);
    });

    test('unknown enum values are dropped, not guessed', () {
      final intent = AcousticIntent.of({
        'soundCharacter': 'bass_cannon', // not an allowed value
        'bassPreference': 'natural',
        'confidence': 'high',
      })!;
      expect(intent.soundCharacter, isNull);
      expect(intent.bassPreference, BassPreference.natural);
    });

    test('a response with no usable signal yields null', () {
      expect(AcousticIntent.of(null), isNull);
      expect(AcousticIntent.of({}), isNull);
      expect(AcousticIntent.of({'confidence': 'high'}), isNull);
    });
  });

  group('AcousticIntent — DSP field rejection (8.2)', () {
    test('ANY forbidden engineering key rejects the whole response', () {
      for (final bad in [
        {'soundCharacter': 'warm', 'frequency': 120},
        {'soundCharacter': 'warm', 'gainDb': -3.0},
        {'bassPreference': 'natural', 'q': 4.0},
        {'soundCharacter': 'warm', 'filter': 'peaking'},
        {'soundCharacter': 'warm', 'peq': []},
        {'soundCharacter': 'warm', 'bands': []},
        {'soundCharacter': 'warm', 'crossover': 2000},
        {'soundCharacter': 'warm', 'register': '0x0824'},
        {'soundCharacter': 'warm', 'DSP': true},
      ]) {
        expect(AcousticIntent.of(bad), isNull,
            reason: 'must reject response carrying ${bad.keys}');
      }
    });

    test('rejection is case-insensitive on the key', () {
      expect(AcousticIntent.of({'soundCharacter': 'warm', 'Frequency': 100}),
          isNull);
      expect(
          AcousticIntent.of({'soundCharacter': 'warm', 'GAIN': -2}), isNull);
    });

    test('a clean perceptual response is accepted', () {
      expect(
          AcousticIntent.of({'soundCharacter': 'warm', 'confidence': 'high'}),
          isNotNull);
    });
  });

  group('CorrectionPlan — carries NO DSP values (8.4)', () {
    test('serialized form contains only perceptual fields', () {
      const plan = CorrectionPlan(
        problem: AcousticProblem.bassBoom,
        goal: CorrectionGoal.tighterLowEnd,
        priority: CorrectionPriority.userPreference,
      );
      final json = plan.toJson();
      expect(json.keys.toSet(),
          {'problem', 'goal', 'priority', 'strategy', 'allowed'});
      for (final forbidden in [
        'frequency', 'gain', 'gainDb', 'q', 'filter', 'peq', 'bands',
        'crossover', 'register', 'dsp', 'hz', 'db',
      ]) {
        expect(json.containsKey(forbidden), isFalse);
      }
    });

    test('round-trips through JSON', () {
      const plan = CorrectionPlan(
        problem: AcousticProblem.harshTreble,
        goal: CorrectionGoal.smootherTreble,
        priority: CorrectionPriority.measurement,
        allowed: false,
      );
      final back = CorrectionPlan.fromJson(plan.toJson());
      expect(back.problem, AcousticProblem.harshTreble);
      expect(back.goal, CorrectionGoal.smootherTreble);
      expect(back.priority, CorrectionPriority.measurement);
      expect(back.allowed, isFalse);
    });

    test('the type exposes no numeric member at all', () {
      // Compile-time guarantee via the public surface: the only fields are
      // enums + a bool. This test documents intent; the toJson assertion above
      // is the enforceable check.
      const plan =
          CorrectionPlan(problem: AcousticProblem.boxyMidrange, goal: CorrectionGoal.clearerMidrange);
      expect(plan.allowed, isTrue);
      expect(plan.priority, CorrectionPriority.balanced);
    });
  });
}

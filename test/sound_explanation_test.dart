import 'package:flutter_test/flutter_test.dart';
import 'package:tunai/core/correction_plan.dart';
import 'package:tunai/core/factory_sound_profile.dart';
import 'package:tunai/core/personal_optimization_context.dart';
import 'package:tunai/core/sound_explanation.dart';

const _gen = SoundExplanationGenerator();

// Consumer-language guarantee: no explanation string, in any locale, may carry
// an engineering term.
const _forbidden = [
  'Hz', 'hz', 'dB', 'db', 'PEQ', 'peq', 'EQ', 'DSP', 'dsp', 'filter', 'gain',
  'frequency', ' Q ', 'crossover', 'register', '주파수', '데시벨',
];

void _assertClean(SoundExplanation e) {
  for (final msg in [
    e.factoryMessage,
    e.roomMessage,
    e.preferenceMessage,
    e.overallMessage,
  ]) {
    if (msg == null) continue;
    for (final term in _forbidden) {
      expect(msg.contains(term), isFalse,
          reason: 'explanation must not contain "$term": "$msg"');
    }
  }
}

void main() {
  group('SoundExplanationGenerator — deterministic, consumer-language', () {
    test('the documented example: factory natural + room bass boom + warm', () {
      const context = PersonalOptimizationContext(
        factoryReference: FactorySoundProfile.tunaiOne,
        roomCondition: 'bassBoom',
        userPreference: 'warm',
        listeningIntent: {'placement': 'desk', 'listeningGoal': 'longListening'},
      );
      final e = _gen.generate(context,
          plan: const CorrectionPlan(
            problem: AcousticProblem.bassBoom,
            goal: CorrectionGoal.tighterLowEnd,
            strategy: CorrectionStrategy.reduceRoomExcess,
          ));
      expect(e.hasContent, isTrue);
      expect(e.roomMessage, contains('책상'));
      expect(e.roomMessage, contains('저역'));
      expect(e.factoryMessage, contains('TUNAI ONE'));
      expect(e.factoryMessage, contains('자연스러운'));
      expect(e.preferenceMessage, isNotNull); // longListening reflected
      expect(e.overallMessage, isNotNull);
      _assertClean(e);
    });

    test('is deterministic — same input, identical output', () {
      const context = PersonalOptimizationContext(
        factoryReference: FactorySoundProfile.tunaiOne,
        roomCondition: 'bassBoom',
        userPreference: 'warm',
      );
      final a = _gen.generate(context);
      final b = _gen.generate(context);
      expect(a.roomMessage, b.roomMessage);
      expect(a.factoryMessage, b.factoryMessage);
      expect(a.overallMessage, b.overallMessage);
    });

    test('a balanced room says little needed changing, does not invent a fix',
        () {
      const context = PersonalOptimizationContext(
        factoryReference: FactorySoundProfile.tunaiOne,
        roomCondition: 'balanced',
      );
      final e = _gen.generate(context);
      expect(e.roomMessage, contains('균형'));
      expect(e.preferenceMessage, isNull); // no user override
      _assertClean(e);
    });

    test('no factory reference → no factory message (never fabricated)', () {
      const context = PersonalOptimizationContext(roomCondition: 'bassBoom');
      final e = _gen.generate(context);
      expect(e.factoryMessage, isNull);
      expect(e.roomMessage, isNotNull);
      _assertClean(e);
    });

    test('natural / no preference → no preference message', () {
      const context = PersonalOptimizationContext(
        factoryReference: FactorySoundProfile.tunaiOne,
        roomCondition: 'bassBoom',
        userPreference: 'natural',
      );
      expect(_gen.generate(context).preferenceMessage, isNull);
    });

    test('fillRoomDip strategy changes the room wording', () {
      const context = PersonalOptimizationContext(
        factoryReference: FactorySoundProfile.tunaiOne,
        roomCondition: 'bassBoom',
      );
      final fill = _gen.generate(context,
          plan: const CorrectionPlan(
            problem: AcousticProblem.bassBoom,
            goal: CorrectionGoal.fullerLowEnd,
            strategy: CorrectionStrategy.fillRoomDip,
          ));
      expect(fill.roomMessage, contains('채웠습니다'));
      _assertClean(fill);
    });

    test('all preference variants render cleanly', () {
      for (final pref in ['warm', 'detailed', 'relaxed', 'vocal']) {
        final e = _gen.generate(PersonalOptimizationContext(
          factoryReference: FactorySoundProfile.tunaiOne,
          roomCondition: 'bassBoom',
          userPreference: pref,
        ));
        expect(e.preferenceMessage, isNotNull, reason: 'pref=$pref');
        _assertClean(e);
      }
    });

    test('an empty context still produces a safe overall message, no crash',
        () {
      const context = PersonalOptimizationContext(roomCondition: 'balanced');
      final e = _gen.generate(context);
      expect(e.overallMessage, isNotNull);
      _assertClean(e);
    });
  });

  group('Phase 4 — confidence-aware decision explanation', () {
    test('low confidence explains that the factory sound was preserved, not '
        'over-corrected', () {
      const context = PersonalOptimizationContext(
        factoryReference: FactorySoundProfile.tunaiOne,
        roomCondition: 'bassBoom',
        confidence: 'low',
      );
      final e = _gen.generate(context,
          plan: const CorrectionPlan(
            problem: AcousticProblem.bassBoom,
            goal: CorrectionGoal.tighterLowEnd,
            strategy: CorrectionStrategy.lowConfidenceIgnore,
          ));
      expect(e.roomMessage, contains('불안정'));
      expect(e.roomMessage, contains('유지'));
      _assertClean(e);
    });

    test('a held-back preference reads as CONSIDERED, never APPLIED', () {
      const context = PersonalOptimizationContext(
        factoryReference: FactorySoundProfile.tunaiOne,
        roomCondition: 'bassBoom',
        userPreference: 'warm',
        confidence: 'moderate',
      );
      final e = _gen.generate(context,
          plan: const CorrectionPlan(
            problem: AcousticProblem.bassBoom,
            goal: CorrectionGoal.tighterLowEnd,
            strategy: CorrectionStrategy.protectFactoryCharacter,
          ));
      expect(e.preferenceMessage, contains('참고'));
      expect(e.preferenceMessage, isNot(contains('반영')));
      _assertClean(e);
    });

    test('an applied preference on a stable measurement reads as REFLECTED', () {
      const context = PersonalOptimizationContext(
        factoryReference: FactorySoundProfile.tunaiOne,
        roomCondition: 'bassBoom',
        userPreference: 'warm',
        confidence: 'stable',
      );
      final e = _gen.generate(context,
          plan: const CorrectionPlan(
            problem: AcousticProblem.bassBoom,
            goal: CorrectionGoal.tighterLowEnd,
            strategy: CorrectionStrategy.reduceRoomExcess,
          ));
      expect(e.preferenceMessage, contains('반영'));
      _assertClean(e);
    });
  });

}

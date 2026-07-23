import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tunai/core/factory_sound_profile.dart';
import 'package:tunai/core/personal_optimization_context.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('OptimizationContextStore — per-Tune "why" memory (Phase 3-4)', () {
    test('saves and loads the perceptual reasons for a Tune, keyed by plan id',
        () async {
      const context = PersonalOptimizationContext(
        factoryReference: FactorySoundProfile.tunaiOne,
        roomCondition: 'bassBoom',
        userPreference: 'warm',
        listeningIntent: {'listeningGoal': 'longListening'},
      );
      await OptimizationContextStore.save('plan-1', context);
      final loaded = (await OptimizationContextStore.load('plan-1'))!;
      expect(loaded.roomCondition, 'bassBoom');
      expect(loaded.userPreference, 'warm');
      expect(loaded.factoryReference?.speakerModel, 'TUNAI ONE');
      expect(loaded.listeningIntent['listeningGoal'], 'longListening');
    });

    test('different plan ids do not collide', () async {
      await OptimizationContextStore.save(
          'a', const PersonalOptimizationContext(roomCondition: 'bassBoom'));
      await OptimizationContextStore.save(
          'b', const PersonalOptimizationContext(roomCondition: 'balanced'));
      expect((await OptimizationContextStore.load('a'))!.roomCondition,
          'bassBoom');
      expect((await OptimizationContextStore.load('b'))!.roomCondition,
          'balanced');
    });

    test('load returns null for an unknown plan id', () async {
      expect(await OptimizationContextStore.load('missing'), isNull);
    });

    test('corrupt stored value loads as null rather than throwing', () async {
      SharedPreferences.setMockInitialValues(
          {'tunai_opt_context_v1_x': 'not json {{'});
      expect(await OptimizationContextStore.load('x'), isNull);
    });

    test('the stored JSON contains no numeric DSP field', () async {
      const context = PersonalOptimizationContext(
        factoryReference: FactorySoundProfile.tunaiOne,
        roomCondition: 'bassBoom',
        userPreference: 'warm',
      );
      final serialized = context.toJson().toString().toLowerCase();
      for (final forbidden in [
        'frequency', 'hz', 'gain', 'db', 'q:', 'crossover', 'delay',
        'limiter', 'register', 'biquad',
      ]) {
        expect(serialized.contains(forbidden), isFalse);
      }
    });

    test('clear removes the stored context', () async {
      await OptimizationContextStore.save(
          'p', const PersonalOptimizationContext(roomCondition: 'bassBoom'));
      await OptimizationContextStore.clear('p');
      expect(await OptimizationContextStore.load('p'), isNull);
    });
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tunai/core/correction_evidence.dart';
import 'package:tunai/core/correction_plan.dart';
import 'package:tunai/core/factory_sound_profile.dart';
import 'package:tunai/core/personal_optimization_context.dart';
import 'package:tunai/core/tune_session.dart';

TuneSession _session(String id, {TuneFeedback feedback = TuneFeedback.none}) {
  const context = PersonalOptimizationContext(
    factoryReference: FactorySoundProfile.tunaiOne,
    roomCondition: 'bassBoom',
    userPreference: 'warm',
    confidence: 'stable',
  );
  const plan = CorrectionPlan(
    problem: AcousticProblem.bassBoom,
    goal: CorrectionGoal.tighterLowEnd,
    strategy: CorrectionStrategy.reduceRoomExcess,
  );
  return TuneSession(
    tuneId: id,
    timestamp: DateTime.utc(2026, 7, 23, 10, 30),
    factoryReference: FactorySoundProfile.tunaiOne,
    contextSummary: context,
    evidence: CorrectionEvidence.from(context: context, plan: plan),
    applied: true,
    feedback: feedback,
  );
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('TuneSession — model', () {
    test('round-trips through JSON', () {
      final s = _session('t1', feedback: TuneFeedback.liked);
      final back = TuneSession.fromJson(s.toJson());
      expect(back.tuneId, 't1');
      expect(back.timestamp.toUtc(), s.timestamp.toUtc());
      expect(back.factoryReference?.speakerModel, 'TUNAI ONE');
      expect(back.contextSummary.roomCondition, 'bassBoom');
      expect(back.evidence.reason, 'reduced_room_excess');
      expect(back.applied, isTrue);
      expect(back.feedback, TuneFeedback.liked);
    });

    test('carries NO numeric DSP value anywhere in its JSON', () {
      // The true invariant: a session is perceptual, so NO value in its JSON
      // tree is a number (DSP values are always numeric). This is stronger and
      // less brittle than substring checks — e.g. the key "feedback" legitimately
      // contains "db".
      void assertNoNumbers(Object? node) {
        if (node is num) {
          fail('session JSON must contain no numeric value, found: $node');
        } else if (node is Map) {
          node.forEach((k, v) {
            expect(k, isA<String>());
            assertNoNumbers(v);
          });
        } else if (node is List) {
          node.forEach(assertNoNumbers);
        }
      }

      assertNoNumbers(_session('t1').toJson());
      // And no engineering FIELD name is present either.
      final keys = _session('t1').toJson().toString().toLowerCase();
      for (final forbidden in [
        'frequency', 'gaindb', 'filter', 'peq', 'crossover', 'register',
        'biquad',
      ]) {
        expect(keys.contains(forbidden), isFalse, reason: 'found "$forbidden"');
      }
    });

    test('copyWith updates only applied/feedback', () {
      final s = _session('t1');
      final updated = s.copyWith(feedback: TuneFeedback.disliked);
      expect(updated.tuneId, 't1');
      expect(updated.feedback, TuneFeedback.disliked);
      expect(updated.evidence.reason, s.evidence.reason);
    });
  });

  group('TuneSessionStore — local, corruption-safe, best-effort', () {
    test('saves and loads a session', () async {
      await TuneSessionStore.save(_session('t1'));
      final loaded = await TuneSessionStore.load('t1');
      expect(loaded, isNotNull);
      expect(loaded!.tuneId, 't1');
      expect(loaded.evidence.reason, 'reduced_room_excess');
    });

    test('newest first, dedups by tuneId, and updates in place', () async {
      await TuneSessionStore.save(_session('a'));
      await TuneSessionStore.save(_session('b'));
      await TuneSessionStore.save(_session('a', feedback: TuneFeedback.liked));
      final all = await TuneSessionStore.loadAll();
      expect(all.map((s) => s.tuneId), ['a', 'b']);
      expect(all.first.feedback, TuneFeedback.liked);
    });

    test('setFeedback updates a stored session', () async {
      await TuneSessionStore.save(_session('t1'));
      await TuneSessionStore.setFeedback('t1', TuneFeedback.disliked);
      expect((await TuneSessionStore.load('t1'))!.feedback,
          TuneFeedback.disliked);
    });

    test('load returns null / loadAll returns empty when nothing stored',
        () async {
      expect(await TuneSessionStore.load('missing'), isNull);
      expect(await TuneSessionStore.loadAll(), isEmpty);
    });

    test('a corrupt store loads as empty history, never throws', () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('tunai_tune_sessions_v1', 'not json {{{');
      expect(await TuneSessionStore.loadAll(), isEmpty);
    });

    test('a single corrupt entry does not lose the whole history', () async {
      final valid = _session('good').toJson();
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('tunai_tune_sessions_v1',
          '[${_jsonEncode(valid)}, "not-a-map", 42]');
      final all = await TuneSessionStore.loadAll();
      // Non-map junk entries are skipped; the good one survives, no throw.
      expect(all.any((s) => s.tuneId == 'good'), isTrue);
    });

    test('setFeedback on a missing session is a safe no-op', () async {
      await TuneSessionStore.setFeedback('nope', TuneFeedback.liked);
      expect(await TuneSessionStore.load('nope'), isNull);
    });
  });
}

String _jsonEncode(Map<String, dynamic> m) {
  // Minimal inline encoder to avoid importing dart:convert twice in the test;
  // SharedPreferences mock takes the raw string.
  return _stringify(m);
}

String _stringify(Object? v) {
  if (v == null) return 'null';
  if (v is num || v is bool) return '$v';
  if (v is String) return '"${v.replaceAll('"', '\\"')}"';
  if (v is Map) {
    return '{${v.entries.map((e) => '"${e.key}":${_stringify(e.value)}').join(',')}}';
  }
  if (v is List) {
    return '[${v.map(_stringify).join(',')}]';
  }
  return '"$v"';
}

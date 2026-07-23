import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'correction_evidence.dart';
import 'factory_sound_profile.dart';
import 'personal_optimization_context.dart';

/// How the user felt about a Tune's result. Placeholder for a future learning
/// loop — captured locally, never yet sent anywhere.
enum TuneFeedback { none, liked, disliked }

/// One traceable record of a completed tuning decision — the Session Layer.
///
/// It ties together, for a single Tune, WHAT was preserved (the factory
/// reference), WHY the correction was chosen (the [CorrectionEvidence]), the
/// perceptual situation (a [PersonalOptimizationContext] summary), whether it
/// was applied, and an optional user feedback placeholder. This is the audit
/// trail for "what happened, and why" across a user's Tunes — the substrate a
/// Pro report or a future learning loop would read.
///
/// PERCEPTUAL ONLY. It stores no frequency, gain, Q, filter, crossover, delay,
/// limiter, or register — every member is a descriptor, an evidence record
/// (itself number-free), or a status. The numeric work stays entirely in
/// TunePlanner / Safety Validator.
@immutable
class TuneSession {
  final String tuneId;
  final DateTime timestamp;

  /// The factory voicing that was being preserved. Null when unknown.
  final FactorySoundProfile? factoryReference;

  /// Perceptual summary of the optimization context (room condition,
  /// confidence, preference, etc.) — the same number-free context object.
  final PersonalOptimizationContext contextSummary;

  /// The structured reason the correction was chosen.
  final CorrectionEvidence evidence;

  /// Whether the Tune was actually applied to the speaker.
  final bool applied;

  /// User's reaction, if given. Placeholder — no learning server yet.
  final TuneFeedback feedback;

  const TuneSession({
    required this.tuneId,
    required this.timestamp,
    required this.factoryReference,
    required this.contextSummary,
    required this.evidence,
    this.applied = false,
    this.feedback = TuneFeedback.none,
  });

  TuneSession copyWith({bool? applied, TuneFeedback? feedback}) => TuneSession(
        tuneId: tuneId,
        timestamp: timestamp,
        factoryReference: factoryReference,
        contextSummary: contextSummary,
        evidence: evidence,
        applied: applied ?? this.applied,
        feedback: feedback ?? this.feedback,
      );

  Map<String, dynamic> toJson() => {
        'tuneId': tuneId,
        'timestamp': timestamp.toUtc().toIso8601String(),
        if (factoryReference != null)
          'factoryReference': factoryReference!.toJson(),
        'contextSummary': contextSummary.toJson(),
        'evidence': evidence.toJson(),
        'applied': applied,
        'feedback': feedback.name,
      };

  factory TuneSession.fromJson(Map<String, dynamic> json) {
    TuneFeedback feedback = TuneFeedback.none;
    final rawFeedback = json['feedback'];
    if (rawFeedback is String) {
      for (final f in TuneFeedback.values) {
        if (f.name == rawFeedback) {
          feedback = f;
          break;
        }
      }
    }
    return TuneSession(
      tuneId: json['tuneId'] as String? ?? '',
      timestamp:
          DateTime.tryParse(json['timestamp'] as String? ?? '')?.toUtc() ??
              DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      factoryReference: json['factoryReference'] is Map
          ? FactorySoundProfile.fromJson(
              Map<String, dynamic>.from(json['factoryReference'] as Map))
          : null,
      contextSummary: json['contextSummary'] is Map
          ? PersonalOptimizationContext.fromJson(
              Map<String, dynamic>.from(json['contextSummary'] as Map))
          : const PersonalOptimizationContext(roomCondition: 'balanced'),
      evidence: json['evidence'] is Map
          ? CorrectionEvidence.fromJson(
              Map<String, dynamic>.from(json['evidence'] as Map))
          : CorrectionEvidence.fromJson(const {}),
      applied: json['applied'] is bool ? json['applied'] as bool : false,
      feedback: feedback,
    );
  }
}

/// Local, corruption-safe, best-effort persistence for [TuneSession]s.
///
/// Best-effort by contract: NO method here may ever throw into the Tune flow.
/// A save failure is swallowed (logged), and a corrupt/partial store loads as
/// an empty history rather than an error, so the Session Layer can never break
/// CONNECT → ROOM → TUNE → APPLY → LISTEN. Firebase / learning-server sync is
/// deliberately out of scope.
class TuneSessionStore {
  static const _key = 'tunai_tune_sessions_v1';
  static const _maxSessions = 50;

  /// Adds/updates a session (keyed by tuneId), newest first, capped. Never
  /// throws — a failure is logged and ignored.
  static Future<void> save(TuneSession session) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final existing = await _loadAll(prefs);
      final next = [
        session,
        ...existing.where((s) => s.tuneId != session.tuneId),
      ].take(_maxSessions).toList();
      await prefs.setString(
          _key, jsonEncode([for (final s in next) s.toJson()]));
    } catch (error) {
      debugPrint('[TUNE_SESSION] save skipped (non-fatal): $error');
    }
  }

  /// Loads all sessions, newest first. Returns empty on any problem.
  static Future<List<TuneSession>> loadAll() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      // MUST await: returning the future un-awaited would let a decode error
      // escape this try/catch and reach the caller.
      return await _loadAll(prefs);
    } catch (error) {
      debugPrint('[TUNE_SESSION] load failed (non-fatal): $error');
      return const [];
    }
  }

  /// Loads a single session by tuneId, or null.
  static Future<TuneSession?> load(String tuneId) async {
    final all = await loadAll();
    for (final s in all) {
      if (s.tuneId == tuneId) return s;
    }
    return null;
  }

  static Future<void> setFeedback(String tuneId, TuneFeedback feedback) async {
    final existing = await load(tuneId);
    if (existing == null) return;
    await save(existing.copyWith(feedback: feedback));
  }

  static Future<void> clear() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_key);
    } catch (_) {}
  }

  static Future<List<TuneSession>> _loadAll(SharedPreferences prefs) async {
    final raw = prefs.getString(_key);
    if (raw == null) return const [];
    final decoded = jsonDecode(raw);
    if (decoded is! List) return const [];
    final out = <TuneSession>[];
    for (final item in decoded) {
      if (item is Map) {
        try {
          out.add(TuneSession.fromJson(Map<String, dynamic>.from(item)));
        } catch (_) {
          // Skip a single corrupt entry rather than losing the whole history.
        }
      }
    }
    return out;
  }
}

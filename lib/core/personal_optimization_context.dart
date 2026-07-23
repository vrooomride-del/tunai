import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'factory_sound_profile.dart';

/// The complete, perceptual picture the engine reasons about when personalising
/// a speaker's factory sound for one user's room.
///
/// This is the explicit statement of TUNAI's philosophy: it bundles the FOUR
/// independent inputs — the factory reference (the sound to PRESERVE), the room
/// condition (what to CORRECT), the user preference (what they LIKE), and the
/// listening intent (what they ASKED for) — and keeps them separate. None of
/// them overrides another; the [factoryReference] in particular is a baseline
/// to protect, never a target to tune toward and never something that silences
/// the user's own preference.
///
/// PERCEPTUAL ONLY — no frequency, gain, Q, crossover, delay, limiter, or
/// register. It carries descriptors and a [FactorySoundProfile] (itself
/// number-free); the numeric work stays entirely in TunePlanner / Safety
/// Validator, unchanged.
@immutable
class PersonalOptimizationContext {
  /// The finished, manufacturer-voiced sound to preserve. Null when unknown.
  final FactorySoundProfile? factoryReference;

  /// What the ROOM is doing that differs from the factory intent, as a coarse
  /// perceptual descriptor: e.g. 'bass_boom', 'boxy_midrange', 'balanced'.
  final String roomCondition;

  /// The user's own preference descriptor (from picker/taste), e.g. 'warm',
  /// 'natural'; null when they expressed none.
  final String? userPreference;

  /// What the user explicitly asked for, as perceptual descriptors from the
  /// intent layer (e.g. {'soundCharacter':'warm','listeningGoal':'longListening'}).
  /// Empty when no request was made.
  final Map<String, String> listeningIntent;

  /// How much the measurement can be TRUSTED — 'stable' / 'moderate' / 'low',
  /// bucketed from the capture's real split-half agreement (see
  /// `CaptureAnalysis.agreement`). A measured value, never guessed. Drives the
  /// judgment layer: a low-confidence reading is not aggressively corrected.
  final String confidence;

  /// The capture's own quality classification (e.g. 'valid'/'degraded'),
  /// from [CaptureQualityStatus] — a real property of the recording, not an
  /// inference.
  final String? measurementQuality;

  const PersonalOptimizationContext({
    this.factoryReference,
    required this.roomCondition,
    this.userPreference,
    this.listeningIntent = const {},
    this.confidence = 'stable',
    this.measurementQuality,
  });

  /// Whether the user contributed any preference or request at all. When false,
  /// personalization reduces to "preserve factory, correct the room" — the
  /// exact behaviour of the pre-personalization flow.
  bool get hasUserSignal =>
      (userPreference != null && userPreference!.isNotEmpty) ||
      listeningIntent.isNotEmpty;

  Map<String, dynamic> toJson() => {
        if (factoryReference != null)
          'factoryReference': factoryReference!.toJson(),
        'roomCondition': roomCondition,
        if (userPreference != null) 'userPreference': userPreference,
        if (listeningIntent.isNotEmpty) 'listeningIntent': listeningIntent,
        'confidence': confidence,
        if (measurementQuality != null) 'measurementQuality': measurementQuality,
      };

  factory PersonalOptimizationContext.fromJson(Map<String, dynamic> json) =>
      PersonalOptimizationContext(
        factoryReference: json['factoryReference'] is Map
            ? FactorySoundProfile.fromJson(
                Map<String, dynamic>.from(json['factoryReference'] as Map))
            : null,
        roomCondition: json['roomCondition'] as String? ?? 'balanced',
        userPreference: json['userPreference'] as String?,
        listeningIntent: json['listeningIntent'] is Map
            ? {
                for (final e in (json['listeningIntent'] as Map).entries)
                  if (e.value is String) e.key.toString(): e.value as String,
              }
            : const {},
        confidence: json['confidence'] as String? ?? 'stable',
        measurementQuality: json['measurementQuality'] as String?,
      );
}

/// Per-Tune storage of WHY a Tune was created — the perceptual reasons, keyed
/// by the Tune's plan id. This is the memory layer: it lets the app later say
/// "this Tune preserved TUNAI ONE's natural balance while calming a room bass
/// boom, toward your warm preference" without recomputing anything.
///
/// Stores ONLY perceptual descriptors (factory intent, room condition,
/// preference, listening intent). It is structurally incapable of holding a
/// DSP value because [PersonalOptimizationContext] has no numeric field. Local
/// only; Firebase sync is out of scope. Corruption-safe.
class OptimizationContextStore {
  static String _key(String planId) => 'tunai_opt_context_v1_$planId';

  static Future<void> save(
      String planId, PersonalOptimizationContext context) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key(planId), jsonEncode(context.toJson()));
  }

  static Future<PersonalOptimizationContext?> load(String planId) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key(planId));
    if (raw == null) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      return PersonalOptimizationContext.fromJson(
          Map<String, dynamic>.from(decoded));
    } catch (_) {
      return null;
    }
  }

  static Future<void> clear(String planId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key(planId));
  }
}

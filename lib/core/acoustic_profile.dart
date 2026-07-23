import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'acoustic_intent.dart' show AcousticIntent, ListeningGoal;
import 'install_location.dart';
import 'listening_taste.dart';

/// A durable, per-user personalization context for a room + speaker setup.
///
/// STRUCTURE ONLY in this batch — deliberately NOT connected to [TunePlanner],
/// the DSP path, or any correction math. It exists so a future personalization
/// feature ("remember this room / carry my taste across Tunes") has a stable
/// model and serialization to build on, without a later breaking migration.
///
/// Everything here is either a user's explicit choice ([roomType],
/// [placement], [listeningTaste]) or a reference to Tunes that genuinely
/// happened ([previousTuneIds]) — nothing measured is invented, and no
/// improvement or score is stored. The Acoustic Intelligence Layer may READ
/// this for richer context; it still never produces DSP values.
class AcousticProfile {
  /// User-chosen room descriptor (same vocabulary as [ConsumerSoundProfile]).
  final String roomType;

  /// User-chosen speaker placement; null when never selected. Context only —
  /// it never affects measurement (see [InstallLocation]).
  final InstallLocation? placement;

  /// User's stated listening taste. Not connected to EQ (see
  /// [ListeningTaste]); carried here for future personalization.
  final ListeningTaste listeningTaste;

  /// What the user primarily listens for. Context only — not connected to any
  /// correction math in this batch.
  final ListeningGoal? listeningGoal;

  /// The perceptual intent the AI extracted from the user's natural-language
  /// request, once the user CONFIRMED it (see the intent-input flow). Null when
  /// the user never gave a request or declined to confirm. Perceptual only —
  /// [AcousticIntent] structurally cannot hold a DSP value.
  final AcousticIntent? intent;

  /// Ids of Tunes previously created for this setup, oldest first. Plain
  /// references to real [TunePlan] ids — no scores, no fabricated history.
  final List<String> previousTuneIds;

  const AcousticProfile({
    required this.roomType,
    this.placement,
    this.listeningTaste = ListeningTaste.natural,
    this.listeningGoal,
    this.intent,
    this.previousTuneIds = const [],
  });

  AcousticProfile copyWith({
    String? roomType,
    InstallLocation? placement,
    ListeningTaste? listeningTaste,
    ListeningGoal? listeningGoal,
    AcousticIntent? intent,
    List<String>? previousTuneIds,
  }) =>
      AcousticProfile(
        roomType: roomType ?? this.roomType,
        placement: placement ?? this.placement,
        listeningTaste: listeningTaste ?? this.listeningTaste,
        listeningGoal: listeningGoal ?? this.listeningGoal,
        intent: intent ?? this.intent,
        previousTuneIds: previousTuneIds ?? this.previousTuneIds,
      );

  /// Appends a real Tune id to the history (dedup, order preserved).
  AcousticProfile withTune(String tuneId) => previousTuneIds.contains(tuneId)
      ? this
      : copyWith(previousTuneIds: [...previousTuneIds, tuneId]);

  Map<String, dynamic> toJson() => {
        'roomType': roomType,
        if (placement != null) 'placement': placement!.name,
        'listeningTaste': listeningTaste.toJson(),
        if (listeningGoal != null) 'listeningGoal': listeningGoal!.name,
        if (intent != null) 'intent': intent!.toJson(),
        'previousTuneIds': previousTuneIds,
      };

  factory AcousticProfile.fromJson(Map<String, dynamic> json) {
    InstallLocation? placement;
    final rawPlacement = json['placement'];
    if (rawPlacement is String) {
      for (final loc in InstallLocation.values) {
        if (loc.name == rawPlacement) {
          placement = loc;
          break;
        }
      }
    }
    ListeningGoal? goal;
    final rawGoal = json['listeningGoal'];
    if (rawGoal is String) {
      for (final g in ListeningGoal.values) {
        if (g.name == rawGoal) {
          goal = g;
          break;
        }
      }
    }
    final rawIntent = json['intent'];
    final intent = rawIntent is Map
        ? AcousticIntent.of(Map<String, dynamic>.from(rawIntent))
        : null;
    final rawIds = json['previousTuneIds'];
    return AcousticProfile(
      roomType: json['roomType'] as String? ?? '',
      placement: placement,
      listeningTaste: ListeningTaste.fromJson(json['listeningTaste'] as String?),
      listeningGoal: goal,
      intent: intent,
      previousTuneIds: rawIds is List
          ? List.unmodifiable(rawIds.whereType<String>())
          : const [],
    );
  }
}

/// Local, on-device persistence for the user's [AcousticProfile] — a single
/// current profile, in SharedPreferences. Firebase sync is deliberately out
/// of scope for this batch (structure/storage foundation only).
///
/// Corruption-safe: a malformed stored value is treated as "no profile"
/// rather than throwing, so a bad write can never brick the flow.
class AcousticProfileStore {
  static const _key = 'tunai_acoustic_profile_v1';

  static Future<void> save(AcousticProfile profile) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode(profile.toJson()));
  }

  static Future<AcousticProfile?> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      return AcousticProfile.fromJson(Map<String, dynamic>.from(decoded));
    } catch (_) {
      return null;
    }
  }

  static Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
  }
}

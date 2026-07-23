import 'package:flutter/foundation.dart';

/// Overall tonal character the user is after.
enum SoundCharacter { natural, warm, detailed, energetic, relaxed }

/// How the user wants the low end handled.
enum BassPreference { controlled, natural, powerful }

/// How present the user wants vocals.
enum VocalPreference { natural, forward }

/// What the user is primarily listening to / for.
enum ListeningGoal { music, movie, desktop, longListening }

/// How confident the intent extraction is.
enum IntentConfidence { low, medium, high }

/// The user's listening INTENT, expressed entirely in perceptual terms.
///
/// This is the "User Intent Layer" of the Acoustic Intelligence Engine — a
/// structured, perceptual translation of what the user asked for ("warm,
/// easy to listen to for hours"). It is NOT a correction and NOT a DSP
/// instruction: it never carries frequency, gain, Q, filter, or any register
/// value, and [AcousticIntent.of] hard-rejects a response that tries to
/// include one. The deterministic engine downstream is the only thing that
/// ever turns intent into numbers.
///
/// Every field is nullable / defaulted so a partial or low-confidence
/// extraction degrades gracefully rather than fabricating certainty.
@immutable
class AcousticIntent {
  final SoundCharacter? soundCharacter;
  final BassPreference? bassPreference;
  final VocalPreference? vocalPreference;
  final ListeningGoal? listeningGoal;

  /// Low = comfortable for long sessions; not every extraction infers it.
  final String? listeningFatigue; // 'low' | 'moderate' | 'high'
  final IntentConfidence confidence;

  const AcousticIntent({
    this.soundCharacter,
    this.bassPreference,
    this.vocalPreference,
    this.listeningGoal,
    this.listeningFatigue,
    this.confidence = IntentConfidence.low,
  });

  bool get hasAnySignal =>
      soundCharacter != null ||
      bassPreference != null ||
      vocalPreference != null ||
      listeningGoal != null ||
      (listeningFatigue != null && listeningFatigue!.isNotEmpty);

  /// Any of these keys appearing in an AI response means the model tried to
  /// produce a DSP/engineering value — a hard contract violation. Such a
  /// response is REJECTED wholesale (returns null), never partially accepted,
  /// so a prompt-injected or misbehaving model can never leak a tuning value
  /// into the intent layer.
  static const _forbiddenKeys = {
    'frequency', 'freq', 'hz',
    'gain', 'gaindb', 'db',
    'q',
    'filter', 'peq', 'eq',
    'crossover', 'xover',
    'register', 'address', 'dsp',
    'bands', 'band', 'coefficient', 'biquad',
  };

  /// Parses a Gemini intent response defensively.
  ///
  /// Returns null when the response is empty, carries no usable signal, OR
  /// contains any forbidden DSP field (see [_forbiddenKeys]) — the last is a
  /// safety rejection, not a parse failure, and is logged as such.
  static AcousticIntent? of(Map<String, dynamic>? json) {
    if (json == null) return null;

    for (final key in json.keys) {
      if (_forbiddenKeys.contains(key.toLowerCase())) {
        debugPrint('[INTENT] REJECTED — response carried a forbidden DSP '
            'field "$key". The AI must never produce tuning values.');
        return null;
      }
    }

    final intent = AcousticIntent(
      soundCharacter: _enumByName(json['soundCharacter'], SoundCharacter.values),
      bassPreference: _enumByName(json['bassPreference'], BassPreference.values),
      vocalPreference:
          _enumByName(json['vocalPreference'], VocalPreference.values),
      listeningGoal: _enumByName(json['listeningGoal'], ListeningGoal.values),
      listeningFatigue: _fatigue(json['listeningFatigue']),
      confidence: _enumByName(json['confidence'], IntentConfidence.values) ??
          IntentConfidence.low,
    );
    return intent.hasAnySignal ? intent : null;
  }

  Map<String, dynamic> toJson() => {
        if (soundCharacter != null) 'soundCharacter': soundCharacter!.name,
        if (bassPreference != null) 'bassPreference': bassPreference!.name,
        if (vocalPreference != null) 'vocalPreference': vocalPreference!.name,
        if (listeningGoal != null) 'listeningGoal': listeningGoal!.name,
        if (listeningFatigue != null) 'listeningFatigue': listeningFatigue,
        'confidence': confidence.name,
      };

  static T? _enumByName<T extends Enum>(Object? raw, List<T> values) {
    if (raw is! String) return null;
    for (final v in values) {
      if (v.name == raw) return v;
    }
    return null;
  }

  static String? _fatigue(Object? raw) {
    if (raw is! String) return null;
    final v = raw.trim().toLowerCase();
    return const {'low', 'moderate', 'high'}.contains(v) ? v : null;
  }
}

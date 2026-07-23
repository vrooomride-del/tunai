import 'package:flutter/foundation.dart';

/// The speaker's factory voicing INTENT — the "target direction" half of:
///
///   Factory Sound Intent + Room State + User Preference + User Request
///        → CorrectionPlan → TunePlanner → Safety Validator → DSP
///
/// This is the anchor of TUNAI's identity: TUNAI is NOT a room EQ. Every
/// correction is a re-interpretation of the speaker's factory sound intent for
/// the user's room and taste — never a blank-slate flattening.
///
/// PRODUCT BOUNDARY (Pro authors / Consumer reads):
/// A FactorySoundProfile is AUTHORED in TUNAI PRO (manufacturing / expert
/// tooling: speaker measurement, DSP tuning, factory voicing, protection
/// settings, speaker identity). The Consumer app NEVER authors one — it only
/// READS a Pro-authored profile that ships with the app or is delivered as
/// data. To enforce that, the value constructor is PRIVATE: within this
/// (Consumer) codebase a profile can only be obtained from
/// [FactorySoundProfileRegistry] (the baked-in Pro-authored catalog) or from
/// [FactorySoundProfile.fromJson] (a delivered/stored profile). Consumer code
/// cannot fabricate arbitrary factory voicings.
///
/// PERCEPTUAL ONLY — every field is a descriptor, never a number. There is no
/// frequency, gain, Q, crossover, delay, limiter, or register here, and there
/// never will be: the real, enforced safe limits live in [TuneSafetyBounds] /
/// [TuneSafetyValidator], unchanged. [safeOperatingRange] is a coarse,
/// human-facing word ('gentle'/'moderate'), not the enforced math. The actual
/// DSP-value authoring is a Pro-only concern and lives nowhere in this app.
@immutable
class FactorySoundProfile {
  final String speakerModel;

  /// Factory voicing character, perceptual: e.g. 'natural_balanced', 'warm'.
  final String targetCharacter;

  /// What the speaker was voiced FOR: e.g. 'accurate_long_listening'.
  final String factoryIntent;

  /// The listening experience the factory voicing targets: e.g.
  /// 'comfortable_detail'.
  final String listeningGoal;

  /// Coarse, human-facing tolerance for correction ('gentle'/'moderate').
  /// NOT a dB/Hz limit — the enforced limits remain in TuneSafetyBounds.
  final String safeOperatingRange;

  /// PRIVATE — authoring a factory voicing is a TUNAI PRO concern. Consumer
  /// code obtains profiles only via [FactorySoundProfileRegistry] or
  /// [fromJson]; it never calls this.
  const FactorySoundProfile._({
    required this.speakerModel,
    this.targetCharacter = 'natural_balanced',
    this.factoryIntent = 'accurate_long_listening',
    this.listeningGoal = 'comfortable_detail',
    this.safeOperatingRange = 'moderate',
  });

  /// The Pro-authored profile for TUNAI ONE, baked into the Consumer app.
  /// Voicing intent only — no numbers. Read-only.
  static const tunaiOne = FactorySoundProfile._(
    speakerModel: 'TUNAI ONE',
    targetCharacter: 'natural_balanced',
    factoryIntent: 'accurate_long_listening',
    listeningGoal: 'comfortable_detail',
    safeOperatingRange: 'moderate',
  );

  Map<String, dynamic> toJson() => {
        'speakerModel': speakerModel,
        'targetCharacter': targetCharacter,
        'factoryIntent': factoryIntent,
        'listeningGoal': listeningGoal,
        'safeOperatingRange': safeOperatingRange,
      };

  /// Deserializes a Pro-authored, delivered/stored profile. This is a READ
  /// path (reconstituting an existing profile), not authoring.
  factory FactorySoundProfile.fromJson(Map<String, dynamic> json) =>
      FactorySoundProfile._(
        // Accept the prior field name ('model') as a fallback so any value
        // stored before this expansion still loads.
        speakerModel: (json['speakerModel'] ?? json['model']) as String? ??
            'Unknown',
        targetCharacter: (json['targetCharacter'] ?? json['factoryTarget'])
                as String? ??
            'natural_balanced',
        factoryIntent:
            json['factoryIntent'] as String? ?? 'accurate_long_listening',
        listeningGoal: json['listeningGoal'] as String? ?? 'comfortable_detail',
        safeOperatingRange:
            (json['safeOperatingRange'] ?? json['safeCorrectionRange'])
                    as String? ??
                'moderate',
      );
}

/// The Consumer's READ-ONLY access to Pro-authored factory profiles.
///
/// Represents the catalog of factory voicings that TUNAI PRO has authored and
/// delivered into the Consumer app. Consumer code asks this for the profile of
/// the connected speaker; it never creates one. Today the catalog holds the
/// single shipping model (TUNAI ONE); as more speakers ship, Pro adds entries
/// here (or they are delivered as data and loaded via
/// [FactorySoundProfile.fromJson]).
class FactorySoundProfileRegistry {
  const FactorySoundProfileRegistry._();

  static const Map<String, FactorySoundProfile> _catalog = {
    'TUNAI ONE': FactorySoundProfile.tunaiOne,
  };

  /// The Pro-authored profile for [speakerModel], or null if unknown.
  static FactorySoundProfile? forModel(String speakerModel) =>
      _catalog[speakerModel];

  /// The factory reference the Consumer flow should preserve for the currently
  /// supported speaker. Read-only; the single sanctioned Consumer entry point.
  static FactorySoundProfile consumerReference() => FactorySoundProfile.tunaiOne;
}

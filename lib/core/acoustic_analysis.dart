import 'tune_plan.dart';
import 'tune_result_summary.dart';

/// The consumer-language result of the Acoustic Intelligence Layer.
///
/// This is the AI's ONLY job now: interpreting a measurement and its
/// already-deployed, deterministically-generated Tune into plain language,
/// plus placement advice. It never contains — and the AI never produces —
/// DSP band values, dB, Hz, Q, or any engineering term. Band generation
/// belongs entirely to [TunePlanner]; see [AcousticAnalysisDigest] for the
/// safe, pre-digested input the AI actually receives.
///
/// Every field is optional and independently omittable: [AcousticAnalysis.of]
/// keeps only what the AI actually returned as non-empty, so the UI shows a
/// field only when there is real content for it — never a placeholder.
class AcousticAnalysis {
  final String? summary;

  /// Plain-language statements of what the Tune actually changed.
  final List<String> changes;

  /// Placement guidance the AI derived from the chosen [placement]; null when
  /// no placement was given or the AI offered none.
  final String? placementAdvice;

  /// One sentence on the listening experience to expect. Never a quantified
  /// or fabricated improvement claim.
  final String? listeningAdvice;

  /// Optional plain-language note on measurement stability (kept from the
  /// prior schema; harmless and hidden when absent).
  final String? confidenceExplanation;

  const AcousticAnalysis({
    this.summary,
    this.changes = const [],
    this.placementAdvice,
    this.listeningAdvice,
    this.confidenceExplanation,
  });

  /// True only when there is at least one piece of real content to show.
  bool get hasContent =>
      (summary != null && summary!.trim().isNotEmpty) ||
      changes.isNotEmpty ||
      (placementAdvice != null && placementAdvice!.trim().isNotEmpty) ||
      (listeningAdvice != null && listeningAdvice!.trim().isNotEmpty) ||
      (confidenceExplanation != null &&
          confidenceExplanation!.trim().isNotEmpty);

  /// Parses a Gemini response defensively — anything missing, blank, or of an
  /// unexpected type is dropped rather than guessed at, so a partial or
  /// malformed response degrades to fewer fields instead of a fabricated one.
  static AcousticAnalysis? of(Map<String, dynamic>? json) {
    if (json == null) return null;

    String? str(Object? v) {
      if (v is! String) return null;
      final trimmed = v.trim();
      return trimmed.isEmpty ? null : trimmed;
    }

    final changes = <String>[];
    // Primary key is `changes`; `improvements` accepted as a legacy alias so a
    // server still on the old field name is not silently dropped.
    final rawChanges = json['changes'] ?? json['improvements'];
    if (rawChanges is List) {
      for (final item in rawChanges) {
        final s = str(item);
        if (s != null) changes.add(s);
      }
    }

    final analysis = AcousticAnalysis(
      summary: str(json['summary']),
      changes: List.unmodifiable(changes),
      placementAdvice: str(json['placementAdvice']),
      listeningAdvice: str(json['listeningAdvice']),
      confidenceExplanation: str(json['confidenceExplanation']),
    );
    return analysis.hasContent ? analysis : null;
  }
}

/// Coarse, engineering-term-free description of ONE corrected region — the
/// only thing about the Tune's actual numbers that the AI is ever shown.
enum ToneRegion { low, mid, high }

enum ToneDirection { reduced, lifted }

/// The safe input the Acoustic Intelligence Layer receives.
///
/// Deliberately carries NO raw dB / Hz / Q. It is built entirely from data
/// the app already has — the deployed [TunePlan] (bucketed into region +
/// direction, exactly as [TuneResultSummary] does for the offline card),
/// the capture's own repeatability confidence, and the user's chosen
/// placement — so that even the prompt sent to Gemini cannot leak an
/// engineering value, and the model has nothing to "recommend a band" from.
class AcousticAnalysisDigest {
  final List<({ToneRegion region, ToneDirection direction})> corrections;
  final bool usedRoomModeCorrection;
  final bool usedTonalBalanceCorrection;

  /// 0..1 split-half repeatability of the capture (see
  /// `CaptureAnalysis.agreement`), bucketed to a word for the AI.
  final String confidenceLabel;

  /// User-chosen placement, as a neutral descriptor (e.g. 'desktop',
  /// 'near_wall', 'living_room'); null if not chosen. Never a measured value.
  final String? placement;

  const AcousticAnalysisDigest({
    required this.corrections,
    required this.usedRoomModeCorrection,
    required this.usedTonalBalanceCorrection,
    required this.confidenceLabel,
    this.placement,
  });

  static const double _lowMidHz = 300;
  static const double _midHighHz = 2000;

  /// Builds a digest from the real deployed plan. Returns null when there is
  /// nothing real to describe (no plan / no bands), so the AI is never asked
  /// to narrate an empty correction.
  static AcousticAnalysisDigest? of({
    required TunePlan? plan,
    required double captureAgreement,
    String? placement,
  }) {
    if (plan == null || plan.bands.isEmpty) return null;

    // Net signed gain per region → a single direction per region, identical
    // to how the offline TuneResultSummary decides "tightened" vs "filled".
    final net = <ToneRegion, double>{};
    var roomMode = false, tonal = false;
    for (final band in plan.bands) {
      final region = band.frequencyHz < _lowMidHz
          ? ToneRegion.low
          : band.frequencyHz < _midHighHz
              ? ToneRegion.mid
              : ToneRegion.high;
      net[region] = (net[region] ?? 0) + band.gainDb;
      switch (band.source) {
        case TuneCorrectionSource.tonalBalance:
        case TuneCorrectionSource.preferenceTarget:
          tonal = true;
        case TuneCorrectionSource.roomMode:
        case TuneCorrectionSource.speakerCharacter:
          roomMode = true;
      }
    }

    final corrections = [
      for (final entry in net.entries)
        (
          region: entry.key,
          direction:
              entry.value < 0 ? ToneDirection.reduced : ToneDirection.lifted,
        ),
    ];
    if (corrections.isEmpty) return null;

    return AcousticAnalysisDigest(
      corrections: corrections,
      usedRoomModeCorrection: roomMode,
      usedTonalBalanceCorrection: tonal,
      confidenceLabel: captureAgreement >= 0.75
          ? 'stable'
          : captureAgreement >= 0.5
              ? 'moderate'
              : 'low',
      placement: placement,
    );
  }

  /// The wire payload for the `aiAnalyze` Cloud Function. Only coarse,
  /// non-technical descriptors — the server prompt is built from these.
  Map<String, dynamic> toJson() => {
        'corrections': [
          for (final c in corrections)
            {'region': c.region.name, 'direction': c.direction.name},
        ],
        'usedRoomModeCorrection': usedRoomModeCorrection,
        'usedTonalBalanceCorrection': usedTonalBalanceCorrection,
        'confidence': confidenceLabel,
        if (placement != null) 'placement': placement,
      };
}

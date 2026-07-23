import 'room_measurement.dart';
import 'sound_preference.dart';
import 'speaker_profile.dart';
import 'tune_outcome_history.dart';

/// Bundles what a future AI Orchestrator would need to reason about a Tune
/// request — the real Room Measurement, the user's chosen [SoundPreference],
/// and the [SpeakerProfile] if one is known.
///
/// This is a data-shaping step only. Nothing here calls Gemini or any
/// network service — `AiTuningService` (ai_tuning_service.dart) already has
/// a working Firebase→Gemini call, but it is not invoked anywhere in the
/// live Consumer flow yet, and connecting it is out of scope for this
/// batch. This class exists so that whenever that connection is made, the
/// AI has one clear, consistent input shape instead of ad-hoc parameters
/// scattered across call sites.
///
/// The "AI interprets, TUNAI validates, DSP executes" principle is
/// unaffected either way: any future AI-produced band list would still have
/// to pass through [TuneSafetyValidator] before reaching DSP Apply, exactly
/// like [TunePlanner]'s output does today. This class only prepares the
/// *input* side.
class AcousticIntelligenceContext {
  final RoomMeasurement measurement;
  final SoundPreference preference;
  final SpeakerProfile? speakerProfile;
  // Closed Loop: the last few real Tune Apply outcomes (see
  // tune_outcome_history.dart), if any — never fabricated, never a
  // simulated re-measurement. Empty/omitted whenever no real history exists
  // yet (e.g. first Tune ever created).
  final List<TuneOutcomeRecord> recentOutcomes;

  const AcousticIntelligenceContext({
    required this.measurement,
    required this.preference,
    this.speakerProfile,
    this.recentOutcomes = const [],
  });

  /// Same convention as [SpeakerProfile.toPromptMap] — a consumer-neutral,
  /// real-data-only summary. Every value here traces back to something
  /// actually measured or explicitly chosen by the user; nothing is
  /// invented to fill out the shape.
  Map<String, dynamic> toPromptMap() => {
        'measured_peaks': [
          for (final peak in measurement.peaks)
            {
              'frequency_hz': peak.frequency,
              'gain_db': peak.gain,
              'q': peak.q,
            },
        ],
        'measurement_quality': measurement.quality.name,
        'room_type': measurement.roomType,
        'has_microphone_calibration': measurement.hasMicrophoneCalibration,
        'preference': {
          'name': preference.name,
          'intensity': preference.intensity,
        },
        if (speakerProfile != null) 'speaker': speakerProfile!.toPromptMap(),
        if (recentOutcomes.isNotEmpty)
          'recent_outcomes': [
            for (final outcome in recentOutcomes)
              {
                'preference': outcome.preference.name,
                'used_ai_recommendation': outcome.usedAiRecommendation,
                'result': outcome.result.name,
                if (outcome.soundScoreBefore != null)
                  'sound_score_before': outcome.soundScoreBefore,
                if (outcome.soundScoreAfter != null)
                  'sound_score_after': outcome.soundScoreAfter,
              },
          ],
      };
}

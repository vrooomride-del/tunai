import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';

import 'acoustic_analysis.dart';

/// Calls the Acoustic Intelligence Layer (`aiAnalyze` Cloud Function) to turn
/// a safe, pre-digested measurement summary into consumer-language prose.
///
/// This REPLACES the old `AiTuningService.suggest` role for the AI: it never
/// requests or receives DSP bands. The deterministic [TunePlanner] owns every
/// band; this only interprets what that engine already decided.
///
/// Crucially, it is never on the Tune-creation critical path. A Tune is
/// created, saved, and shown entirely from the deterministic engine BEFORE
/// this is ever called, and this runs afterwards to fill in an optional card.
/// So its latency — the very thing behind the old 12s "Creating your Sound"
/// stall — can no longer block anything the user is waiting on. On any
/// failure (offline, timeout, function not deployed, malformed output) it
/// returns null and the AI card simply does not appear.
class AcousticAnalysisService {
  static FirebaseFunctions get _functions =>
      FirebaseFunctions.instanceFor(region: 'asia-northeast3');

  /// Client-side ceiling. Generous because nothing is waiting on it — the
  /// Tune is already on screen. Still finite so a hung call is eventually
  /// abandoned and the card stays hidden rather than pending forever.
  static const Duration timeout = Duration(seconds: 40);

  static Future<AcousticAnalysis?> analyze(
    AcousticAnalysisDigest digest, {
    bool ko = true,
    @visibleForTesting
    Future<HttpsCallableResult> Function(Map<String, dynamic>)? callOverride,
  }) async {
    try {
      final payload = {
        ...digest.toJson(),
        'locale': ko ? 'ko' : 'en',
      };
      debugPrint('[AI-ANALYZE] request: $payload');
      final HttpsCallableResult result;
      if (callOverride != null) {
        result = await callOverride(payload).timeout(timeout);
      } else {
        result = await _functions
            .httpsCallable('aiAnalyze')
            .call(payload)
            .timeout(timeout);
      }
      final data = result.data;
      if (data is! Map) {
        debugPrint('[AI-ANALYZE] unexpected response type: ${data.runtimeType}');
        return null;
      }
      final analysis = AcousticAnalysis.of(Map<String, dynamic>.from(data));
      debugPrint('[AI-ANALYZE] parsed hasContent=${analysis?.hasContent}');
      return analysis;
    } catch (error) {
      // Never surfaced to the user as an error — the AI layer is purely
      // additive. The offline TuneResultSummary card already covers the
      // must-have "what changed" explanation without any network call.
      debugPrint('[AI-ANALYZE] unavailable (non-fatal): $error');
      return null;
    }
  }
}

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';

import 'acoustic_intent.dart';

/// Turns a user's free-text / selected listening request into a structured,
/// perceptual [AcousticIntent] via the `aiIntent` Cloud Function.
///
/// The AI's ONLY job here is perceptual translation — never a correction and
/// never a DSP value. [AcousticIntent.of] additionally REJECTS any response
/// carrying a forbidden engineering field, so even a misbehaving model cannot
/// push a tuning value through this path. On any failure (offline, timeout,
/// not deployed, forbidden field, empty) it returns null and the caller keeps
/// whatever default intent it already had — the audio flow is never affected.
class AcousticIntentService {
  static FirebaseFunctions get _functions =>
      FirebaseFunctions.instanceFor(region: 'asia-northeast3');

  static const Duration timeout = Duration(seconds: 30);

  static Future<AcousticIntent?> extract(
    String userRequest, {
    bool ko = true,
    @visibleForTesting
    Future<HttpsCallableResult> Function(Map<String, dynamic>)? callOverride,
  }) async {
    final trimmed = userRequest.trim();
    if (trimmed.isEmpty) return null;
    try {
      final payload = {'userRequest': trimmed, 'locale': ko ? 'ko' : 'en'};
      debugPrint('[INTENT] request: $payload');
      final HttpsCallableResult result;
      if (callOverride != null) {
        result = await callOverride(payload).timeout(timeout);
      } else {
        result = await _functions
            .httpsCallable('aiIntent')
            .call(payload)
            .timeout(timeout);
      }
      final data = result.data;
      if (data is! Map) {
        debugPrint('[INTENT] unexpected response type: ${data.runtimeType}');
        return null;
      }
      final intent = AcousticIntent.of(Map<String, dynamic>.from(data));
      debugPrint('[INTENT] parsed hasSignal=${intent?.hasAnySignal}');
      return intent;
    } catch (error) {
      debugPrint('[INTENT] unavailable (non-fatal): $error');
      return null;
    }
  }
}

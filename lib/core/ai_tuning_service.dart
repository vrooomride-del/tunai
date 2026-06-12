import 'dart:convert';
import 'package:google_generative_ai/google_generative_ai.dart';
import '../core/audio_analyzer.dart';
import 'speaker_profile.dart';

class AiTuningResult {
  final List<Map<String, dynamic>> bands;
  final String explanation;
  final bool isError;

  const AiTuningResult({required this.bands, required this.explanation, this.isError = false});

  factory AiTuningResult.fromJson(Map<String, dynamic> json) => AiTuningResult(
    bands: List<Map<String, dynamic>>.from(json['bands'] ?? []),
    explanation: json['explanation'] ?? '',
  );

  factory AiTuningResult.error(String msg) => AiTuningResult(bands: [], explanation: msg, isError: true);
}

class AiTuningService {
  static const _apiKey = 'AQ.Ab8RN6Je2ple9H4TTYY30b5qKIx7N-xyaLV-7zr5wzWOT_7pJQ';

  static final _model = GenerativeModel(
    model: 'gemini-2.5-flash-lite',
    apiKey: _apiKey,
    generationConfig: GenerationConfig(temperature: 0.2, responseMimeType: 'application/json'),
  );

  static Future<AiTuningResult> suggest({
    required List<ResonancePeak> peaks,
    required String userRequest,
    SpeakerProfile? speakerProfile,
  }) async {
    final prompt = _buildPrompt(peaks, userRequest, speakerProfile);
    try {
      final response = await _model.generateContent([Content.text(prompt)]);
      final text = response.text ?? '';
      final json = jsonDecode(text);
      return AiTuningResult.fromJson(json);
    } catch (e) {
      return AiTuningResult.error('AI 응답 오류: $e');
    }
  }

  static String _buildPrompt(List<ResonancePeak> peaks, String userRequest, SpeakerProfile? sp) {
    final peakStr = peaks.asMap().entries.map((e) =>
      '  Peak${e.key+1}: ${e.value.frequency.toStringAsFixed(0)}Hz, ${e.value.gain.toStringAsFixed(1)}dB, Q${e.value.q.toStringAsFixed(2)}'
    ).join('\n');

    String tsSection = '';
    if (sp != null) {
      tsSection = '''
SPEAKER T/S (물리 제약):
  Fs: ${sp.fs}Hz → HPF 권장: ${sp.recommendedHpfFreq.toStringAsFixed(0)}Hz 이하 부스트 금지
  Xmax: ${sp.xmax}mm → 최대 저역 부스트: ${sp.maxBassBoostDb}dB
  감도: ${sp.sensitivity}dB
''';
    }

    return '''
당신은 전문 DSP 음향 엔지니어입니다.
측정된 공진 주파수를 분석하고 PEQ 노치 필터 파라미터를 추천하세요.

$tsSection
측정된 공진 주파수:
$peakStr

사용자 요청: $userRequest

다음 JSON 형식으로만 응답하세요:
{
  "bands": [
    {"frequency": 120, "gainDb": -3.5, "q": 2.0, "enabled": true},
    ...
  ],
  "explanation": "한국어로 2-3문장 설명"
}
''';
  }
}

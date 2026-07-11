import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

// ── Feature flag ──────────────────────────────────────────────────────────────
// Enable via:
//   flutter run \
//     --dart-define=USE_TUNAI_CLOUD_ORCHESTRATOR=true \
//     --dart-define=TUNAI_CLOUD_BASE_URL=https://api.example.com
const bool _kUseCloud = bool.fromEnvironment(
  'USE_TUNAI_CLOUD_ORCHESTRATOR',
  defaultValue: false,
);
const String _kCloudBaseUrl = String.fromEnvironment(
  'TUNAI_CLOUD_BASE_URL',
  defaultValue: 'http://127.0.0.1:8100',
);

bool get tunaiCloudEnabled => _kUseCloud;

// ── Models ────────────────────────────────────────────────────────────────────

class AcousticIntent {
  final String bassBoom;
  final String vocalClarity;
  final String stereoImage;
  final String fatigue;

  const AcousticIntent({
    required this.bassBoom,
    required this.vocalClarity,
    required this.stereoImage,
    required this.fatigue,
  });

  factory AcousticIntent.fromJson(Map<String, dynamic> j) => AcousticIntent(
        bassBoom: j['bass_boom'] as String? ?? 'none',
        vocalClarity: j['vocal_clarity'] as String? ?? 'none',
        stereoImage: j['stereo_image'] as String? ?? 'preserve',
        fatigue: j['fatigue'] as String? ?? 'avoid',
      );
}

class InterpretExplanation {
  final String summary;
  final List<String> whatTunaiFound;

  const InterpretExplanation({
    required this.summary,
    required this.whatTunaiFound,
  });

  factory InterpretExplanation.fromJson(Map<String, dynamic> j) =>
      InterpretExplanation(
        summary: j['summary'] as String? ?? '',
        whatTunaiFound: (j['what_tunai_found'] as List<dynamic>?)
                ?.map((e) => e as String)
                .toList() ??
            [],
      );
}

class InterpretResponse {
  final String requestId;
  final AcousticIntent intent;
  final String strength;
  final String tone;
  final bool requiresRoomScan;
  final bool requiresConfirmation;
  final InterpretExplanation explanation;
  final String source;

  const InterpretResponse({
    required this.requestId,
    required this.intent,
    required this.strength,
    required this.tone,
    required this.requiresRoomScan,
    required this.requiresConfirmation,
    required this.explanation,
    required this.source,
  });

  factory InterpretResponse.fromJson(Map<String, dynamic> j) =>
      InterpretResponse(
        requestId: j['request_id'] as String? ?? '',
        intent: AcousticIntent.fromJson(
            j['intent'] as Map<String, dynamic>? ?? {}),
        strength: j['strength'] as String? ?? 'medium',
        tone: j['tone'] as String? ?? 'natural',
        requiresRoomScan: j['requires_room_scan'] as bool? ?? true,
        requiresConfirmation: j['requires_confirmation'] as bool? ?? true,
        explanation: InterpretExplanation.fromJson(
            j['explanation'] as Map<String, dynamic>? ?? {}),
        source: j['source'] as String? ?? 'unknown',
      );
}

class RoomScanSummary {
  final String? roomType;
  final int? soundScore;
  final List<Map<String, dynamic>> peaks;

  const RoomScanSummary({this.roomType, this.soundScore, this.peaks = const []});

  Map<String, dynamic> toJson() => {
        if (roomType != null) 'room_type': roomType,
        if (soundScore != null) 'sound_score': soundScore,
        if (peaks.isNotEmpty) 'peaks': peaks,
      };
}

class SpeakerSummary {
  final String? model;
  final String? profile;

  const SpeakerSummary({this.model, this.profile});

  Map<String, dynamic> toJson() => {
        if (model != null) 'model': model,
        if (profile != null) 'profile': profile,
      };
}

// ── Service ───────────────────────────────────────────────────────────────────

class TunaiCloudService {
  static final TunaiCloudService _instance = TunaiCloudService._();
  factory TunaiCloudService() => _instance;
  TunaiCloudService._();

  late final Dio _dio = Dio(
    BaseOptions(
      baseUrl: _kCloudBaseUrl,
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 30),
      headers: {'Content-Type': 'application/json'},
    ),
  );

  Future<InterpretResponse> interpretTuneRequest({
    required String userText,
    String locale = 'ko-KR',
    RoomScanSummary? roomScan,
    SpeakerSummary? speaker,
  }) async {
    final body = <String, dynamic>{
      'user_text': userText,
      'locale': locale,
      if (roomScan != null) 'room_scan': roomScan.toJson(),
      if (speaker != null) 'speaker': speaker.toJson(),
    };

    try {
      final res = await _dio.post<Map<String, dynamic>>(
        '/v1/tune/interpret',
        data: body,
      );

      final data = res.data;
      if (data == null) throw const TunaiCloudException('Empty response from TUNAI Cloud');
      return InterpretResponse.fromJson(data);
    } on DioException catch (e) {
      debugPrint('[TunaiCloud] DioException: ${e.type} ${e.response?.statusCode}');
      if (e.type == DioExceptionType.connectionTimeout ||
          e.type == DioExceptionType.receiveTimeout) {
        throw const TunaiCloudException('TUNAI Cloud 연결 시간이 초과되었습니다.');
      }
      final code = e.response?.statusCode;
      if (code != null && code >= 400 && code < 500) {
        throw TunaiCloudException('요청 오류 ($code)');
      }
      throw const TunaiCloudException('TUNAI Cloud를 일시적으로 사용할 수 없습니다.');
    } on FormatException {
      throw const TunaiCloudException('응답 형식 오류');
    }
  }

  Future<bool> isReachable() async {
    try {
      final res = await _dio.get<Map<String, dynamic>>('/health');
      return res.data?['status'] == 'ok';
    } catch (_) {
      return false;
    }
  }
}

class TunaiCloudException implements Exception {
  final String message;
  const TunaiCloudException(this.message);

  @override
  String toString() => 'TunaiCloudException: $message';
}

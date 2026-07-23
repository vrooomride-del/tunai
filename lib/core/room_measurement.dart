import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:shared_preferences/shared_preferences.dart';
import 'package:path_provider/path_provider.dart';

import 'audio_analyzer.dart';

const int roomMeasurementSchemaVersion = 1;
const String roomMeasurementAlgorithmVersion = 'room_fft_ccv_v1';

enum CaptureQualityStatus { valid, degraded, invalid, cancelled }

class CaptureTiming {
  final int requestedSampleRate;
  final int? actualSampleRate;
  final int channelCount;
  final Duration expectedDuration;
  final Duration capturedDuration;
  final int sampleCount;
  final int fileSizeBytes;
  final DateTime recordingStartedAt;
  final DateTime playbackStartedAt;
  final DateTime playbackCompletedAt;
  final DateTime recordingStoppedAt;

  const CaptureTiming({
    required this.requestedSampleRate,
    required this.actualSampleRate,
    required this.channelCount,
    required this.expectedDuration,
    required this.capturedDuration,
    required this.sampleCount,
    required this.fileSizeBytes,
    required this.recordingStartedAt,
    required this.playbackStartedAt,
    required this.playbackCompletedAt,
    required this.recordingStoppedAt,
  });

  double get durationCompleteness => expectedDuration.inMicroseconds == 0
      ? 0
      : capturedDuration.inMicroseconds / expectedDuration.inMicroseconds;

  Map<String, dynamic> toJson() => {
        'requestedSampleRate': requestedSampleRate,
        if (actualSampleRate != null) 'actualSampleRate': actualSampleRate,
        'channelCount': channelCount,
        'expectedDurationMs': expectedDuration.inMilliseconds,
        'capturedDurationUs': capturedDuration.inMicroseconds,
        'sampleCount': sampleCount,
        'fileSizeBytes': fileSizeBytes,
        'recordingStartedAt': recordingStartedAt.toIso8601String(),
        'playbackStartedAt': playbackStartedAt.toIso8601String(),
        'playbackCompletedAt': playbackCompletedAt.toIso8601String(),
        'recordingStoppedAt': recordingStoppedAt.toIso8601String(),
      };

  factory CaptureTiming.fromJson(Map<String, dynamic> json) => CaptureTiming(
        requestedSampleRate: json['requestedSampleRate'] as int,
        actualSampleRate: json['actualSampleRate'] as int?,
        channelCount: json['channelCount'] as int,
        expectedDuration:
            Duration(milliseconds: json['expectedDurationMs'] as int),
        capturedDuration:
            Duration(microseconds: json['capturedDurationUs'] as int),
        sampleCount: json['sampleCount'] as int,
        fileSizeBytes: json['fileSizeBytes'] as int,
        recordingStartedAt:
            DateTime.parse(json['recordingStartedAt'] as String),
        playbackStartedAt: DateTime.parse(json['playbackStartedAt'] as String),
        playbackCompletedAt:
            DateTime.parse(json['playbackCompletedAt'] as String),
        recordingStoppedAt:
            DateTime.parse(json['recordingStoppedAt'] as String),
      );
}

class CaptureLevelMetrics {
  final double rms;
  final double peakAbsolute;
  final double? estimatedNoiseFloorDbfs;
  final double clippingRatio;
  final bool signalPresent;
  final bool severelyClipped;

  const CaptureLevelMetrics({
    required this.rms,
    required this.peakAbsolute,
    required this.estimatedNoiseFloorDbfs,
    required this.clippingRatio,
    required this.signalPresent,
    required this.severelyClipped,
  });

  double get rmsDbfs => rms <= 0 ? -120 : 20 * math.log(rms) / math.ln10;

  Map<String, dynamic> toJson() => {
        'rms': rms,
        'peakAbsolute': peakAbsolute,
        'estimatedNoiseFloorDbfs': estimatedNoiseFloorDbfs,
        'clippingRatio': clippingRatio,
        'signalPresent': signalPresent,
        'severelyClipped': severelyClipped,
      };

  factory CaptureLevelMetrics.fromJson(Map<String, dynamic> json) =>
      CaptureLevelMetrics(
        rms: (json['rms'] as num).toDouble(),
        peakAbsolute: (json['peakAbsolute'] as num).toDouble(),
        estimatedNoiseFloorDbfs:
            (json['estimatedNoiseFloorDbfs'] as num?)?.toDouble(),
        clippingRatio: (json['clippingRatio'] as num).toDouble(),
        signalPresent: json['signalPresent'] as bool,
        severelyClipped: json['severelyClipped'] as bool,
      );
}

class RoomMeasurement {
  final int schemaVersion;
  final String algorithmVersion;
  final String id;
  final String roomType;
  final String microphoneProfileId;
  final bool hasMicrophoneCalibration;
  final DateTime capturedAt;
  final CaptureTiming timing;
  final double usableRangeMinHz;
  final double usableRangeMaxHz;
  final List<FrequencyBin> frequencyBins;
  final List<ResonancePeak> peaks;
  final double consistencyMetric;
  final CaptureLevelMetrics levels;
  final CaptureQualityStatus quality;
  final List<String> warnings;

  const RoomMeasurement({
    this.schemaVersion = roomMeasurementSchemaVersion,
    this.algorithmVersion = roomMeasurementAlgorithmVersion,
    required this.id,
    required this.roomType,
    required this.microphoneProfileId,
    required this.hasMicrophoneCalibration,
    required this.capturedAt,
    required this.timing,
    required this.usableRangeMinHz,
    required this.usableRangeMaxHz,
    required this.frequencyBins,
    required this.peaks,
    required this.consistencyMetric,
    required this.levels,
    required this.quality,
    required this.warnings,
  });

  /// Usable for Tune generation — [CaptureQualityStatus.valid] or
  /// [CaptureQualityStatus.degraded] (lower confidence, but not rejected).
  /// Only [CaptureQualityStatus.invalid]/[CaptureQualityStatus.cancelled]
  /// are unusable.
  bool get isValid =>
      quality == CaptureQualityStatus.valid ||
      quality == CaptureQualityStatus.degraded;

  Map<String, dynamic> toJson() => {
        'schemaVersion': schemaVersion,
        'algorithmVersion': algorithmVersion,
        'id': id,
        'roomType': roomType,
        'microphoneProfileId': microphoneProfileId,
        'hasMicrophoneCalibration': hasMicrophoneCalibration,
        'capturedAt': capturedAt.toIso8601String(),
        'timing': timing.toJson(),
        'usableRangeMinHz': usableRangeMinHz,
        'usableRangeMaxHz': usableRangeMaxHz,
        'frequencyBins':
            frequencyBins.map((bin) => [bin.frequency, bin.magnitude]).toList(),
        'peaks':
            peaks.map((peak) => [peak.frequency, peak.gain, peak.q]).toList(),
        'consistencyMetric': consistencyMetric,
        'levels': levels.toJson(),
        'quality': quality.name,
        'warnings': warnings,
      };

  factory RoomMeasurement.fromJson(Map<String, dynamic> json) {
    if (json['schemaVersion'] != roomMeasurementSchemaVersion) {
      throw const FormatException('Unsupported room measurement schema.');
    }
    return RoomMeasurement(
      schemaVersion: json['schemaVersion'] as int,
      algorithmVersion: json['algorithmVersion'] as String,
      id: json['id'] as String,
      roomType: json['roomType'] as String,
      microphoneProfileId: json['microphoneProfileId'] as String,
      hasMicrophoneCalibration: json['hasMicrophoneCalibration'] as bool,
      capturedAt: DateTime.parse(json['capturedAt'] as String),
      timing: CaptureTiming.fromJson(
          Map<String, dynamic>.from(json['timing'] as Map)),
      usableRangeMinHz: (json['usableRangeMinHz'] as num).toDouble(),
      usableRangeMaxHz: (json['usableRangeMaxHz'] as num).toDouble(),
      frequencyBins: (json['frequencyBins'] as List).map((entry) {
        final values = entry as List;
        return FrequencyBin(
          frequency: (values[0] as num).toDouble(),
          magnitude: (values[1] as num).toDouble(),
        );
      }).toList(),
      peaks: (json['peaks'] as List).map((entry) {
        final values = entry as List;
        return ResonancePeak(
          frequency: (values[0] as num).toDouble(),
          gain: (values[1] as num).toDouble(),
          q: (values[2] as num).toDouble(),
        );
      }).toList(),
      consistencyMetric: (json['consistencyMetric'] as num).toDouble(),
      levels: CaptureLevelMetrics.fromJson(
          Map<String, dynamic>.from(json['levels'] as Map)),
      quality: CaptureQualityStatus.values.byName(json['quality'] as String),
      warnings: (json['warnings'] as List).cast<String>(),
    );
  }
}

class RoomMeasurementValidator {
  static const double durationTolerance = 0.15;
  static const double minimumRms = 0.002;
  static const double severeClippingRatio = 0.01;

  static CaptureLevelMetrics calculateLevels(List<double> samples) {
    if (samples.isEmpty) {
      return const CaptureLevelMetrics(
        rms: 0,
        peakAbsolute: 0,
        estimatedNoiseFloorDbfs: -120,
        clippingRatio: 0,
        signalPresent: false,
        severelyClipped: false,
      );
    }
    var energy = 0.0;
    var peak = 0.0;
    var clipped = 0;
    for (var i = 0; i < samples.length; i++) {
      final absolute = samples[i].abs();
      energy += samples[i] * samples[i];
      if (absolute > peak) peak = absolute;
      if (absolute >= 0.995) clipped++;
    }
    final rms = math.sqrt(energy / samples.length);
    final clippingRatio = clipped / samples.length;
    return CaptureLevelMetrics(
      rms: rms,
      peakAbsolute: peak,
      // There is no signal-free capture window in this method, so a true
      // ambient noise floor cannot be supported yet.
      estimatedNoiseFloorDbfs: null,
      clippingRatio: clippingRatio,
      signalPresent: rms >= minimumRms,
      severelyClipped: clippingRatio > severeClippingRatio,
    );
  }

  /// Graduated reliability judgment for a capture that already passed
  /// [validate] (genuinely broken captures are rejected there, before a
  /// [RoomMeasurement] is even built). Among the ones that pass, this
  /// distinguishes a clean, comfortably-above-threshold capture from a
  /// borderline one — reusing the same [CaptureLevelMetrics] and
  /// [CaptureTiming] already computed for validation, no new measurement.
  ///
  /// [CaptureQualityStatus.degraded] measurements still proceed to Tune
  /// generation (see [TunePlanner._validateMeasurement]) — they are usable,
  /// just lower-confidence, and that confidence is what
  /// `_confidenceFromMeasurement` (room_scan_result.dart) surfaces to the
  /// user.
  static CaptureQualityStatus classifyQuality({
    required CaptureTiming timing,
    required CaptureLevelMetrics levels,
  }) {
    final durationDeviation = (timing.durationCompleteness - 1).abs();
    final borderlineDuration = durationDeviation > durationTolerance * 0.5;
    final quietSignal = levels.rms < minimumRms * 2.5;
    final someClipping = levels.clippingRatio > 0 && !levels.severelyClipped;

    if (borderlineDuration || quietSignal || someClipping) {
      return CaptureQualityStatus.degraded;
    }
    return CaptureQualityStatus.valid;
  }

  static List<String> validate({
    required CaptureTiming timing,
    required List<double> samples,
    required List<FrequencyBin> bins,
    required List<ResonancePeak> peaks,
    required CaptureLevelMetrics levels,
  }) {
    final failures = <String>[];
    if (timing.fileSizeBytes <= 44 || samples.isEmpty) {
      failures.add('The recording file was empty or incomplete.');
    }
    final expectedSamples = timing.requestedSampleRate *
        timing.channelCount *
        timing.expectedDuration.inMicroseconds /
        Duration.microsecondsPerSecond;
    if (samples.length < expectedSamples * (1 - durationTolerance)) {
      failures.add('The recording ended before the measurement completed.');
    }
    if ((timing.durationCompleteness - 1).abs() > durationTolerance) {
      failures.add('The recording duration was outside the accepted range.');
    }
    final playbackDuration =
        timing.playbackCompletedAt.difference(timing.playbackStartedAt);
    final wallCompleteness = playbackDuration.inMicroseconds /
        timing.expectedDuration.inMicroseconds;
    if ((wallCompleteness - 1).abs() > durationTolerance) {
      failures.add('The test signal duration was outside the accepted range.');
    }
    if (!levels.signalPresent || levels.rms < minimumRms) {
      failures.add('The measurement signal was too quiet to analyze.');
    }
    if (levels.severelyClipped) {
      failures.add('The recording level was too high to analyze safely.');
    }
    if (bins.isEmpty ||
        bins.any((bin) => !bin.frequency.isFinite || !bin.magnitude.isFinite)) {
      failures.add('The captured frequency response was invalid.');
    }
    for (var i = 1; i < bins.length; i++) {
      if (bins[i].frequency <= bins[i - 1].frequency) {
        failures.add('The captured frequency response was not ordered.');
        break;
      }
    }
    if (peaks.any((peak) =>
        !peak.frequency.isFinite ||
        !peak.gain.isFinite ||
        !peak.q.isFinite ||
        peak.frequency < 20 ||
        peak.frequency > 500 ||
        peak.gain > 0 ||
        peak.gain < -24 ||
        peak.q < 0.3 ||
        peak.q > 16)) {
      failures.add('The detected room features were invalid.');
    }
    return failures;
  }
}

class RoomMeasurementStore {
  static const _idKey = 'tunai_room_measurement_current_id_v1';
  static const _fileName = 'tunai_room_measurement_v1.json';

  static Future<File> _file() async {
    final directory = await getApplicationSupportDirectory();
    return File('${directory.path}/$_fileName');
  }

  static Future<void> save(RoomMeasurement measurement) async {
    final file = await _file();
    await file.parent.create(recursive: true);
    final temporary = File('${file.path}.tmp');
    await temporary.writeAsString(jsonEncode(measurement.toJson()),
        flush: true);
    if (await file.exists()) await file.delete();
    await temporary.rename(file.path);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_idKey, measurement.id);
  }

  static Future<RoomMeasurement?> load() async {
    final prefs = await SharedPreferences.getInstance();
    final expectedId = prefs.getString(_idKey);
    if (expectedId == null) return null;
    try {
      final file = await _file();
      if (!await file.exists()) throw const FormatException('Missing file.');
      final raw = await file.readAsString();
      final measurement = RoomMeasurement.fromJson(
          Map<String, dynamic>.from(jsonDecode(raw) as Map));
      if (measurement.id != expectedId) {
        throw const FormatException('Measurement reference mismatch.');
      }
      return measurement;
    } catch (_) {
      await prefs.remove(_idKey);
      return null;
    }
  }

  static Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_idKey);
    final file = await _file();
    if (await file.exists()) await file.delete();
  }
}

import 'dart:io';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter_sound/flutter_sound.dart';
import 'package:just_audio/just_audio.dart';
import 'package:permission_handler/permission_handler.dart';
import '../../core/pink_noise_generator.dart';
import '../../core/audio_analyzer.dart';
import '../../core/mic_calibration.dart';
import '../../core/speaker_profile.dart';
import '../dsp/dsp_compiler.dart' show DspCompiler, DspCompilerSafety, RegisterPacket;

enum MeasurementStep {
  idle,
  generatingNoise,
  playing,
  recording,
  analyzing,
  detectingPeaks,
  compiling,
  done,
  error,
}

class MeasurementState {
  final MeasurementStep step;
  final String message;
  final List<FrequencyBin> scmsBins;
  final List<ResonancePeak> peaks;
  final List<RegisterPacket> packets;
  final String? error;

  const MeasurementState({
    this.step = MeasurementStep.idle,
    this.message = '',
    this.scmsBins = const [],
    this.peaks = const [],
    this.packets = const [],
    this.error,
  });

  MeasurementState copyWith({
    MeasurementStep? step,
    String? message,
    List<FrequencyBin>? scmsBins,
    List<ResonancePeak>? peaks,
    List<RegisterPacket>? packets,
    String? error,
  }) => MeasurementState(
    step: step ?? this.step,
    message: message ?? this.message,
    scmsBins: scmsBins ?? this.scmsBins,
    peaks: peaks ?? this.peaks,
    packets: packets ?? this.packets,
    error: error ?? this.error,
  );
}

final measurementProvider =
    StateNotifierProvider<MeasurementController, MeasurementState>(
  (ref) => MeasurementController(),
);

class MeasurementController extends StateNotifier<MeasurementState> {
  MeasurementController() : super(const MeasurementState());

  final _recorder = FlutterSoundRecorder();
  final _player = AudioPlayer();
  bool _recorderInitialized = false;

  Future<void> startMeasurement({SpeakerProfile? speakerProfile}) async {
    try {
      // 0. 마이크 권한 요청
      final micStatus = await Permission.microphone.request();
      if (!micStatus.isGranted) {
        state = state.copyWith(
          step: MeasurementStep.error,
          error: '마이크 권한이 필요합니다. 설정에서 허용해주세요.',
        );
        return;
      }

      // 1. 핑크노이즈 WAV 생성
      _update(MeasurementStep.generatingNoise, '핑크 노이즈 생성 중...');
      final wavBytes = PinkNoiseGenerator().generateWav();
      final wavFile = await _saveWav(wavBytes);

      // 2. 녹음기 초기화
      if (!_recorderInitialized) {
        await _recorder.openRecorder();
        _recorderInitialized = true;
      }

      // 3. 녹음 시작
      _update(MeasurementStep.recording, '공간 측정 중... (10초)');
      final recordPath = await _recordingPath();
      await _recorder.startRecorder(
        toFile: recordPath,
        codec: Codec.pcm16WAV,
        sampleRate: AudioAnalyzer.sampleRate,
        numChannels: 1,
      );

      // 4. Sref 재생
      _update(MeasurementStep.playing, 'Sref 재생 중...');
      await _player.setFilePath(wavFile.path);
      await _player.play();

      // 10초 대기
      await Future.delayed(const Duration(seconds: 10));

      // 5. 녹음 중지
      await _recorder.stopRecorder();
      await _player.stop();

      // 6. FFT 분석
      _update(MeasurementStep.analyzing, 'FFT 분석 중...');
      final pcmBytes = await File(recordPath).readAsBytes();
      final rawPcm = Uint8List.sublistView(pcmBytes, 44);
      final samples = AudioAnalyzer.pcmToFloat(rawPcm);
      debugPrint('[MEASURE] pcmBytes=${pcmBytes.length}, samples=${samples.length}, rms=${_rms(samples).toStringAsFixed(4)}');
      final scapBins = AudioAnalyzer.performFFT(samples);

      // 7. 1단계: 기종별 마이크 보정 (MicCalibrationDb — 고정 테이블, dB 덧셈)
      _update(MeasurementStep.detectingPeaks, '공진 주파수 검출 중...');
      final deviceProfile = await DeviceProfile.detect();
      debugPrint('[MIC] 기기: ${deviceProfile.modelName} (보정: ${deviceProfile.hasCalibration})');
      List<FrequencyBin> micCorrectedBins;
      if (deviceProfile.hasCalibration) {
        micCorrectedBins = scapBins.map((bin) {
          final correction = MicCalibrationDb.interpolateCorrection(
              deviceProfile.calibration!, bin.frequency);
          return FrequencyBin(
              frequency: bin.frequency, magnitude: bin.magnitude + correction);
        }).toList();
        debugPrint('[MIC] 기종 보정 적용: ${deviceProfile.modelName}');
      } else {
        micCorrectedBins = scapBins;
      }

      // 8. 2단계: CCV 적용 (핑크노이즈 이론 형태 vs 실측 잔차 보정, dB 덧셈)
      //    입력: MicCalibrationDb 보정 완료된 스펙트럼
      //    de-mean 적용으로 "동일 신호 자기 비교" 시 보정값 = 0 → 피크 유지
      final ccv = AudioAnalyzer.calculateCCV(micCorrectedBins);
      debugPrint('[CCV] 보정 bin 수: ${ccv.length}');
      final scmsBins = AudioAnalyzer.applyCCV(micCorrectedBins, ccv);

      // 9. 피크 검출
      final peaks = AudioAnalyzer.detectPeaks(scmsBins);

      // 9. DSP 컴파일
      _update(MeasurementStep.compiling, 'DSP 패킷 컴파일 중...');
      // T/S 안전범위 적용
      List<ResonancePeak> safePeaks = peaks;
      if (speakerProfile != null) {
        final safety = DspCompilerSafety.safetyFromTs(
          fs: speakerProfile.fs,
          xmax: speakerProfile.xmax,
          sensitivity: speakerProfile.sensitivity,
        );
        safePeaks = peaks.map((p) => ResonancePeak(
          frequency: p.frequency,
          gain: DspCompilerSafety.clampBassBoost(p.gain, p.frequency, safety.maxBassBoost),
          q: p.q,
        )).toList();
      }
      final packets = DspCompiler.compileAll(safePeaks);

      state = state.copyWith(
        step: MeasurementStep.done,
        message: '측정 완료! ${peaks.length}개 공진 주파수 검출',
        scmsBins: scmsBins,
        peaks: safePeaks,
        packets: packets,
      );
    } catch (e) {
      state = state.copyWith(
        step: MeasurementStep.error,
        error: e.toString(),
      );
    }
  }

  void _update(MeasurementStep step, String message) {
    state = state.copyWith(step: step, message: message);
  }

  Future<File> _saveWav(Uint8List bytes) async {
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/pink_noise.wav');
    await file.writeAsBytes(bytes);
    return file;
  }

  Future<String> _recordingPath() async {
    final dir = await getTemporaryDirectory();
    return '${dir.path}/scap_recording.wav';
  }

  /// 디버그 전용: CCV 재설계 검증 + 파이프라인 더미 데이터 주입
  ///
  /// CCV 전/후 비교 시나리오:
  ///   시나리오A — 인위적 피크 포함 스펙트럼: CCV 적용 후 피크가 유지되는지 확인
  ///   시나리오B — 완전 평탄 스펙트럼: CCV 적용 후 보정값이 0에 가까운지 확인
  ///     (예전 버그: 동일 신호 비교 시 피크 소멸 → de-mean 후 재발 불가)
  void injectDummyData() {
    assert(kDebugMode, 'injectDummyData는 디버그 빌드 전용입니다');

    if (kDebugMode) _verifyCcv();

    const dummyPeaks = [
      ResonancePeak(frequency: 82.0,   gain: -6.5, q: 4.0),
      ResonancePeak(frequency: 248.0,  gain: -4.2, q: 3.5),
      ResonancePeak(frequency: 1180.0, gain: -3.8, q: 5.0),
    ];
    final packets = DspCompiler.compileAll(dummyPeaks);
    debugPrint('[DUMMY] peaks=${dummyPeaks.length}, packets=${packets.length}');
    for (final p in dummyPeaks) { debugPrint('[DUMMY] $p'); }
    state = state.copyWith(
      step: MeasurementStep.done,
      message: '[DEBUG] 더미 데이터 주입 완료 — ${dummyPeaks.length}개 공진',
      peaks: dummyPeaks,
      packets: packets,
    );
  }

  /// CCV 재설계 검증 로그 (디버그 전용)
  void _verifyCcv() {
    // ── 시나리오 A: 이상적 핑크노이즈 스펙트럼 (피크 없음) ──────────────
    // srefDb와 동일한 형태 → de-mean 후 CCV = 0 → applyCCV 후 변화 없어야 함
    final flatBins = <FrequencyBin>[];
    for (var freq = 20.0; freq <= 2000; freq *= 1.05) {
      flatBins.add(FrequencyBin(
          frequency: freq, magnitude: AudioAnalyzer.srefDb(freq)));
    }
    final ccvFlat = AudioAnalyzer.calculateCCV(flatBins);
    final maxCorrFlat = ccvFlat.values.isEmpty
        ? 0.0 : ccvFlat.values.map((v) => v.abs()).reduce(max);
    debugPrint('[CCV-VERIFY] 시나리오A(평탄) 최대 보정값: '
        '${maxCorrFlat.toStringAsFixed(3)}dB → 0에 가까워야 함');

    // ── 시나리오 B: 82Hz에 +8dB 인위적 피크 포함 ────────────────────────
    final peakBins = flatBins.map((b) {
      final bump = (b.frequency > 60 && b.frequency < 100) ? 8.0 : 0.0;
      return FrequencyBin(frequency: b.frequency, magnitude: b.magnitude + bump);
    }).toList();
    final ccvPeak = AudioAnalyzer.calculateCCV(peakBins);
    final applied = AudioAnalyzer.applyCCV(peakBins, ccvPeak);
    final peakBefore = peakBins
        .where((b) => b.frequency > 60 && b.frequency < 100)
        .map((b) => b.magnitude).reduce(max);
    final peakAfter = applied
        .where((b) => b.frequency > 60 && b.frequency < 100)
        .map((b) => b.magnitude).reduce(max);
    debugPrint('[CCV-VERIFY] 시나리오B(피크) 82Hz 전: '
        '${peakBefore.toStringAsFixed(1)}dB → 후: ${peakAfter.toStringAsFixed(1)}dB '
        '(감소여부: ${peakAfter < peakBefore})');
    debugPrint('[CCV-VERIFY] ─ 예전 버그라면 시나리오A 보정값 ≫ 0 이거나 '
        '시나리오B 피크가 소멸됐을 것');
  }

  double _rms(Float64List s) {
    if (s.isEmpty) return 0;
    final sum = s.fold<double>(0, (acc, v) => acc + v * v);
    return sqrt(sum / s.length);
  }

  void reset() => state = const MeasurementState();

  @override
  void dispose() {
    _recorder.closeRecorder();
    _player.dispose();
    super.dispose();
  }
}
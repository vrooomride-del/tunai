import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter_sound/flutter_sound.dart';
import 'package:just_audio/just_audio.dart';
import 'package:permission_handler/permission_handler.dart';
import '../../core/api_service.dart';
import '../../core/mic_calibration.dart';
import '../../core/pink_noise_generator.dart';
import '../../core/audio_analyzer.dart';
import '../dsp/dsp_compiler.dart';

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

  Future<void> startMeasurement() async {
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
      final scapBins = AudioAnalyzer.performFFT(samples);

      // 7. 기기 감지 + CCV → Scms
      final deviceProfile = await DeviceProfile.detect();
      final ccv = AudioAnalyzer.calculateCCV(scapBins, deviceProfile: deviceProfile);
      final scmsBins = AudioAnalyzer.applyCCV(scapBins, ccv);

      // 8. 피크 검출
      _update(MeasurementStep.detectingPeaks, '공진 주파수 검출 중...');
      final peaks = AudioAnalyzer.detectPeaks(scmsBins);

      // 9. DSP 컴파일
      _update(MeasurementStep.compiling, 'DSP 패킷 컴파일 중...');
      final packets = DspCompiler.compileAll(peaks);

      state = state.copyWith(
        step: MeasurementStep.done,
        message: '측정 완료! ${peaks.length}개 공진 주파수 검출',
        scmsBins: scmsBins,
        peaks: peaks,
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

  void reset() => state = const MeasurementState();

  @override
  void dispose() {
    _recorder.closeRecorder();
    _player.dispose();
    super.dispose();
  }
}
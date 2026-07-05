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
import '../ble/ble_controller.dart' show bleProvider;
import '../dsp/dsp_compiler.dart' show DspCompiler, DspCompilerSafety, RegisterPacket;
import '../auth/auth_controller.dart' show authProvider;
import '../../core/device_service.dart';
import '../../core/install_location.dart';
import '../../core/akg/measurement_session.dart';

enum MeasurementStep {
  idle,
  generatingNoise,
  playing,
  recording,
  analyzing,
  detectingPeaks,
  compiling,
  converging,  // DSP 적용 후 재측정 대기 (Closed Loop)
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
  // Closed Loop 상태
  final int iteration;           // 현재 반복 회차 (1-based, 0=미진행)
  final bool hasConverged;       // 수렴 성공 여부
  final double? residualErrorDb; // 마지막 잔류 오차 (dB)

  const MeasurementState({
    this.step = MeasurementStep.idle,
    this.message = '',
    this.scmsBins = const [],
    this.peaks = const [],
    this.packets = const [],
    this.error,
    this.iteration = 0,
    this.hasConverged = false,
    this.residualErrorDb,
  });

  MeasurementState copyWith({
    MeasurementStep? step,
    String? message,
    List<FrequencyBin>? scmsBins,
    List<ResonancePeak>? peaks,
    List<RegisterPacket>? packets,
    String? error,
    int? iteration,
    bool? hasConverged,
    double? residualErrorDb,
  }) => MeasurementState(
    step: step ?? this.step,
    message: message ?? this.message,
    scmsBins: scmsBins ?? this.scmsBins,
    peaks: peaks ?? this.peaks,
    packets: packets ?? this.packets,
    error: error ?? this.error,
    iteration: iteration ?? this.iteration,
    hasConverged: hasConverged ?? this.hasConverged,
    residualErrorDb: residualErrorDb ?? this.residualErrorDb,
  );
}

final measurementProvider =
    StateNotifierProvider<MeasurementController, MeasurementState>(
  (ref) => MeasurementController(ref),
);

class MeasurementController extends StateNotifier<MeasurementState> {
  final Ref _ref;
  MeasurementController(this._ref) : super(const MeasurementState());

  final _recorder = FlutterSoundRecorder();
  final _player = AudioPlayer();
  bool _recorderInitialized = false;
  bool _isCancelled = false;

  static const int _maxIterations = 3;
  static const double _convergenceThresholdDb = 1.5;

  // ── public API ────────────────────────────────────────────────────────────

  /// Open-loop 단일 측정 (기존 동작 유지)
  Future<void> startMeasurement({SpeakerProfile? speakerProfile}) async {
    _isCancelled = false;
    state = const MeasurementState();
    try {
      if (!await _requestMicPermission()) return;
      final wavFile = await _prepareWav();
      final (scmsBins, safePeaks) = await _measureOnce(
          wavFile: wavFile, speakerProfile: speakerProfile, label: '');
      if (_isCancelled) return;
      final packets = DspCompiler.compileAll(safePeaks);
      state = state.copyWith(
        step: MeasurementStep.done,
        message: '측정 완료! ${safePeaks.length}개 공진 주파수 검출',
        scmsBins: scmsBins,
        peaks: safePeaks,
        packets: packets,
        iteration: 1,
      );
      _recordSession(peakCount: safePeaks.length, iterations: 1);
    } catch (e) {
      state = state.copyWith(step: MeasurementStep.error, error: e.toString());
    }
  }

  /// Closed Loop 반복수렴 측정 (특허 청구항1)
  ///
  /// apply → re-measure → converge → retry
  /// 최대 3회, 수렴 기준 1.5dB (JND)
  Future<void> startClosedLoop({SpeakerProfile? speakerProfile}) async {
    _isCancelled = false;
    state = const MeasurementState();
    try {
      if (!await _requestMicPermission()) return;
      final wavFile = await _prepareWav();

      List<ResonancePeak> lastPeaks = [];
      double? lastResidual;

      for (int iter = 0; iter < _maxIterations; iter++) {
        if (_isCancelled) return;

        final iterLabel = '${iter + 1}/$_maxIterations차';
        _update(MeasurementStep.converging, '$iterLabel 보정 — 측정 중...');

        final (scmsBins, safePeaks) = await _measureOnce(
            wavFile: wavFile, speakerProfile: speakerProfile, label: iterLabel);
        if (_isCancelled) return;

        // 누적 gain 경고 (설계 문서 제약 #3)
        final totalGain = safePeaks.fold(0.0, (s, p) => s + p.gain.abs());
        if (totalGain > 24.0) {
          debugPrint('[LOOP] 경고: 누적 gain ${totalGain.toStringAsFixed(1)}dB > 24dB');
        }

        // DSP 컴파일 + BLE 전송
        _update(MeasurementStep.compiling, '$iterLabel 보정 — DSP 적용 중...');
        final packets = DspCompiler.compileAll(safePeaks);
        await _ref.read(bleProvider.notifier).sendPackets(packets);

        // 수렴 확인 (2차 반복부터)
        if (iter > 0) {
          final residual = _calcResidual(safePeaks, lastPeaks);
          lastResidual = residual;
          debugPrint('[LOOP] $iterLabel 잔류오차: ${residual.toStringAsFixed(2)}dB (기준: $_convergenceThresholdDb dB)');

          if (residual < _convergenceThresholdDb) {
            state = state.copyWith(
              step: MeasurementStep.done,
              message: '수렴 완료 ($iterLabel, 잔류 오차 ${residual.toStringAsFixed(1)}dB)',
              scmsBins: scmsBins,
              peaks: safePeaks,
              packets: packets,
              iteration: iter + 1,
              hasConverged: true,
              residualErrorDb: residual,
            );
            _recordSession(
              peakCount: safePeaks.length,
              iterations: iter + 1,
              residualErrorDb: residual,
              converged: true,
            );
            debugPrint('[LOOP] ✅ 수렴 성공');
            return;
          }
        }

        // 미수렴 — DSP 안정화 대기 후 다음 회차 (ADAU1701 Safeload 처리)
        state = state.copyWith(
          scmsBins: scmsBins, peaks: safePeaks, packets: packets,
          iteration: iter + 1, residualErrorDb: lastResidual,
        );
        lastPeaks = safePeaks;

        if (iter < _maxIterations - 1) {
          _update(MeasurementStep.converging,
              '$iterLabel 완료 — DSP 안정화 대기 (200ms)...');
          await Future.delayed(const Duration(milliseconds: 200));
        }
      }

      // 최대 반복 초과 — 마지막 결과 확정 (에러 아님)
      debugPrint('[LOOP] ⚠ 최대 반복 도달 ($_maxIterations회), 마지막 결과 적용');
      state = state.copyWith(
        step: MeasurementStep.done,
        message: '최대 반복 도달 ($_maxIterations회) — 마지막 결과 적용.'
            '${lastResidual != null ? ' 잔류 오차: ${lastResidual.toStringAsFixed(1)}dB' : ''}'
            ' 추가 수동 조정이 필요할 수 있습니다.',
        hasConverged: false,
        residualErrorDb: lastResidual,
      );
      _recordSession(
        peakCount: lastPeaks.length,
        iterations: _maxIterations,
        residualErrorDb: lastResidual,
        converged: false,
      );
    } catch (e) {
      state = state.copyWith(step: MeasurementStep.error, error: e.toString());
    }
  }

  /// 루프 도중 취소
  void cancelLoop() {
    _isCancelled = true;
    state = state.copyWith(
      step: MeasurementStep.idle,
      message: '측정 취소됨',
    );
  }

  // ── 내부 헬퍼 ─────────────────────────────────────────────────────────────

  /// 마이크 권한 요청 — 거부 시 error state 설정하고 false 반환
  Future<bool> _requestMicPermission() async {
    final status = await Permission.microphone.request();
    if (!status.isGranted) {
      state = state.copyWith(
        step: MeasurementStep.error,
        error: '마이크 권한이 필요합니다. 설정에서 허용해주세요.',
      );
      return false;
    }
    return true;
  }

  /// 핑크노이즈 WAV 준비 (한 번 생성 후 루프에서 재사용)
  Future<File> _prepareWav() async {
    _update(MeasurementStep.generatingNoise, '핑크 노이즈 생성 중...');
    final wavBytes = PinkNoiseGenerator().generateWav();
    return _saveWav(wavBytes);
  }

  /// 단일 측정 사이클: 녹음 → FFT → MicCal → CCV → 피크검출 → SafetyProfile
  /// 반환: (scmsBins, safePeaks)
  Future<(List<FrequencyBin>, List<ResonancePeak>)> _measureOnce({
    required File wavFile,
    required SpeakerProfile? speakerProfile,
    required String label,
  }) async {
    final prefix = label.isEmpty ? '' : '$label — ';

    // 녹음기 초기화
    if (!_recorderInitialized) {
      await _recorder.openRecorder();
      _recorderInitialized = true;
    }

    // 녹음 시작
    // ignore: unnecessary_brace_in_string_interps
    _update(MeasurementStep.recording, '${prefix}공간 측정 중... (10초)');
    final recordPath = await _recordingPath();
    await _recorder.startRecorder(
      toFile: recordPath,
      codec: Codec.pcm16WAV,
      sampleRate: AudioAnalyzer.sampleRate,
      numChannels: 1,
    );

    // 핑크노이즈 재생
    _update(MeasurementStep.playing, '${prefix}Sref 재생 중...');
    await _player.setFilePath(wavFile.path);
    await _player.play();
    await Future.delayed(const Duration(seconds: 10));

    await _recorder.stopRecorder();
    await _player.stop();

    // FFT 분석
    _update(MeasurementStep.analyzing, '${prefix}FFT 분석 중...');
    final pcmBytes = await File(recordPath).readAsBytes();
    final rawPcm = Uint8List.sublistView(pcmBytes, 44);
    final samples = AudioAnalyzer.pcmToFloat(rawPcm);
    debugPrint('[MEASURE] pcmBytes=${pcmBytes.length}, samples=${samples.length}, rms=${_rms(samples).toStringAsFixed(4)}');
    final scapBins = AudioAnalyzer.performFFT(samples);

    // MicCalibrationDb (1단계)
    // ignore: unnecessary_brace_in_string_interps
    _update(MeasurementStep.detectingPeaks, '${prefix}공진 주파수 검출 중...');
    final deviceProfile = await DeviceProfile.detect();
    List<FrequencyBin> micCorrectedBins;
    if (deviceProfile.hasCalibration) {
      micCorrectedBins = scapBins.map((bin) {
        final correction = MicCalibrationDb.interpolateCorrection(
            deviceProfile.calibration!, bin.frequency);
        return FrequencyBin(
            frequency: bin.frequency, magnitude: bin.magnitude + correction);
      }).toList();
    } else {
      micCorrectedBins = scapBins;
    }

    // CCV (2단계)
    final ccv = AudioAnalyzer.calculateCCV(micCorrectedBins);
    final scmsBins = AudioAnalyzer.applyCCV(micCorrectedBins, ccv);

    // 피크 검출
    final peaks = AudioAnalyzer.detectPeaks(scmsBins);

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

    return (scmsBins, safePeaks);
  }

  /// 수렴 잔류 오차 계산 — 이전 피크 주파수 ±10% 범위에서 현재 최대 |gain| (dB)
  double _calcResidual(
    List<ResonancePeak> current,
    List<ResonancePeak> previous,
  ) {
    if (previous.isEmpty) return double.infinity;
    double maxResidual = 0.0;
    for (final prev in previous) {
      final near = current.where(
        (p) => (p.frequency - prev.frequency).abs() / prev.frequency < 0.10,
      );
      if (near.isEmpty) continue;
      final localMax = near.map((p) => p.gain.abs()).reduce(max);
      if (localMax > maxResidual) maxResidual = localMax;
    }
    return maxResidual;
  }

  void _update(MeasurementStep step, String message) {
    state = state.copyWith(step: step, message: message);
  }

  /// 측정 1회 완료 시 AKG-ready 이력에 기록(fire-and-forget) — 지금 당장 아무도
  /// 이 데이터를 읽지 않지만, 나중에 AIE/Measurement History가 참조할 수 있도록
  /// 저장만 해둔다. 실패해도 측정 자체 흐름에는 영향 없음.
  void _recordSession({
    required int peakCount,
    int? iterations,
    double? residualErrorDb,
    bool converged = false,
  }) {
    () async {
      try {
        final device = await DeviceService.loadDevice();
        final session = MeasurementSession(
          id: DateTime.now().microsecondsSinceEpoch.toString(),
          timestamp: DateTime.now(),
          deviceId: device?.serial,
          userId: _ref.read(authProvider).userId,
          spaceType: _ref.read(installLocationProvider)?.name,
          peakCount: peakCount,
          iterations: iterations,
          residualErrorDb: residualErrorDb,
          converged: converged,
        );
        await MeasurementSessionStore.append(session);
      } catch (_) {
        // 이력 저장 실패는 무시 — 측정 기능 자체를 막지 않음
      }
    }();
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
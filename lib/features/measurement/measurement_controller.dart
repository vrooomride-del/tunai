import 'dart:io';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter_sound/flutter_sound.dart';
import 'package:just_audio/just_audio.dart' hide AudioSource;
import 'package:permission_handler/permission_handler.dart';
import '../../core/pink_noise_generator.dart';
import '../../core/tunai_playback_audio_session.dart';
import '../../core/audio_analyzer.dart';
import '../../core/mic_calibration.dart';
import '../../core/speaker_profile.dart';
import '../ble/ble_controller.dart' show bleProvider;
import '../dsp/dsp_compiler.dart'
    show DspCompiler, DspCompilerSafety, RegisterPacket;
import '../auth/auth_controller.dart' show authProvider;
import '../../core/device_service.dart';
import '../../core/install_location.dart';
import '../../core/akg/measurement_session.dart';
import '../../core/room_measurement.dart';
import '../../core/mic_calibration_service.dart';
import '../../core/measurement_capture_sequence.dart';

enum MeasurementStep {
  idle,
  generatingNoise,
  playing,
  recording,
  analyzing,
  detectingPeaks,
  compiling,
  converging, // DSP 적용 후 재측정 대기 (Closed Loop)
  done,
  error,
}

class MeasurementState {
  final MeasurementStep step;
  final String message;
  final List<FrequencyBin> scmsBins;
  /// Visualization-only curve: measured spectrum minus the theoretical pink
  /// reference (`AudioAnalyzer.srefDb`) — the same "deviation" spectrum peak
  /// detection already runs on internally. Unlike [scmsBins] (which the CCV
  /// correction deliberately collapses toward the pink reference's own
  /// monotonically-decreasing shape for EQ purposes — see `_measureOnce`),
  /// this one keeps the real room-mode bumps visible, which is what makes it
  /// meaningful to show a user rather than a smooth downward line.
  final List<FrequencyBin> responseBins;
  final List<ResonancePeak> peaks;
  final List<RegisterPacket> packets;
  final String? error;
  final RoomMeasurement? measurement;
  // Closed Loop 상태
  final int iteration; // 현재 반복 회차 (1-based, 0=미진행)
  final bool hasConverged; // 수렴 성공 여부
  final double? residualErrorDb; // 마지막 잔류 오차 (dB)

  const MeasurementState({
    this.step = MeasurementStep.idle,
    this.message = '',
    this.scmsBins = const [],
    this.responseBins = const [],
    this.peaks = const [],
    this.packets = const [],
    this.error,
    this.measurement,
    this.iteration = 0,
    this.hasConverged = false,
    this.residualErrorDb,
  });

  MeasurementState copyWith({
    MeasurementStep? step,
    String? message,
    List<FrequencyBin>? scmsBins,
    List<FrequencyBin>? responseBins,
    List<ResonancePeak>? peaks,
    List<RegisterPacket>? packets,
    String? error,
    RoomMeasurement? measurement,
    int? iteration,
    bool? hasConverged,
    double? residualErrorDb,
  }) =>
      MeasurementState(
        step: step ?? this.step,
        message: message ?? this.message,
        scmsBins: scmsBins ?? this.scmsBins,
        responseBins: responseBins ?? this.responseBins,
        peaks: peaks ?? this.peaks,
        packets: packets ?? this.packets,
        error: error ?? this.error,
        measurement: measurement ?? this.measurement,
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
  bool _captureActive = false;
  bool _disposed = false;

  bool get captureActive => _captureActive;

  static const int _maxIterations = 3;
  static const double _convergenceThresholdDb = 1.5;

  // ── public API ────────────────────────────────────────────────────────────

  /// Open-loop 단일 측정 (기존 동작 유지)
  Future<void> startMeasurement({SpeakerProfile? speakerProfile}) async {
    if (_captureActive) return;
    _captureActive = true;
    _isCancelled = false;
    state = const MeasurementState();
    try {
      if (!await _requestMicPermission()) return;
      final wavFile = await _prepareWav();
      final (scmsBins, responseBins, safePeaks, measurement) =
          await _measureOnce(
              wavFile: wavFile, speakerProfile: speakerProfile, label: '');
      if (_isCancelled) return;
      final packets = DspCompiler.compileAll(safePeaks);
      state = state.copyWith(
        step: MeasurementStep.done,
        message: '측정 완료! ${safePeaks.length}개 공진 주파수 검출',
        scmsBins: scmsBins,
        responseBins: responseBins,
        peaks: safePeaks,
        packets: packets,
        measurement: measurement,
        iteration: 1,
      );
      _recordSession(peakCount: safePeaks.length, iterations: 1);
    } catch (e) {
      if (!_isCancelled && !_disposed) {
        state =
            state.copyWith(step: MeasurementStep.error, error: e.toString());
      }
    } finally {
      await _stopCapture();
      _captureActive = false;
    }
  }

  /// Closed Loop 반복수렴 측정 (특허 청구항1)
  ///
  /// apply → re-measure → converge → retry
  /// 최대 3회, 수렴 기준 1.5dB (JND)
  Future<void> startClosedLoop({SpeakerProfile? speakerProfile}) async {
    if (_captureActive) return;
    _captureActive = true;
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

        final (scmsBins, responseBins, safePeaks, measurement) =
            await _measureOnce(
                wavFile: wavFile,
                speakerProfile: speakerProfile,
                label: iterLabel);
        if (_isCancelled) return;

        // 누적 gain 경고 (설계 문서 제약 #3)
        final totalGain = safePeaks.fold(0.0, (s, p) => s + p.gain.abs());
        if (totalGain > 24.0) {
          debugPrint(
              '[LOOP] 경고: 누적 gain ${totalGain.toStringAsFixed(1)}dB > 24dB');
        }

        // DSP 컴파일 + BLE 전송
        _update(MeasurementStep.compiling, '$iterLabel 보정 — DSP 적용 중...');
        final packets = DspCompiler.compileAll(safePeaks);
        await _ref.read(bleProvider.notifier).sendPackets(packets);

        // 수렴 확인 (2차 반복부터)
        if (iter > 0) {
          final residual = _calcResidual(safePeaks, lastPeaks);
          lastResidual = residual;
          debugPrint(
              '[LOOP] $iterLabel 잔류오차: ${residual.toStringAsFixed(2)}dB (기준: $_convergenceThresholdDb dB)');

          if (residual < _convergenceThresholdDb) {
            state = state.copyWith(
              step: MeasurementStep.done,
              message:
                  '수렴 완료 ($iterLabel, 잔류 오차 ${residual.toStringAsFixed(1)}dB)',
              scmsBins: scmsBins,
              responseBins: responseBins,
              peaks: safePeaks,
              packets: packets,
              measurement: measurement,
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
          scmsBins: scmsBins,
          responseBins: responseBins,
          peaks: safePeaks,
          packets: packets,
          iteration: iter + 1,
          residualErrorDb: lastResidual,
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
      if (!_isCancelled && !_disposed) {
        state =
            state.copyWith(step: MeasurementStep.error, error: e.toString());
      }
    } finally {
      await _stopCapture();
      _captureActive = false;
    }
  }

  /// 루프 도중 취소
  Future<void> cancelLoop() async {
    _isCancelled = true;
    await _stopCapture();
    if (!_disposed) {
      state = state.copyWith(
        step: MeasurementStep.idle,
        message: '측정 취소됨',
      );
    }
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
  /// 반환: (scmsBins, responseBins, safePeaks, measurement)
  Future<
      (
        List<FrequencyBin>,
        List<FrequencyBin>,
        List<ResonancePeak>,
        RoomMeasurement
      )> _measureOnce({
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
    if (_isCancelled) throw const _MeasurementCancelled();

    // 녹음 시작
    // ignore: unnecessary_brace_in_string_interps
    _update(MeasurementStep.recording, '${prefix}공간 측정 중... (10초)');
    final recordPath = await _recordingPath();
    // Same explicit, awaited session activation as the Speaker Audio Check
    // confirmation tone (see tunai_playback_audio_session.dart) — keeping
    // both playback sites on the identical call removes any chance of them
    // silently diverging in configuration again. settleKey ties the settle
    // wait to the CURRENT BLE connection, not just the app's first-ever
    // call, so a reconnect after a drop re-settles too.
    final playSw = Stopwatch()..start();
    debugPrint('[AUDIO_PATH] ROOM_SCAN: playback requested');
    await TunaiPlaybackAudioSession.ensureActive(
      settleKey: _ref.read(bleProvider).connectionGeneration,
      label: 'ROOM_SCAN',
    );
    final signalDuration = await _player.setFilePath(wavFile.path);
    debugPrint('[AUDIO_PATH] ROOM_SCAN: player ready duration=$signalDuration '
        'state=${_player.processingState} (+${playSw.elapsedMilliseconds}ms)');
    final timestamps =
        await const MeasurementCaptureSequence(now: DateTime.now).run(
      startRecorder: () async {
        // Explicit, never the platform default: `AudioSource.defaultSource`
        // leaves it to the OS to pick an input, and on some Android
        // versions/OEM skins a connected Bluetooth device can be chosen as
        // the mic input (attempting an HFP/SCO connection) even though this
        // app only ever wants the PHONE's own microphone for Room Scan —
        // the connected speaker is a playback+DSP-control device, never a
        // capture device. An unwanted SCO negotiation with a peripheral
        // that doesn't support it is a plausible real cause of the BLE
        // connection dropping partway through the 10-second capture.
        await _recorder.startRecorder(
          toFile: recordPath,
          codec: Codec.pcm16WAV,
          sampleRate: AudioAnalyzer.sampleRate,
          numChannels: 1,
          // UNPROCESSED, not `microphone`: `microphone` is the standard
          // capture path and on many Android devices (Samsung included) still
          // runs automatic gain control and noise suppression. Both actively
          // corrupt an acoustic measurement — AGC changes the level partway
          // through the sweep, and noise suppression attenuates exactly the
          // steady broadband content pink noise is made of. UNPROCESSED asks
          // the platform for the raw microphone path with that chain
          // disabled, which is the only capture mode whose frequency
          // response means anything here.
          audioSource: AudioSource.unprocessed,
        );
      },
      recorderIsReady: () => _recorder.isRecording,
      playSignalToCompletion: () async {
        _update(MeasurementStep.playing, '${prefix}Sref 재생 중...');
        debugPrint(
            '[AUDIO_PATH] ROOM_SCAN: play() START (+${playSw.elapsedMilliseconds}ms)');
        await _player.play();
        debugPrint(
            '[AUDIO_PATH] ROOM_SCAN: play() RETURNED (+${playSw.elapsedMilliseconds}ms)');
        if (_isCancelled) throw const _MeasurementCancelled();
      },
      stopRecorder: () async {
        await _recorder.stopRecorder();
      },
      stopPlayback: _player.stop,
    );

    // FFT 분석
    _update(MeasurementStep.analyzing, '${prefix}FFT 분석 중...');
    final pcmBytes = await File(recordPath).readAsBytes();
    if (pcmBytes.length <= 44) {
      throw StateError('The recording file was empty or incomplete.');
    }
    final header = ByteData.sublistView(pcmBytes);
    final actualChannels = header.getUint16(22, Endian.little);
    final actualSampleRate = header.getUint32(24, Endian.little);
    final rawPcm = Uint8List.sublistView(pcmBytes, 44);
    final samples = AudioAnalyzer.pcmToFloat(rawPcm);
    debugPrint(
        '[MEASURE] pcmBytes=${pcmBytes.length}, samples=${samples.length}, rms=${_rms(samples).toStringAsFixed(4)}');
    final capture = AudioAnalyzer.analyzeCapture(samples);
    final scapBins = capture.bins;

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

    // RAW captured level per band — deliberately measured on micCorrectedBins,
    // BEFORE the pink-reference subtraction below, so it answers one question
    // directly: was there any real signal in the band this analysis actually
    // searches (20-300Hz)?
    //
    // Room-mode detection only looks at 20-300Hz. A phone's own speaker cannot
    // physically reproduce that band, so when playback is not routed to the
    // real speaker, those bins carry background noise only — and every peak
    // found in them is noise, which is exactly what real-device runs showed
    // (different "resonances" every capture, Q always pinned at the ceiling).
    // The mid-band level is logged alongside as a reference the phone CAN
    // reproduce: the gap between the two is the direct, quantitative signal of
    // whether bass actually reached the microphone.
    double meanLevel(double lowHz, double highHz) {
      final band = micCorrectedBins
          .where((b) => b.frequency >= lowHz && b.frequency < highHz);
      if (band.isEmpty) return double.nan;
      return band.map((b) => b.magnitude).reduce((a, b) => a + b) / band.length;
    }

    final analysisBandLevel = meanLevel(20, 300);
    final midBandLevel = meanLevel(300, 2000);
    debugPrint('[SIGNAL] raw mean level  20-300Hz(analysis)='
        '${analysisBandLevel.toStringAsFixed(1)}dB  '
        '300-2000Hz(reference)=${midBandLevel.toStringAsFixed(1)}dB  '
        'gap=${(analysisBandLevel - midBandLevel).toStringAsFixed(1)}dB');

    // CCV (2단계) — 디스플레이/EQ용 보정 스펙트럼
    final ccv = AudioAnalyzer.calculateCCV(micCorrectedBins);
    final scmsBins = AudioAnalyzer.applyCCV(micCorrectedBins, ccv);

    // 피크 검출: 룸 모드는 "레퍼런스 제거 편차(measured − pink sref)" 위에서
    // 검출한다. applyCCV 결과(scmsBins)는 measured가 완전 상쇄돼 sref−mean(단조
    // 감소 곡선)이 되므로 로컬 극대값이 없어 항상 0개가 나온다. 편차 스펙트럼은
    // 핑크 기울기를 제거해 실제 룸 공진을 로컬 극대값으로 남긴다.
    final deviationBins = micCorrectedBins
        .map((b) => FrequencyBin(
              frequency: b.frequency,
              magnitude: b.magnitude - AudioAnalyzer.srefDb(b.frequency),
            ))
        .toList();
    // Same deviationBins used both here (peak detection → TunePlan input)
    // and as measure_screen.dart's `responseBins` (what the Room Balance
    // graph actually plots) — logging the full range here lets a real-device
    // "graph shows bumps but bands=0" report be checked against the exact
    // numbers peak detection saw, not a second, possibly-different curve.
    if (deviationBins.isNotEmpty) {
      final in20to300 =
          deviationBins.where((b) => b.frequency >= 20 && b.frequency <= 300);
      final above300 = deviationBins.where((b) => b.frequency > 300);
      String rangeStr(Iterable<FrequencyBin> bins) {
        if (bins.isEmpty) return 'n/a';
        final mags = bins.map((b) => b.magnitude);
        return '${mags.reduce((a, b) => a < b ? a : b).toStringAsFixed(1)}..'
            '${mags.reduce((a, b) => a > b ? a : b).toStringAsFixed(1)}dB';
      }

      debugPrint('[TUNE_TRACE] deviationBins total=${deviationBins.length} '
          '20-300Hz(searched)=${in20to300.length} range=${rangeStr(in20to300)} '
          '300-500Hz(NOT searched by detectPeaks)=${above300.length} '
          'range=${rangeStr(above300)}');
    }
    final peaks = AudioAnalyzer.detectPeaks(deviationBins);

    // T/S 안전범위 적용
    List<ResonancePeak> safePeaks = peaks;
    if (speakerProfile != null) {
      final safety = DspCompilerSafety.safetyFromTs(
        fs: speakerProfile.fs,
        xmax: speakerProfile.xmax,
        sensitivity: speakerProfile.sensitivity,
      );
      safePeaks = peaks
          .map((p) => ResonancePeak(
                frequency: p.frequency,
                gain: DspCompilerSafety.clampBassBoost(
                    p.gain, p.frequency, safety.maxBassBoost),
                q: p.q,
              ))
          .toList();
    }

    final captureDuration = Duration(
      microseconds: (samples.length /
              actualSampleRate /
              actualChannels *
              Duration.microsecondsPerSecond)
          .round(),
    );
    final timing = CaptureTiming(
      requestedSampleRate: AudioAnalyzer.sampleRate,
      actualSampleRate: actualSampleRate,
      channelCount: actualChannels,
      expectedDuration:
          const Duration(seconds: PinkNoiseGenerator.durationSeconds),
      capturedDuration: captureDuration,
      sampleCount: samples.length,
      fileSizeBytes: pcmBytes.length,
      recordingStartedAt: timestamps.recordingStartedAt,
      playbackStartedAt: timestamps.playbackStartedAt,
      playbackCompletedAt: timestamps.playbackCompletedAt,
      recordingStoppedAt: timestamps.recordingStoppedAt,
    );
    final levels = RoomMeasurementValidator.calculateLevels(samples);
    final failures = RoomMeasurementValidator.validate(
      timing: timing,
      samples: samples,
      bins: scmsBins,
      peaks: safePeaks,
      levels: levels,
    );
    if (failures.isNotEmpty) {
      throw StateError(failures.first);
    }
    final location = _ref.read(installLocationProvider);
    final mic = _ref.read(micCalibrationProfileProvider).valueOrNull;
    final quality = RoomMeasurementValidator.classifyQuality(
      timing: timing,
      levels: levels,
    );
    final measurement = RoomMeasurement(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      roomType: location?.labelEn ?? 'Living Room',
      microphoneProfileId: mic?.profileName ?? 'Generic Phone Mic',
      hasMicrophoneCalibration: mic != null && !mic.isGeneric,
      capturedAt: timestamps.recordingStoppedAt,
      timing: timing,
      usableRangeMinHz: 20,
      usableRangeMaxHz: 500,
      // The DEVIATION spectrum, not `scmsBins`.
      //
      // `applyCCV` adds `srefDb(f) - measured(f) - mean` to `measured(f)`,
      // which cancels the measurement exactly: inside the 20Hz-2kHz CCV band
      // `scmsBins` reduces to `srefDb(f) - mean`, a fixed function of
      // frequency carrying no information about this room at all. Persisting
      // that as the measurement's spectrum meant every downstream consumer of
      // `frequencyBins` — Sound Score, the AI context, and now broadband tone
      // analysis — was reading a constant curve. `deviationBins`
      // (`measured - srefDb`) is the same data with the pink-noise slope
      // removed and the measurement itself retained.
      frequencyBins: List.unmodifiable(deviationBins),
      peaks: List.unmodifiable(safePeaks),
      // A REAL repeatability measure (see CaptureAnalysis.agreement), not the
      // old "fraction of finite bins" — which was 1.0 by construction for
      // every capture that reached this point, and so reported perfect
      // consistency even for a capture that was entirely noise.
      consistencyMetric: capture.agreement,
      levels: levels,
      quality: quality,
      warnings: [
        if (mic == null || mic.isGeneric)
          'No device-specific microphone calibration was available.',
        if (quality == CaptureQualityStatus.degraded)
          'The measurement signal was quieter or less stable than ideal.',
      ],
    );
    return (scmsBins, deviationBins, safePeaks, measurement);
  }

  Future<void> _stopCapture() async {
    try {
      await _player.stop();
    } catch (_) {}
    try {
      if (_recorderInitialized && !_recorder.isStopped) {
        await _recorder.stopRecorder();
      }
    } catch (_) {}
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
      ResonancePeak(frequency: 82.0, gain: -6.5, q: 4.0),
      ResonancePeak(frequency: 248.0, gain: -4.2, q: 3.5),
      ResonancePeak(frequency: 1180.0, gain: -3.8, q: 5.0),
    ];
    final packets = DspCompiler.compileAll(dummyPeaks);
    debugPrint('[DUMMY] peaks=${dummyPeaks.length}, packets=${packets.length}');
    for (final p in dummyPeaks) {
      debugPrint('[DUMMY] $p');
    }
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
      flatBins.add(
          FrequencyBin(frequency: freq, magnitude: AudioAnalyzer.srefDb(freq)));
    }
    final ccvFlat = AudioAnalyzer.calculateCCV(flatBins);
    final maxCorrFlat = ccvFlat.values.isEmpty
        ? 0.0
        : ccvFlat.values.map((v) => v.abs()).reduce(max);
    debugPrint('[CCV-VERIFY] 시나리오A(평탄) 최대 보정값: '
        '${maxCorrFlat.toStringAsFixed(3)}dB → 0에 가까워야 함');

    // ── 시나리오 B: 82Hz에 +8dB 인위적 피크 포함 ────────────────────────
    final peakBins = flatBins.map((b) {
      final bump = (b.frequency > 60 && b.frequency < 100) ? 8.0 : 0.0;
      return FrequencyBin(
          frequency: b.frequency, magnitude: b.magnitude + bump);
    }).toList();
    final ccvPeak = AudioAnalyzer.calculateCCV(peakBins);
    final applied = AudioAnalyzer.applyCCV(peakBins, ccvPeak);
    final peakBefore = peakBins
        .where((b) => b.frequency > 60 && b.frequency < 100)
        .map((b) => b.magnitude)
        .reduce(max);
    final peakAfter = applied
        .where((b) => b.frequency > 60 && b.frequency < 100)
        .map((b) => b.magnitude)
        .reduce(max);
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

  void markPersistenceFailure() {
    state = state.copyWith(
      step: MeasurementStep.error,
      error: 'The measurement could not be saved. Please try again.',
    );
  }

  @override
  void dispose() {
    _disposed = true;
    _isCancelled = true;
    _stopCapture();
    _recorder.closeRecorder();
    _player.dispose();
    super.dispose();
  }
}

class _MeasurementCancelled implements Exception {
  const _MeasurementCancelled();
}

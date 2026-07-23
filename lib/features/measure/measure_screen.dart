import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';
import '../measurement/measurement_controller.dart';
import '../ble/ble_controller.dart';
import '../../core/confirmation_tone_generator.dart';
import '../../core/speaker_profile.dart';
import '../../core/tunai_playback_audio_session.dart';
import '../../core/install_location.dart';
import '../../core/spectrum_snapshot.dart';
import '../../core/speaker_verification_session.dart';
import '../../core/mic_calibration_service.dart';
import '../../core/room_scan_result.dart';
import '../../core/room_measurement.dart';
import '../../shared/widgets.dart';
import '../../shared/acoustic_timeline.dart';

/// ROOM 탭 — 공간 측정 UX.
/// 측정 완료 시 [onMeasured]로 TUNE 탭 자동 전환을 요청한다.
class MeasureScreen extends ConsumerStatefulWidget {
  final VoidCallback onMeasured;
  const MeasureScreen({super.key, required this.onMeasured});
  @override
  ConsumerState<MeasureScreen> createState() => _MeasureScreenState();
}

class _MeasureScreenState extends ConsumerState<MeasureScreen>
    with WidgetsBindingObserver {
  // true = show Mic Check card before scan starts
  bool _showMicCheck = false;
  bool _committingResult = false;
  late final MeasurementController _measurementController;

  bool get _isKo => Localizations.localeOf(context).languageCode == 'ko';

  @override
  void initState() {
    super.initState();
    _measurementController = ref.read(measurementProvider.notifier);
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) {
      _measurementController.cancelLoop();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _measurementController.cancelLoop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final mState = ref.watch(measurementProvider);
    final bState = ref.watch(bleProvider);
    final ko = _isKo;
    final step = mState.step;
    final isRunning = step != MeasurementStep.idle &&
        step != MeasurementStep.done &&
        step != MeasurementStep.error;
    final isConnected = bState.connection == BleConnectionState.connected;

    ref.listen<MeasurementState>(measurementProvider, (prev, next) async {
      if (next.step == MeasurementStep.done &&
          prev?.step != MeasurementStep.done) {
        final measurement = next.measurement;
        debugPrint('[FLOW] MEASURE_DONE isValid=${measurement?.isValid} '
            'committing=$_committingResult peaks=${next.peaks.length}');
        if (_committingResult || measurement == null || !measurement.isValid) {
          debugPrint('[FLOW] MEASURE_DONE_SKIP (no save / no navigate)');
          return;
        }
        _committingResult = true;
        if (next.responseBins.isNotEmpty) {
          // responseBins (measured − pink reference) keeps real room-mode
          // bumps visible; scmsBins is a CCV-corrected curve that collapses
          // toward the pink reference's own smooth, monotonically-decreasing
          // shape by design (see measurement_controller.dart) — plotting
          // that one was why the Consumer graph looked like a flat downward
          // line instead of a real frequency response.
          ref
              .read(spectrumSnapshotProvider.notifier)
              .setBefore(next.responseBins);
        }
        try {
          await RoomMeasurementStore.save(measurement);
          await ref
              .read(roomScanResultProvider.notifier)
              .saveResult(RoomScanResult.fromMeasurement(measurement));
          debugPrint('[FLOW] ROOMSCAN_SAVED → onMeasured (go TUNE)');
          if (mounted) widget.onMeasured();
        } catch (error) {
          debugPrint('[FLOW] ROOMSCAN_SAVE_FAILED $error');
          if (mounted) {
            ref.read(measurementProvider.notifier).markPersistenceFailure();
          }
        } finally {
          _committingResult = false;
        }
      }
    });

    ref.listen<BleState>(bleProvider, (previous, next) {
      final wasConnected = previous?.connection == BleConnectionState.connected;
      if (wasConnected &&
          next.connection != BleConnectionState.connected &&
          isRunning) {
        ref.read(measurementProvider.notifier).cancelLoop();
      }
    });

    if (isRunning) {
      return _MeasuringView(
        mState: mState,
        ko: ko,
        onCancel: () => ref.read(measurementProvider.notifier).cancelLoop(),
      );
    }

    if (step == MeasurementStep.done) {
      return _ResultView(
        mState: mState,
        ko: ko,
        onOptimize: widget.onMeasured,
        onReMeasure: () {
          ref.read(measurementProvider.notifier).reset();
          setState(() => _showMicCheck = false);
        },
      );
    }

    // ── Ready state — show Mic Check or main ready screen ──────────────────
    if (_showMicCheck) {
      return _MicCheckView(
        ko: ko,
        onContinue: () {
          setState(() => _showMicCheck = false);
          ref.read(measurementProvider.notifier).startMeasurement(
                speakerProfile: ref.read(speakerProfileProvider),
              );
        },
        onBack: () => setState(() => _showMicCheck = false),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(32, 0, 32, 32),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 48),
                    Text(
                      ko
                          ? '당신의 공간이 소리를 결정합니다.'
                          : 'Your space shapes your sound.',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 26,
                        fontWeight: FontWeight.w300,
                        height: 1.35,
                        letterSpacing: -0.2,
                      ),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      ko
                          ? '벽, 가구, 스피커 배치에 따라 소리는 달라집니다.\n\nTUNAI가 공간을 분석하고 당신만의 사운드를 만들어드립니다.'
                          : 'Walls, furniture, and placement affect how your speaker sounds.\n\nTUNAI analyzes your listening space and creates a personalized sound profile.',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.45),
                        fontSize: 14,
                        height: 1.65,
                      ),
                    ),
                    const SizedBox(height: 40),
                    const _LocationPicker(),
                    const SizedBox(height: 20),
                    // Mic status card
                    _MicStatusCard(ko: ko),
                    if (!isConnected) ...[
                      const SizedBox(height: 16),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 12),
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.white12),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Row(children: [
                          const Icon(Icons.bluetooth_disabled,
                              color: Colors.white24, size: 16),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              ko
                                  ? '스피커를 먼저 연결해주세요 (CONNECT 탭)'
                                  : 'Connect your speaker first (CONNECT tab)',
                              style: const TextStyle(
                                  color: Colors.white38, fontSize: 12),
                            ),
                          ),
                        ]),
                      ),
                    ],
                    if (step == MeasurementStep.error &&
                        mState.error != null) ...[
                      const SizedBox(height: 16),
                      Text(mState.error!,
                          style: const TextStyle(
                              color: Color(0xFFFF5252),
                              fontSize: 13,
                              height: 1.5)),
                    ],
                    const SizedBox(height: 40),
                  ],
                ),
              ),
            ),
            // ── 하단 버튼 ────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(32, 0, 32, 40),
              child: _BigButton(
                label: ko ? '공간 분석 시작' : 'Start Space Analysis',
                onTap: isConnected
                    ? () => setState(() => _showMicCheck = true)
                    : null,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Mic Check step ─────────────────────────────────────────────────────────────
class _MicCheckView extends ConsumerStatefulWidget {
  final bool ko;
  final VoidCallback onContinue;
  final VoidCallback onBack;
  const _MicCheckView(
      {required this.ko, required this.onContinue, required this.onBack});

  @override
  ConsumerState<_MicCheckView> createState() => _MicCheckViewState();
}

class _MicCheckViewState extends ConsumerState<_MicCheckView> {
  // Speaker Check is a mandatory gate (not just a suggestion): the OS gives
  // the app no way to confirm which device is actually playing audio (see
  // tunai_playback_audio_session.dart), so the user's own "예/아니요"
  // confirmation is the only real signal available. null = not yet
  // confirmed, true = confirmed heard from the speaker, false = confirmed
  // NOT heard from the speaker — both null and false block measurement.
  bool? _speakerConfirmed;

  @override
  Widget build(BuildContext context) {
    final ko = widget.ko;
    final micAsync = ref.watch(micCalibrationProfileProvider);
    final mic = micAsync.valueOrNull;
    final canStart = _speakerConfirmed == true;

    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(32, 48, 32, 32),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      ko ? '휴대폰 마이크 확인' : 'Phone Mic Check',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 26,
                        fontWeight: FontWeight.w300,
                        height: 1.35,
                      ),
                    ),
                    const SizedBox(height: 32),
                    // Mic status
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.white12),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            PhoneMicCheckStatusLine(
                              status: mic != null
                                  ? mic.statusLabel(ko: ko)
                                  : (ko
                                      ? '마이크 확인 중...'
                                      : 'Checking microphone...'),
                            ),
                            if (mic != null) ...[
                              const SizedBox(height: 8),
                              Text(
                                mic.confidenceLabel(ko: ko),
                                style: const TextStyle(
                                    color: Colors.white38, fontSize: 11),
                              ),
                            ],
                          ]),
                    ),
                    const SizedBox(height: 28),
                    // Instructions
                    _Instruction(
                      icon: Icons.place_outlined,
                      text: ko
                          ? '휴대폰을 청취 위치에 놓아주세요.'
                          : 'Place your phone at the listening position.',
                    ),
                    _Instruction(
                      icon: Icons.back_hand_outlined,
                      text: ko
                          ? '마이크를 손으로 가리지 마세요.'
                          : 'Keep the microphone uncovered.',
                    ),
                    _Instruction(
                      icon: Icons.volume_off_outlined,
                      text: ko
                          ? '가능한 조용한 상태에서 진행해 주세요.'
                          : 'Make your space as quiet as possible.',
                    ),
                    const SizedBox(height: 32),
                    // Noise level placeholder
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.white12),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Row(children: [
                        const Icon(Icons.sensors,
                            color: Colors.white24, size: 14),
                        const SizedBox(width: 10),
                        Text(
                          ko
                              ? '주변 소음 감지 — 준비 중'
                              : 'Ambient noise detection — coming soon',
                          style: const TextStyle(
                              color: Colors.white24, fontSize: 11),
                        ),
                      ]),
                    ),
                    const SizedBox(height: 28),
                    // Speaker Audio Check — mandatory gate, not just a
                    // suggestion: confirms the phone's audio output is
                    // actually reaching the connected speaker BEFORE the
                    // real (10s pink-noise) measurement signal plays. Uses a
                    // short, distinct musical chime — never the measurement
                    // noise itself — so the two are never confused with
                    // each other. "공간 분석 시작" below stays disabled until
                    // the user explicitly confirms "예".
                    _SpeakerAudioCheckSection(
                      onHeardChanged: (heard) =>
                          setState(() => _speakerConfirmed = heard),
                    ),
                    if (!canStart) ...[
                      const SizedBox(height: 10),
                      Text(
                        ko
                            ? '먼저 연결된 스피커에서 확인음이 들리는지 확인해주세요.'
                            : 'First confirm you can hear the tone from your '
                                'connected speaker.',
                        style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.4),
                            fontSize: 11.5,
                            height: 1.5),
                      ),
                    ],
                    const SizedBox(height: 28),
                    // Mic Strategy
                    ConsumerMicStrategySection(ko: ko),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(32, 0, 32, 16),
              child: _BigButton(
                label: ko ? '공간 분석 시작' : 'Start Space Analysis',
                onTap: canStart ? widget.onContinue : null,
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(32, 0, 32, 32),
              child: GestureDetector(
                onTap: widget.onBack,
                child: Center(
                  child: Text(
                    ko ? '뒤로' : 'Back',
                    style: const TextStyle(color: Colors.white30, fontSize: 13),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Speaker Audio Check ──────────────────────────────────────────────────
//
// Root-cause context: the app's BLE connection to the speaker is a
// low-bandwidth DSP *control* link only — it cannot carry real-time audio.
// The actual Room Scan measurement signal (and this confirmation tone) play
// through the phone's normal audio output, which only reaches the speaker
// if the PHONE's system Bluetooth audio route is separately selected to it
// (independent of the app's BLE connection). The app cannot force that
// routing — only the user, in their phone's Bluetooth settings, can. This
// section makes that requirement visible and lets the user verify it BEFORE
// starting a 10-second measurement that would otherwise silently capture
// nothing meaningful.
class _SpeakerAudioCheckSection extends ConsumerStatefulWidget {
  final ValueChanged<bool?> onHeardChanged;
  const _SpeakerAudioCheckSection({required this.onHeardChanged});

  @override
  ConsumerState<_SpeakerAudioCheckSection> createState() =>
      _SpeakerAudioCheckSectionState();
}

class _SpeakerAudioCheckSectionState
    extends ConsumerState<_SpeakerAudioCheckSection> {
  final _player = AudioPlayer();
  bool _playing = false;
  bool _hasPlayedOnce = false;
  bool? _heard;
  String? _error;

  /// Whether the phone currently has a Bluetooth AUDIO link to a speaker.
  /// null = not checked yet, or could not be determined — in which case
  /// nothing is claimed either way and no notice is shown.
  bool? _hasBluetoothAudio;

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  void _setHeard(bool? value) {
    setState(() => _heard = value);
    widget.onHeardChanged(value);
    final session = ref.read(speakerVerificationSessionProvider.notifier);
    if (value == true) {
      // Ties the confirmation to the exact connection it was heard on (see
      // speaker_verification_session.dart) so this stays valid across
      // ROOM → TUNE → APPLY as long as the same speaker stays connected,
      // and auto-invalidates on disconnect/reconnect/speaker swap.
      final ble = ref.read(bleProvider);
      final speakerId = ble.selectedDeviceIdentifier;
      if (ble.connection == BleConnectionState.connected &&
          speakerId != null &&
          speakerId.isNotEmpty) {
        session.confirmHeard(
          speakerId: speakerId,
          connectionGeneration: ble.connectionGeneration,
        );
      }
    } else if (value == false) {
      session.clear();
    }
  }

  Future<void> _playTone() async {
    if (_playing) return;
    _setHeard(null);
    setState(() {
      _playing = true;
      _hasPlayedOnce = true;
      _error = null;
    });
    try {
      // Must be awaited HERE, immediately before play() — this is the fix
      // for the real-device bug where this first confirmation tone played
      // from the phone instead of the speaker while the later Room Scan
      // measurement signal worked correctly: the app-startup session config
      // was fire-and-forget and could still be in flight the first time a
      // user reaches this screen. See tunai_playback_audio_session.dart.
      // settleKey ties the settle wait to the CURRENT BLE connection so a
      // reconnect after a drop gets a fresh settle wait too, not just the
      // very first tone of the app's lifetime.
      final sw = Stopwatch()..start();
      debugPrint('[AUDIO_PATH] SPEAKER_CHECK: playback requested');
      await TunaiPlaybackAudioSession.ensureActive(
        settleKey: ref.read(bleProvider).connectionGeneration,
        label: 'SPEAKER_CHECK',
      );
      final bytes = ConfirmationToneGenerator().generateWav();
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/tunai_confirmation_tone.wav');
      await file.writeAsBytes(bytes, flush: true);
      final duration = await _player.setFilePath(file.path);
      // Player READY: a non-null duration here means the source was really
      // loaded and decoded, so a silent run can be told apart from a run
      // where playback never got a source at all.
      debugPrint('[AUDIO_PATH] SPEAKER_CHECK: player ready duration=$duration '
          'state=${_player.processingState} (+${sw.elapsedMilliseconds}ms)');
      debugPrint(
          '[AUDIO_PATH] SPEAKER_CHECK: play() START (+${sw.elapsedMilliseconds}ms)');
      await _player.play();
      debugPrint(
          '[AUDIO_PATH] SPEAKER_CHECK: play() RETURNED (+${sw.elapsedMilliseconds}ms)');
      // Asked AFTER playback, so the answer reflects the route the tone
      // actually used. If there is no Bluetooth audio link, the tone came out
      // of the phone and cannot have come from the speaker — the user is told
      // exactly that rather than being left to wonder why they heard nothing
      // from the speaker (or, worse, confirming "I heard it" about the phone).
      final hasBluetoothAudio =
          await TunaiPlaybackAudioSession.hasBluetoothAudioOutput();
      if (mounted) setState(() => _hasBluetoothAudio = hasBluetoothAudio);
    } catch (error) {
      if (mounted) {
        setState(() => _error = Localizations.localeOf(context)
                    .languageCode ==
                'ko'
            ? '확인음을 재생하지 못했습니다.'
            : "Couldn't play the confirmation tone.");
      }
    } finally {
      if (mounted) setState(() => _playing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ko = Localizations.localeOf(context).languageCode == 'ko';
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.white12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            ko ? '스피커 오디오 확인' : 'Speaker Audio Check',
            style: const TextStyle(
                color: Colors.white, fontSize: 14, fontWeight: FontWeight.w400),
          ),
          const SizedBox(height: 6),
          Text(
            ko
                ? '아래 버튼을 누르면 짧은 확인음이 재생됩니다.\n이 소리는 공간 측정에 쓰이는 소리와는 다릅니다.'
                : "Tap below to play a short confirmation chime.\nIt's different from the sound used for the actual measurement.",
            style: TextStyle(
                color: Colors.white.withValues(alpha: 0.45),
                fontSize: 12,
                height: 1.5),
          ),
          const SizedBox(height: 14),
          GestureDetector(
            onTap: _playTone,
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 11),
              width: double.infinity,
              decoration: BoxDecoration(
                border: Border.all(color: Colors.white24),
                borderRadius: BorderRadius.circular(6),
              ),
              alignment: Alignment.center,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                      _playing
                          ? Icons.graphic_eq
                          : Icons.play_circle_outline,
                      color: Colors.white70,
                      size: 16),
                  const SizedBox(width: 8),
                  Text(
                    _playing
                        ? (ko ? '재생 중...' : 'Playing...')
                        : (_heard != null
                            ? (ko ? '다시 재생' : 'Play again')
                            : (ko ? '확인음 재생' : 'Play confirmation tone')),
                    style: const TextStyle(color: Colors.white70, fontSize: 13),
                  ),
                ],
              ),
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 10),
            Text(_error!,
                style: const TextStyle(color: Color(0xFFFF5252), fontSize: 11)),
          ],
          // Only when we positively KNOW there is no Bluetooth audio link.
          // `null` (unknown / not yet checked) shows nothing — never claim
          // something about the user's setup that wasn't actually determined.
          if (_hasBluetoothAudio == false && !_playing) ...[
            const SizedBox(height: 12),
            Container(
              key: const Key('consumer_no_bluetooth_audio_notice'),
              padding: const EdgeInsets.all(11),
              decoration: BoxDecoration(
                color: const Color(0xFFFFB300).withValues(alpha: 0.08),
                border:
                    Border.all(color: const Color(0xFFFFB300).withValues(alpha: 0.35)),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                // Deliberately explicit that this makes the RESULT invalid,
                // not merely that playback is on the wrong device. A phone's
                // own speaker cannot physically reproduce the low frequencies
                // this analysis looks at, so a measurement taken this way
                // captures only background noise in the band that matters —
                // any "correction" derived from it would be meaningless.
                // Measurement is still allowed to run (the user can simulate
                // the flow), but never silently presented as trustworthy.
                ko
                    ? '지금은 소리가 휴대폰에서 재생되고 있습니다.\n'
                        '이 상태로는 정확한 공간 측정과 실제 소리 개선이 불가능합니다.\n'
                        '휴대폰 블루투스 설정에서 스피커를 소리 재생 기기로 연결한 뒤 '
                        '다시 재생해주세요.'
                    : 'Sound is currently playing from your phone.\n'
                        'Accurate space measurement and real sound improvement '
                        'are not possible this way.\n'
                        'Connect the speaker for audio in your phone’s Bluetooth '
                        'settings, then play again.',
                style: const TextStyle(
                    color: Color(0xFFFFB300), fontSize: 11, height: 1.5),
              ),
            ),
          ],
          if (_hasPlayedOnce && !_playing && _error == null) ...[
            const SizedBox(height: 14),
            Text(
              ko ? '스피커에서 소리가 들리셨나요?' : 'Did you hear it from your speaker?',
              style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.6), fontSize: 12),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: _YesNoButton(
                    label: ko ? '예' : 'Yes',
                    selected: _heard == true,
                    onTap: () => _setHeard(true),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _YesNoButton(
                    label: ko ? '아니요' : 'No',
                    selected: _heard == false,
                    onTap: () => _setHeard(false),
                  ),
                ),
              ],
            ),
          ],
          if (_heard == false) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.03),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                ko
                    ? '휴대폰 설정 > 블루투스에서 스피커가 오디오 출력 기기로 선택되어 있는지 확인해 주세요.\n앱 연결과는 별개로, 소리를 재생하려면 휴대폰이 스피커를 오디오 기기로도 선택하고 있어야 합니다.'
                    : "Please check your phone's Bluetooth settings and make "
                        'sure the speaker is selected as the audio output '
                        "device. Separately from the app's connection, your "
                        'phone also needs to select the speaker for audio '
                        'playback.',
                style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.5),
                    fontSize: 11,
                    height: 1.6),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _YesNoButton extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _YesNoButton(
      {required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 9),
          decoration: BoxDecoration(
            color: selected
                ? Colors.white.withValues(alpha: 0.1)
                : Colors.transparent,
            border: Border.all(
                color: selected ? Colors.white54 : Colors.white24),
            borderRadius: BorderRadius.circular(6),
          ),
          alignment: Alignment.center,
          child: Text(label,
              style: TextStyle(
                  color: selected ? Colors.white : Colors.white54,
                  fontSize: 12)),
        ),
      );
}

class _Instruction extends StatelessWidget {
  final IconData icon;
  final String text;
  const _Instruction({required this.icon, required this.text});
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icon, color: Colors.white38, size: 16),
          const SizedBox(width: 12),
          Expanded(
            child: Text(text,
                style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.6),
                    fontSize: 13,
                    height: 1.5)),
          ),
        ]),
      );
}

// ── Mic status compact card for the Ready screen ───────────────────────────────
class _MicStatusCard extends ConsumerWidget {
  final bool ko;
  const _MicStatusCard({required this.ko});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final micAsync = ref.watch(micCalibrationProfileProvider);
    return micAsync.when(
      data: (mic) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        decoration: BoxDecoration(
          border: Border.all(color: Colors.white12),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(children: [
          const Icon(Icons.mic, color: Colors.white38, size: 14),
          const SizedBox(width: 10),
          Expanded(
              child: Text(
            mic.statusLabel(ko: ko),
            style: const TextStyle(color: Colors.white54, fontSize: 11),
          )),
        ]),
      ),
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
    );
  }
}

// ── 측정 진행 화면 ─────────────────────────────────────────────────────────────
class _MeasuringView extends StatefulWidget {
  final MeasurementState mState;
  final bool ko;
  final VoidCallback onCancel;
  const _MeasuringView({
    required this.mState,
    required this.ko,
    required this.onCancel,
  });
  @override
  State<_MeasuringView> createState() => _MeasuringViewState();
}

class _MeasuringViewState extends State<_MeasuringView> {
  int _phaseIdx = 0;
  late final List<(String, String)> _phases;

  @override
  void initState() {
    super.initState();
    _phases = const [
      ('Checking bass response', '저역 반응을 확인하고 있습니다'),
      ('Listening to your space', '공간의 소리를 듣고 있습니다'),
      ('Balancing stereo image', '좌우 음장을 조정하고 있습니다'),
      ('Creating Your Sound', '나만의 사운드를 만들고 있습니다'),
    ];
    _tick();
  }

  Future<void> _tick() async {
    for (var i = 0; i < _phases.length; i++) {
      await Future.delayed(const Duration(seconds: 2));
      if (!mounted) return;
      setState(() => _phaseIdx = i);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ko = widget.ko;
    final progress = ((_phaseIdx + 1) / _phases.length).clamp(0.0, 1.0);
    final phaseText = ko ? _phases[_phaseIdx].$2 : _phases[_phaseIdx].$1;

    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(32, 60, 32, 40),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                ko ? '공간을 분석하고 있습니다...' : 'TUNAI is analyzing your space...',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 26,
                  fontWeight: FontWeight.w300,
                  height: 1.35,
                ),
              ),
              const Spacer(flex: 2),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 400),
                child: Text(
                  phaseText,
                  key: ValueKey(_phaseIdx),
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.55),
                    fontSize: 14,
                    height: 1.5,
                  ),
                ),
              ),
              const SizedBox(height: 20),
              LinearProgressIndicator(
                value: progress,
                backgroundColor: Colors.white12,
                color: Colors.white38,
                minHeight: 1.5,
              ),
              if (widget.mState.message.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(
                  widget.mState.message,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.25),
                    fontSize: 11,
                  ),
                ),
              ],
              const Spacer(flex: 3),
              GestureDetector(
                onTap: widget.onCancel,
                child: Center(
                  child: Text(
                    ko ? '취소' : 'Cancel',
                    style: const TextStyle(color: Colors.white38, fontSize: 13),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── 측정 결과 화면 ─────────────────────────────────────────────────────────────
class _ResultView extends ConsumerWidget {
  final MeasurementState mState;
  final bool ko;
  final VoidCallback onOptimize;
  final VoidCallback onReMeasure;
  const _ResultView({
    required this.mState,
    required this.ko,
    required this.onOptimize,
    required this.onReMeasure,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final result = ref.watch(roomScanResultProvider);
    final cards = result?.cards ?? const <RoomScanResultCard>[];

    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(32, 60, 32, 32),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      ko
                          ? 'TUNAI가 공간이 소리에\n미치는 영향을 찾았습니다.'
                          : 'TUNAI found how your\nspace shapes the sound.',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 26,
                        fontWeight: FontWeight.w300,
                        height: 1.35,
                        letterSpacing: -0.2,
                      ),
                    ),
                    const SizedBox(height: 36),
                    // Listening Environment Summary — consumer-safe, no Hz/dB/chart
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 12),
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.white12),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Row(children: [
                        const Icon(Icons.check_circle_outline,
                            color: Color(0xFF69F0AE), size: 14),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            ko
                                ? 'TUNAI가 공간의 소리 특성을 정리했습니다.'
                                : 'TUNAI has completed your space sound summary.',
                            style: const TextStyle(
                                color: Colors.white54,
                                fontSize: 12,
                                height: 1.4),
                          ),
                        ),
                      ]),
                    ),
                    const SizedBox(height: 24),
                    AcousticTimeline(
                      currentStep: AcousticTimelineStep.acousticTune,
                      ko: ko,
                    ),
                    const SizedBox(height: 24),
                    Text(
                      ko ? '청취 환경 요약' : 'Listening Environment Summary',
                      style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.35),
                          fontSize: 11,
                          letterSpacing: 1.5),
                    ),
                    const SizedBox(height: 10),
                    ...cards.map((card) => _ResultCard(card: card, ko: ko)),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(32, 0, 32, 16),
              child: _BigButton(
                label: ko ? '나만의 사운드 만들기' : 'Create Your Sound',
                onTap: onOptimize,
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(32, 0, 32, 32),
              child: GestureDetector(
                onTap: onReMeasure,
                child: Center(
                  child: Text(
                    ko ? '다시 공간 분석' : 'Scan again',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.3),
                      fontSize: 13,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ResultCard extends StatelessWidget {
  final RoomScanResultCard card;
  final bool ko;
  const _ResultCard({required this.card, required this.ko});
  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          border: Border.all(color: Colors.white12),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(card.label(ko: ko),
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w400)),
          const SizedBox(height: 4),
          Text(card.description(ko: ko),
              style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.45),
                  fontSize: 12,
                  height: 1.4)),
        ]),
      );
}

// ── Mic Strategy Section ──────────────────────────────────────────────────────

@visibleForTesting
class PhoneMicCheckStatusLine extends StatelessWidget {
  final String status;
  const PhoneMicCheckStatusLine({super.key, required this.status});

  @override
  Widget build(BuildContext context) => Row(children: [
        const Icon(Icons.mic, color: Colors.white54, size: 16),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            status,
            softWrap: true,
            style: const TextStyle(color: Colors.white, fontSize: 13),
          ),
        ),
      ]);
}

class ConsumerMicStrategySection extends StatelessWidget {
  final bool ko;
  const ConsumerMicStrategySection({super.key, required this.ko});

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(
        ko ? '측정 장치' : 'Measurement Device',
        style: TextStyle(
            color: Colors.white.withValues(alpha: 0.35),
            fontSize: 11,
            letterSpacing: 1.5),
      ),
      const SizedBox(height: 10),
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          border: Border.all(color: Colors.white24),
          borderRadius: BorderRadius.circular(6),
          color: Colors.white.withValues(alpha: 0.03),
        ),
        child: Row(children: [
          const Icon(Icons.smartphone, color: Colors.white70, size: 16),
          const SizedBox(width: 12),
          Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Text(
                  ko ? '스마트폰 마이크' : 'Smartphone Microphone',
                  style: const TextStyle(color: Colors.white, fontSize: 13),
                ),
                const SizedBox(height: 2),
                Text(
                  ko
                      ? '현재는 스마트폰 마이크로 진행합니다.'
                      : 'Currently using your smartphone microphone.',
                  style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.45),
                      fontSize: 11,
                      height: 1.4),
                ),
              ])),
        ]),
      ),
    ]);
  }
}

// ── 공용 위젯 ──────────────────────────────────────────────────────────────────
class _BigButton extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;
  const _BigButton({required this.label, this.onTap});
  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 18),
        decoration: BoxDecoration(
          color: enabled ? Colors.white : Colors.white12,
          borderRadius: BorderRadius.circular(4),
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: TextStyle(
            color: enabled ? Colors.black : Colors.white24,
            fontSize: 14,
            fontWeight: FontWeight.w500,
            letterSpacing: 1.5,
          ),
        ),
      ),
    );
  }
}

class _LocationPicker extends ConsumerWidget {
  const _LocationPicker();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selected = ref.watch(installLocationProvider);
    final ko = Localizations.localeOf(context).languageCode == 'ko';
    return SectionCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(
          ko ? '스피커가 놓인 공간을 알려주세요 (선택사항)' : 'Where is your speaker? (Optional)',
          style: const TextStyle(
              color: Colors.white, fontSize: 14, letterSpacing: 0.5),
        ),
        const SizedBox(height: 4),
        // Never required to proceed with Room Scan — measurement accuracy
        // never depends on this. When set, it's used only as extra context
        // for the AI recommendation step (see AiTuneOrchestrator's
        // `location` field) and in the profile's display name; skipping it
        // simply falls back to a generic "Living Room" label.
        Text(
          ko
              ? '건너뛰어도 측정에는 영향이 없습니다. AI가 사운드를 만들 때 참고합니다.'
              : "Skipping this won't affect the measurement. It's just extra "
                  'context for the AI recommendation.',
          style: const TextStyle(color: Colors.white38, fontSize: 11),
        ),
        const SizedBox(height: 12),
        ...InstallLocation.values.map((loc) {
          final isSelected = selected == loc;
          return GestureDetector(
            onTap: () => ref.read(installLocationProvider.notifier).state = loc,
            child: Container(
              margin: const EdgeInsets.only(bottom: 6),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                border: Border.all(
                    color: isSelected ? Colors.white : Colors.white12),
                borderRadius: BorderRadius.circular(6),
                color: isSelected
                    ? Colors.white.withValues(alpha: 0.05)
                    : Colors.transparent,
              ),
              child: Row(children: [
                Icon(
                    isSelected
                        ? Icons.radio_button_checked
                        : Icons.radio_button_off,
                    color: isSelected ? Colors.white : Colors.white24,
                    size: 16),
                const SizedBox(width: 10),
                Text(ko ? loc.label : loc.labelEn,
                    style: TextStyle(
                        color: isSelected ? Colors.white : Colors.white60,
                        fontSize: 13)),
              ]),
            ),
          );
        }),
        if (selected == InstallLocation.custom) ...[
          const SizedBox(height: 6),
          TextField(
            style: const TextStyle(color: Colors.white, fontSize: 13),
            decoration: const InputDecoration(
              hintText: '예: 침실 책장 위, 캠핑카 등',
              hintStyle: TextStyle(color: Colors.white24),
              enabledBorder: OutlineInputBorder(
                  borderSide: BorderSide(color: Colors.white24)),
              focusedBorder: OutlineInputBorder(
                  borderSide: BorderSide(color: Colors.white54)),
              contentPadding:
                  EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            ),
            onChanged: (v) =>
                ref.read(installLocationCustomTextProvider.notifier).state = v,
          ),
        ],
      ]),
    );
  }
}

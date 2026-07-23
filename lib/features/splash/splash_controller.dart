import 'dart:async';

import 'package:flutter/animation.dart';
import 'package:flutter/foundation.dart' show debugPrint;

import 'audio_identity_service.dart';
import 'brand_identity.dart';

/// Drives one Splash playthrough: the motion timeline, the synchronized logo
/// sound, and the fail-safe that guarantees [onFinished] fires exactly once.
///
/// Owned by the Splash widget's State (which supplies the [TickerProvider]);
/// this class holds no widget/BuildContext references so it stays testable
/// and reusable if the Splash UI is ever restyled.
class SplashController {
  SplashController({
    required TickerProvider vsync,
    required this.brand,
    this.minDuration = const Duration(milliseconds: 1400),
    this.playLogoSound = true,
    AudioIdentityService? audioIdentityService,
  })  : animationController =
            AnimationController(vsync: vsync, duration: minDuration),
        _audio = audioIdentityService ?? AudioIdentityService();

  final BrandIdentity brand;
  final Duration minDuration;
  final bool playLogoSound;
  final AnimationController animationController;
  final AudioIdentityService _audio;

  Timer? _failSafeTimer;
  bool _finished = false;
  VoidCallback? _onFinished;
  final Stopwatch _stopwatch = Stopwatch();

  // Splash only actually hands off once BOTH the visual motion AND the logo
  // sound have finished naturally — never cutting the sound off mid-play
  // just because the animation timer elapsed first. `_audioDone` starts
  // true when there is no sound to wait for (disabled, or once it fails/is
  // unavailable) so a missing asset never blocks the handoff. The fail-safe
  // timer is the absolute ceiling regardless of what either signal does.
  bool _animationDone = false;
  bool _audioDone = false;

  Animation<double> get animation => animationController;

  /// Starts the motion + logo sound and arms the fail-safe. [onFinished]
  /// fires exactly once, once both the animation and the logo sound have
  /// completed (or immediately for whichever of the two is disabled/fails),
  /// or when the fail-safe timeout (2x [minDuration]) is reached — whichever
  /// comes first.
  void start(VoidCallback onFinished) {
    _onFinished = onFinished;
    _stopwatch.start();
    animationController.addStatusListener(_onStatusChanged);
    animationController.forward();
    debugPrint('[ SPLASH ] Animation start (duration=$minDuration)');

    if (playLogoSound) {
      unawaited(_audio.playSafely(brand.logoSoundAssetPath).then((_) {
        debugPrint('[ SPLASH ] audio finished/unavailable '
            '(+${_stopwatch.elapsedMilliseconds}ms)');
        _audioDone = true;
        _maybeFinish();
      }));
    } else {
      _audioDone = true;
    }

    _failSafeTimer = Timer(minDuration * 2, () {
      if (_finished) return;
      debugPrint('[ SPLASH ] Complete (fail-safe timeout after '
          '${_stopwatch.elapsedMilliseconds}ms real time — animation/audio '
          'never both completed)');
      _finish();
    });
  }

  void _onStatusChanged(AnimationStatus status) {
    debugPrint('[ SPLASH ] animation status=$status '
        '(+${_stopwatch.elapsedMilliseconds}ms)');
    if (status == AnimationStatus.completed) {
      _animationDone = true;
      _maybeFinish();
    }
  }

  void _maybeFinish() {
    if (!_animationDone || !_audioDone) return;
    debugPrint('[ SPLASH ] Complete (animation + audio both done after '
        '${_stopwatch.elapsedMilliseconds}ms real time)');
    _finish();
  }

  void _finish() {
    if (_finished) return;
    _finished = true;
    _failSafeTimer?.cancel();
    _onFinished?.call();
  }

  void dispose() {
    debugPrint('[ SPLASH ] controller dispose '
        '(+${_stopwatch.elapsedMilliseconds}ms, finished=$_finished)');
    _failSafeTimer?.cancel();
    animationController.removeStatusListener(_onStatusChanged);
    animationController.dispose();
    unawaited(_audio.dispose());
  }
}

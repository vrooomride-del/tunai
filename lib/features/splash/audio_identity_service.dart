import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';

/// Plays the brand's short logo sound on the host phone at app launch.
///
/// This is a brand identity cue, not a hardware check: it never proves BLE
/// delivery, DSP output, amplifier output, or speaker output. Do not treat a
/// successful play as speaker/output verification — that requires a separate,
/// explicitly-implemented confirmation path once a real protocol exists.
///
/// If the configured asset is ever missing or fails to decode, [playSafely]
/// fails silently by design rather than blocking Splash or crashing the app.
class AudioIdentityService {
  AudioIdentityService({AudioPlayer Function()? playerFactory})
      : _playerFactory = playerFactory ?? AudioPlayer.new;

  final AudioPlayer Function() _playerFactory;
  AudioPlayer? _player;

  /// Plays [assetPath] once at [volume] (0.0–1.0) and **completes only once
  /// playback actually finishes** (or immediately on any failure — missing
  /// asset, decode error, unavailable platform channel in tests). Callers
  /// use this to know the sound has genuinely played out in full, e.g. so
  /// Splash never hands off while the logo sound is still mid-play. Never
  /// throws; duplicate calls are ignored while a player is already active.
  Future<void> playSafely(String assetPath, {double volume = 0.6}) async {
    if (_player != null) return; // already playing this instance
    final stopwatch = Stopwatch()..start();
    try {
      final player = _playerFactory();
      _player = player;
      debugPrint(
          '[ SPLASH ] audio: player created (+${stopwatch.elapsedMilliseconds}ms)');
      // Deliberately does NOT await TunaiPlaybackAudioSession.ensureActive()
      // here, unlike the Speaker Check / Room Scan playback sites.
      //
      // A previous batch added that await and it REGRESSED this sound to
      // silence on real hardware. Splash is on a hard deadline: the logo
      // sound is 2.0s and SplashController's fail-safe fires at
      // 2 x minDuration (2800ms), after which Splash hands off, the widget
      // is disposed, and `dispose()` below kills the player mid-tone. At
      // cold start `ensureActive()` is the app's first platform-channel
      // work (AudioSession.instance + configure + setActive, plus a focus
      // request) and can easily eat the ~800ms of slack that decoding the
      // asset needs, pushing playback past that deadline — the tone then
      // never audibly starts at all. Splash audio also has nothing to gain
      // from it: it is a phone-side brand cue at launch, before any BLE
      // connection exists, and Android plays media fine without an explicit
      // session configuration.
      await player.setAsset(assetPath);
      debugPrint(
          '[ SPLASH ] audio: setAsset done (+${stopwatch.elapsedMilliseconds}ms)');
      await player.setVolume(volume.clamp(0.0, 1.0));
      // just_audio's play() does not complete until playback finishes (or is
      // paused/stopped) — that is exactly the signal callers need here.
      await player.play();
      debugPrint(
          '[ SPLASH ] audio: playback completed (+${stopwatch.elapsedMilliseconds}ms)');
    } catch (error, stackTrace) {
      debugPrint(
          '[ SPLASH ] audio: unavailable (+${stopwatch.elapsedMilliseconds}ms) '
          '$error\n$stackTrace');
    }
  }

  Future<void> dispose() async {
    final player = _player;
    _player = null;
    await player?.dispose();
  }
}

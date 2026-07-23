import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart';

/// Single source of truth for configuring+activating the app's shared
/// [AudioSession] before ANY playback that needs to reach the connected
/// speaker (the Speaker Audio Check confirmation tone in measure_screen.dart
/// AND the real Room Scan pink-noise signal in measurement_controller.dart).
///
/// Root-cause context: `main.dart` used to configure the session once,
/// fire-and-forget, at app startup. On a real device that meant whichever
/// playback happened to run first (often the Speaker Audio Check tone,
/// reached quickly after first launch) could race ahead of that
/// configuration actually completing/activating, silently falling back to
/// the phone's default output — while by the time the user reached the
/// actual Room Scan measurement (after reading instructions, tapping
/// through screens), the session was already configured, so it worked. Both
/// playback sites now call [ensureActive] and AWAIT it immediately before
/// their own `AudioPlayer.play()`, removing that race entirely — and using
/// this one function means the two can never silently diverge in
/// configuration again.
class TunaiPlaybackAudioSession {
  static Future<AudioSession>? _configured;
  static Object? _lastSettledKey;
  static bool _everSettled = false;

  /// Configures the session (once, cached) for Bluetooth-capable playback,
  /// then activates it. Safe to call before every single playback — cheap
  /// once configured, and `setActive` is idempotent.
  ///
  /// [settleKey] identifies "which BLE connection is this for" (pass
  /// `BleState.connectionGeneration`) — the settle wait below re-arms
  /// whenever this changes, not just once per app process. A fresh BLE
  /// connection re-negotiates the phone's separate Bluetooth AUDIO route
  /// from scratch (A2DP profile handshake), so the settle gap this is
  /// working around recurs on every new connection, including a
  /// reconnect to the very same speaker after a drop — not just the very
  /// first connection of the app's lifetime.
  ///
  /// [awaitRouteSettle] must be false for playback that is never routed to
  /// a Bluetooth speaker in the first place (e.g. the Splash logo sound,
  /// which intentionally plays on the phone itself — see
  /// audio_identity_service.dart) — there is no A2DP handshake to wait out
  /// for on-device-only audio, so waiting would just be a pointless delay.
  ///
  /// [label] names the calling playback site ('SPEAKER_CHECK', 'ROOM_SCAN')
  /// so a real logcat capture can tell the two apart — every line below is
  /// tagged `[AUDIO_PATH]` with it, and timings are cumulative from entry,
  /// so the actual first-playback path can be read off a device instead of
  /// guessed at.
  static Future<void> ensureActive({
    Object? settleKey,
    bool awaitRouteSettle = true,
    String label = 'UNKNOWN',
  }) async {
    final sw = Stopwatch()..start();
    debugPrint('[AUDIO_PATH] $label: session request '
        '(settleKey=$settleKey configured=${_configured != null})');
    final attempt = _configured ??= _configure();
    try {
      final session = await attempt;
      debugPrint(
          '[AUDIO_PATH] $label: configured (+${sw.elapsedMilliseconds}ms)');
      await session.setActive(true);
      debugPrint('[AUDIO_PATH] $label: session ACTIVE '
          '(+${sw.elapsedMilliseconds}ms)');
      // `setActive(true)` completing only means the *session* was activated,
      // not that the *physical* output route has switched to the connected
      // Bluetooth speaker yet. On the FIRST playback after a new BLE
      // connection the classic-Bluetooth A2DP audio link is often still being
      // negotiated, so a blind fixed delay (previously 1200ms) can elapse
      // while the route is still on the phone — the "first white noise / tone
      // plays from the phone, later ones from the speaker" symptom.
      //
      // Instead, wait for the ACTUAL signal: poll `getDevices()` (confirmed to
      // report `bluetoothA2dp` correctly on real hardware) until the A2DP
      // output appears, then proceed. Returns fast when the route is already
      // up, waits out a genuinely-still-switching route, and — if the device
      // never exposes A2DP (audio not connected) or the query is unavailable —
      // falls back to the old bounded fixed delay so playback is never blocked
      // indefinitely.
      final needsSettle =
          awaitRouteSettle && (!_everSettled || settleKey != _lastSettledKey);
      if (needsSettle) {
        _everSettled = true;
        _lastSettledKey = settleKey;
        await _awaitAudioRouteSettled(session, label, sw);
      }
      debugPrint('[AUDIO_PATH] $label: ensureActive DONE '
          '(+${sw.elapsedMilliseconds}ms settled=$needsSettle)');
    } catch (error) {
      // Do not leave a failed attempt cached: on a cold start, this is the
      // very first platform-channel call the app makes, and can race the
      // Flutter engine's own channel setup. If that single early call fails
      // and its future stays cached in `_configured`, every later call
      // (including the real Room Scan measurement) would silently reuse the
      // same failure forever with no retry. Clearing it here means the next
      // `ensureActive()` call — e.g. the user retrying the confirmation tone,
      // or Room Scan starting moments later — gets a fresh attempt instead.
      if (identical(_configured, attempt)) {
        _configured = null;
      }
      debugPrint('[AUDIO_PATH] $label: ensureActive FAILED '
          '(+${sw.elapsedMilliseconds}ms, non-fatal): $error');
    }
  }

  /// Whether the OS currently reports a connected Bluetooth AUDIO output.
  ///
  /// A speaker's BLE/GATT control link (flutter_blue_plus, the `connected`
  /// state everywhere else in this app) and its classic Bluetooth AUDIO link
  /// are two completely separate connections. The app establishes the former
  /// itself; the latter is owned by Android's Bluetooth settings and the app
  /// cannot initiate it. When it is absent, media playback comes out of the
  /// PHONE no matter what this class does — so callers use this to tell the
  /// user the truth instead of letting them believe they are hearing the
  /// speaker.
  ///
  /// Returns null when it cannot be determined (query failed), so callers can
  /// distinguish "known absent" from "unknown" and never assert something
  /// false. Never throws.
  static Future<bool?> hasBluetoothAudioOutput() async {
    try {
      final session = await (_configured ??= _configure());
      final devices = await session.getDevices();
      return devices.any(
          (d) => d.isOutput && d.type == AudioDeviceType.bluetoothA2dp);
    } catch (error) {
      debugPrint('[AUDIO_PATH] hasBluetoothAudioOutput() failed: $error');
      return null;
    }
  }

  /// The most time the first playback may wait for the A2DP route to appear.
  /// Long enough to cover a real first-connection handshake, bounded so a
  /// device that never exposes A2DP can't block playback forever.
  static const _maxRouteWait = Duration(milliseconds: 4000);
  static const _pollInterval = Duration(milliseconds: 150);

  /// Waits until the OS reports a connected `bluetoothA2dp` OUTPUT (the real
  /// "audio is now going to the speaker" signal), polling [_pollInterval] up to
  /// [_maxRouteWait]. Returns immediately once it appears. Falls back to a
  /// bounded fixed delay if `getDevices()` is unavailable, and simply proceeds
  /// after the ceiling if A2DP never appears (audio not connected — the
  /// on-screen "playing from phone" notice already covers that case). Never
  /// throws.
  static Future<void> _awaitAudioRouteSettled(
      AudioSession session, String label, Stopwatch sw) async {
    final deadline = DateTime.now().add(_maxRouteWait);
    while (DateTime.now().isBefore(deadline)) {
      List<AudioDevice> outputs;
      try {
        outputs =
            (await session.getDevices()).where((d) => d.isOutput).toList();
      } catch (error) {
        debugPrint('[AUDIO_PATH] $label: getDevices() failed, fixed-delay '
            'fallback: $error');
        await Future.delayed(const Duration(milliseconds: 1200));
        return;
      }
      final hasA2dp =
          outputs.any((d) => d.type == AudioDeviceType.bluetoothA2dp);
      if (hasA2dp) {
        debugPrint('[AUDIO_PATH] $label: A2DP route ready '
            '(+${sw.elapsedMilliseconds}ms) '
            '[${outputs.map((d) => d.type.name).join(', ')}]');
        return;
      }
      await Future.delayed(_pollInterval);
    }
    debugPrint('[AUDIO_PATH] $label: A2DP route NOT ready within '
        '${_maxRouteWait.inMilliseconds}ms — proceeding (likely playing from '
        'phone; audio not connected)');
  }

  static Future<AudioSession> _configure() async {
    final session = await AudioSession.instance;
    await session.configure(AudioSessionConfiguration(
      avAudioSessionCategory: AVAudioSessionCategory.playback,
      avAudioSessionCategoryOptions:
          AVAudioSessionCategoryOptions.allowBluetooth |
              AVAudioSessionCategoryOptions.allowBluetoothA2dp,
      avAudioSessionMode: AVAudioSessionMode.defaultMode,
      androidAudioAttributes: const AndroidAudioAttributes(
        contentType: AndroidAudioContentType.music,
        usage: AndroidAudioUsage.media,
      ),
      androidAudioFocusGainType: AndroidAudioFocusGainType.gain,
    ));
    debugPrint('[ AUDIO ] session configured for Bluetooth A2DP playback');
    return session;
  }
}

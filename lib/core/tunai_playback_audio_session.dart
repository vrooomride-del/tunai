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
      // `setActive(true)` completing only means the *session* was
      // activated, not that the *physical* output route has switched to the
      // connected Bluetooth speaker yet. A previous version of this method
      // BLOCKED here polling `getDevices()` for a `bluetoothA2dp` entry —
      // reverted, because on real hardware it made playback (and everything
      // waiting on it) stall far longer than the old fixed delay, without
      // confirmed evidence it was even detecting the right thing on this
      // speaker. Back to a bounded fixed delay: known, bounded, non-hanging.
      // `_logDevicesForDiagnostics` runs alongside it, unawaited — it never
      // gates playback, it only prints what the OS reports so the next real
      // logcat capture has actual evidence instead of another guess.
      final needsSettle =
          awaitRouteSettle && (!_everSettled || settleKey != _lastSettledKey);
      if (needsSettle) {
        _everSettled = true;
        _lastSettledKey = settleKey;
        _logDevicesForDiagnostics(session, label);
        await Future.delayed(const Duration(milliseconds: 1200));
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

  /// Fire-and-forget diagnostic only — never awaited by [ensureActive], so
  /// it can never add latency or block playback. Purely so the next real
  /// logcat capture shows what the OS actually reports at the moment of
  /// this settle wait, instead of relying on another unverified guess.
  static void _logDevicesForDiagnostics(AudioSession session, String label) {
    session.getDevices().then((devices) {
      final outputs = devices.where((d) => d.isOutput).toList();
      final hasA2dp =
          outputs.any((d) => d.type == AudioDeviceType.bluetoothA2dp);
      // The single most decisive line in this whole audit: if this says
      // a2dp=false, media audio is going to the PHONE and no amount of
      // app-side session/timing work can change that — the speaker simply
      // is not connected as a Bluetooth AUDIO device (BLE/GATT control and
      // classic A2DP audio are two separate links).
      debugPrint('[AUDIO_PATH] $label: OUTPUT DEVICES a2dp=$hasA2dp '
          '[${outputs.map((d) => '${d.type.name}:${d.name}').join(', ')}]');
    }).catchError((Object error) {
      debugPrint('[AUDIO_PATH] $label: getDevices() failed: $error');
    });
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

import 'dart:math';
import 'dart:typed_data';

/// Generates a clean, rising four-note chime — used ONLY for the
/// pre-measurement "can you hear the speaker?" confirmation step (see
/// `_MicCheckView` in measure_screen.dart). Deliberately a musical,
/// recognizable sound rather than a noise burst, so a user can never confuse
/// it with the actual pink-noise Room Scan measurement signal
/// ([PinkNoiseGenerator]) — "휴대폰 확인음과 스피커 측정음을 명확히 구분한다".
///
/// ~2.3s total, not the ~0.5s an earlier version used. Neither `audio_session`
/// nor `just_audio` expose any way to know when Android has actually finished
/// switching physical audio output to a connected Bluetooth speaker (see
/// tunai_playback_audio_session.dart) — that switch can take real, elapsed
/// PLAYBACK time after `play()` starts, not just time before it. A clip
/// short enough to finish entirely before the switch completes can play in
/// full from the phone's own speaker no matter how long the app waits
/// before calling `play()`. Making the clip itself long enough gives the
/// tail end a real chance to be heard from the actual connected speaker.
class ConfirmationToneGenerator {
  static const int sampleRate = 44100;
  static const int channels = 1;

  /// Four ascending pure tones played back-to-back (each note's own
  /// attack/release envelope keeps the transition clean without gaps),
  /// followed by one trailing silence — ~2.3s total.
  static const List<double> _noteFrequenciesHz = [880, 1046.5, 1318.5, 1568];
  static const double _noteDurationSeconds = 0.5;
  static const double _gapSeconds = 0.3;

  Uint8List generateWav() {
    final samplesPerNote = (sampleRate * _noteDurationSeconds).round();
    final samplesPerGap = (sampleRate * _gapSeconds).round();
    final totalSamples =
        _noteFrequenciesHz.length * samplesPerNote + samplesPerGap;
    final dataSize = totalSamples * 2; // 16-bit mono
    final fileSize = 44 + dataSize;

    final buf = ByteData(fileSize);
    // RIFF/WAVE/fmt/data header — identical layout to PinkNoiseGenerator's.
    buf.setUint8(0, 0x52);
    buf.setUint8(1, 0x49);
    buf.setUint8(2, 0x46);
    buf.setUint8(3, 0x46);
    buf.setUint32(4, fileSize - 8, Endian.little);
    buf.setUint8(8, 0x57);
    buf.setUint8(9, 0x41);
    buf.setUint8(10, 0x56);
    buf.setUint8(11, 0x45);
    buf.setUint8(12, 0x66);
    buf.setUint8(13, 0x6D);
    buf.setUint8(14, 0x74);
    buf.setUint8(15, 0x20);
    buf.setUint32(16, 16, Endian.little);
    buf.setUint16(20, 1, Endian.little);
    buf.setUint16(22, channels, Endian.little);
    buf.setUint32(24, sampleRate, Endian.little);
    buf.setUint32(28, sampleRate * channels * 2, Endian.little);
    buf.setUint16(32, channels * 2, Endian.little);
    buf.setUint16(34, 16, Endian.little);
    buf.setUint8(36, 0x64);
    buf.setUint8(37, 0x61);
    buf.setUint8(38, 0x74);
    buf.setUint8(39, 0x61);
    buf.setUint32(40, dataSize, Endian.little);

    var offset = 44;
    for (final freq in _noteFrequenciesHz) {
      for (var i = 0; i < samplesPerNote; i++) {
        final t = i / sampleRate;
        // Short attack/release envelope so each note doesn't click.
        final envelope = _envelope(i, samplesPerNote);
        final sample = sin(2 * pi * freq * t) * envelope * 0.6;
        buf.setInt16(
            offset, (sample * 32767).round().clamp(-32768, 32767), Endian.little);
        offset += 2;
      }
    }
    for (var i = 0; i < samplesPerGap; i++) {
      buf.setInt16(offset, 0, Endian.little);
      offset += 2;
    }

    return buf.buffer.asUint8List();
  }

  double _envelope(int sampleIndex, int totalSamples) {
    const rampSamples = 400;
    if (sampleIndex < rampSamples) return sampleIndex / rampSamples;
    final fromEnd = totalSamples - sampleIndex;
    if (fromEnd < rampSamples) return fromEnd / rampSamples;
    return 1.0;
  }
}

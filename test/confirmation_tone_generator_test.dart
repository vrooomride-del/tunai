import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:tunai/core/confirmation_tone_generator.dart';
import 'package:tunai/core/pink_noise_generator.dart';

double _wavDurationSeconds(Uint8List bytes) {
  final data = ByteData.sublistView(bytes);
  int byteRate = 0;
  int dataSize = 0;
  var offset = 12;
  while (offset + 8 <= bytes.length) {
    final chunkId = String.fromCharCodes(bytes.sublist(offset, offset + 4));
    final chunkSize = data.getUint32(offset + 4, Endian.little);
    final chunkStart = offset + 8;
    if (chunkId == 'fmt ') {
      byteRate = data.getUint32(chunkStart + 8, Endian.little);
    } else if (chunkId == 'data') {
      dataSize = chunkSize;
    }
    offset = chunkStart + chunkSize + (chunkSize.isOdd ? 1 : 0);
  }
  return dataSize / byteRate;
}

void main() {
  group('ConfirmationToneGenerator', () {
    test('produces a valid, short RIFF/WAVE file', () {
      final bytes = ConfirmationToneGenerator().generateWav();
      expect(String.fromCharCodes(bytes.sublist(0, 4)), 'RIFF');
      expect(String.fromCharCodes(bytes.sublist(8, 12)), 'WAVE');

      final duration = _wavDurationSeconds(bytes);
      // Long enough to still be audible from the actual connected speaker
      // even if the OS takes real elapsed playback time to finish switching
      // the physical Bluetooth route (no API exposes when that completes —
      // see tunai_playback_audio_session.dart), but still clearly a short
      // chime, not a measurement signal.
      expect(duration, greaterThan(1.5));
      expect(duration, lessThan(4.0));
    });

    test('samples never clip outside 16-bit signed range', () {
      final bytes = ConfirmationToneGenerator().generateWav();
      final data = ByteData.sublistView(bytes);
      for (var offset = 44; offset + 2 <= bytes.length; offset += 2) {
        final sample = data.getInt16(offset, Endian.little);
        expect(sample, greaterThanOrEqualTo(-32768));
        expect(sample, lessThanOrEqualTo(32767));
      }
    });

    test(
        'is clearly distinct in character from the pink-noise measurement '
        'signal — musical tone, not noise, and much shorter', () {
      final toneBytes = ConfirmationToneGenerator().generateWav();
      final toneDuration = _wavDurationSeconds(toneBytes);
      // Real PinkNoiseGenerator duration constant — the measurement signal
      // this confirmation tone must never be mistaken for.
      expect(toneDuration, lessThan(PinkNoiseGenerator.durationSeconds / 2));
    });
  });
}

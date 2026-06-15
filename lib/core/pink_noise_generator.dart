import 'dart:math';
import 'dart:typed_data';

/// Paul Kellet's refined pink noise algorithm
/// 20Hz~20kHz 균일 에너지 핑크노이즈 생성
class PinkNoiseGenerator {
  static const int sampleRate = 44100;
  static const int durationSeconds = 10;
  static const int channels = 1; // mono

  // Kellet filter state
  double _b0 = 0, _b1 = 0, _b2 = 0, _b3 = 0, _b4 = 0, _b5 = 0, _b6 = 0;
  final Random _random = Random();

  double _nextSample() {
    final white = _random.nextDouble() * 2.0 - 1.0;
    _b0 = 0.99886 * _b0 + white * 0.0555179;
    _b1 = 0.99332 * _b1 + white * 0.0750759;
    _b2 = 0.96900 * _b2 + white * 0.1538520;
    _b3 = 0.86650 * _b3 + white * 0.3104856;
    _b4 = 0.55000 * _b4 + white * 0.5329522;
    _b5 = -0.7616 * _b5 - white * 0.0168980;
    final pink = (_b0 + _b1 + _b2 + _b3 + _b4 + _b5 + _b6 + white * 0.5362) * 0.11;
    _b6 = white * 0.115926;
    return pink.clamp(-1.0, 1.0);
  }

  /// 16-bit PCM WAV 바이트 생성
  Uint8List generateWav() {
    const totalSamples = sampleRate * durationSeconds;
    const dataSize = totalSamples * 2; // 16bit = 2bytes per sample
    const fileSize = 44 + dataSize;

    final buf = ByteData(fileSize);

    // WAV Header
    // RIFF
    buf.setUint8(0, 0x52); buf.setUint8(1, 0x49);
    buf.setUint8(2, 0x46); buf.setUint8(3, 0x46);
    buf.setUint32(4, fileSize - 8, Endian.little);
    // WAVE
    buf.setUint8(8, 0x57); buf.setUint8(9, 0x41);
    buf.setUint8(10, 0x56); buf.setUint8(11, 0x45);
    // fmt chunk
    buf.setUint8(12, 0x66); buf.setUint8(13, 0x6D);
    buf.setUint8(14, 0x74); buf.setUint8(15, 0x20);
    buf.setUint32(16, 16, Endian.little);       // chunk size
    buf.setUint16(20, 1, Endian.little);         // PCM
    buf.setUint16(22, channels, Endian.little);  // channels
    buf.setUint32(24, sampleRate, Endian.little);
    buf.setUint32(28, sampleRate * channels * 2, Endian.little); // byte rate
    buf.setUint16(32, channels * 2, Endian.little); // block align
    buf.setUint16(34, 16, Endian.little);        // bits per sample
    // data chunk
    buf.setUint8(36, 0x64); buf.setUint8(37, 0x61);
    buf.setUint8(38, 0x74); buf.setUint8(39, 0x61);
    buf.setUint32(40, dataSize, Endian.little);

    // PCM samples
    for (int i = 0; i < totalSamples; i++) {
      final sample = (_nextSample() * 32767).round().clamp(-32768, 32767);
      buf.setInt16(44 + i * 2, sample, Endian.little);
    }

    return buf.buffer.asUint8List();
  }
}

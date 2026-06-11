import 'dart:math';
import 'dart:typed_data';
import 'package:fftea/fftea.dart';
import 'mic_calibration.dart';

class FrequencyBin {
  final double frequency;
  final double magnitude;
  const FrequencyBin({required this.frequency, required this.magnitude});
}

typedef CCV = Map<int, double>;

class AudioAnalyzer {
  static const int sampleRate = 44100;
  static const int fftSize = 65536;

  static double srefMagnitude(int binIndex) {
    if (binIndex == 0) return 0;
    final freq = binIndex * sampleRate / fftSize;
    if (freq < 20 || freq > 20000) return 0;
    return 1.0 / sqrt(freq);
  }

  static Float64List pcmToFloat(Uint8List pcmBytes) {
    final samples = Float64List(pcmBytes.length ~/ 2);
    final view = ByteData.sublistView(pcmBytes);
    for (int i = 0; i < samples.length; i++) {
      samples[i] = view.getInt16(i * 2, Endian.little) / 32768.0;
    }
    return samples;
  }

  static List<FrequencyBin> performFFT(Float64List samples) {
    final paddedSize = fftSize;
    final input = Float64List(paddedSize);
    final copyLen = min(samples.length, paddedSize);

    for (int i = 0; i < copyLen; i++) {
      final window = 0.5 * (1 - cos(2 * pi * i / (copyLen - 1)));
      input[i] = samples[i] * window;
    }

    final fft = FFT(paddedSize);
    final freq = fft.realFft(input);

    final bins = <FrequencyBin>[];
    final nyquist = paddedSize ~/ 2;

    for (int i = 1; i < nyquist; i++) {
      final re = freq[i].x;
      final im = freq[i].y;
      final magnitude = sqrt(re * re + im * im) / paddedSize;
      final frequency = i * sampleRate / paddedSize.toDouble();

      if (frequency >= 20 && frequency <= 20000) {
        final db = magnitude > 0 ? 20 * log(magnitude) / ln10 : -120.0;
        bins.add(FrequencyBin(frequency: frequency, magnitude: db));
      }
    }

    return bins;
  }

  static CCV calculateCCV(List<FrequencyBin> scapBins,
      {DeviceProfile? deviceProfile}) {
    final ccv = <int, double>{};
    for (int i = 0; i < scapBins.length; i++) {
      final bin = scapBins[i];
      final freq = bin.frequency;
      final binIndex = (freq * fftSize / sampleRate).round();
      final srefMag = srefMagnitude(binIndex);
      if (srefMag <= 0) continue;
      final scapLinear = pow(10, bin.magnitude / 20).toDouble();
      if (scapLinear <= 0) continue;

      // 기종별 마이크 보정 적용
      double deviceCorrection = 0.0;
      if (deviceProfile != null && deviceProfile.hasCalibration) {
        deviceCorrection = MicCalibrationDb.interpolateCorrection(
            deviceProfile.calibration!, freq);
      }
      final correctionLinear = pow(10, deviceCorrection / 20).toDouble();
      ccv[binIndex] = (srefMag / scapLinear) * correctionLinear;
    }
    return ccv;
  }

  static List<FrequencyBin> applyCCV(List<FrequencyBin> scapBins, CCV ccv) {
    return scapBins.map((bin) {
      final freq = bin.frequency;
      final binIndex = (freq * fftSize / sampleRate).round();
      final correction = ccv[binIndex] ?? 1.0;
      final scapLinear = pow(10, bin.magnitude / 20).toDouble();
      final scmsLinear = scapLinear * correction;
      final scmsDb = scmsLinear > 0 ? 20 * log(scmsLinear) / ln10 : -120.0;
      return FrequencyBin(frequency: freq, magnitude: scmsDb);
    }).toList();
  }

  static List<ResonancePeak> detectPeaks(List<FrequencyBin> scmsBins) {
    final targetBins = scmsBins
        .where((b) => b.frequency >= 20 && b.frequency <= 500)
        .toList();
    if (targetBins.isEmpty) return [];

    final avg = targetBins.map((b) => b.magnitude).reduce((a, b) => a + b)
        / targetBins.length;
    final peaks = <ResonancePeak>[];
    final threshold = avg + 3.0;

    for (int i = 1; i < targetBins.length - 1; i++) {
      final prev = targetBins[i - 1].magnitude;
      final curr = targetBins[i].magnitude;
      final next = targetBins[i + 1].magnitude;
      if (curr > prev && curr > next && curr > threshold) {
        final gainToReduce = -(curr - avg).clamp(1.0, 24.0);
        peaks.add(ResonancePeak(
          frequency: targetBins[i].frequency,
          gain: gainToReduce,
          q: 4.0,
        ));
      }
    }

    peaks.sort((a, b) => a.gain.compareTo(b.gain));
    return peaks.take(4).toList();
  }
}

class ResonancePeak {
  final double frequency;
  final double gain;
  final double q;

  const ResonancePeak({
    required this.frequency,
    required this.gain,
    required this.q,
  });

  @override
  String toString() =>
      'Peak(f=${frequency.toStringAsFixed(1)}Hz, G=${gain.toStringAsFixed(1)}dB, Q=$q)';
}
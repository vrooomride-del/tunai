import 'dart:math';
import 'package:fftea/fftea.dart';
import 'package:flutter/foundation.dart';

class FrequencyBin {
  final double frequency;
  final double magnitude;
  const FrequencyBin({required this.frequency, required this.magnitude});
}

typedef CCV = Map<int, double>;

class AudioAnalyzer {
  static const int sampleRate = 44100;
  static const int fftSize = 65536;

  /// 핑크노이즈 이론 스펙트럼 dB값 (1/f 파워 → -10*log10(f) + 오프셋)
  /// 오프셋은 de-mean 시 소거되므로 임의 기준(1kHz = 0dB) 사용
  static double srefDb(double freq) {
    if (freq <= 0) return 0;
    return -10 * log(freq / 1000) / ln10; // 1kHz 기준 0dB
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
    const paddedSize = fftSize;
    final input = Float64List(paddedSize);
    final copyLen = min(samples.length, paddedSize);

    for (int i = 0; i < copyLen; i++) {
      final window = 0.5 * (1 - cos(2 * pi * i / (copyLen - 1)));
      input[i] = samples[i] * window;
    }

    final fft = FFT(paddedSize);
    final freq = fft.realFft(input);

    final bins = <FrequencyBin>[];
    const nyquist = paddedSize ~/ 2;

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

  /// CCV 계산 — dB 도메인, 20Hz~2kHz 대역 평균 de-mean (안 2)
  ///
  /// 원리:
  ///   srefDb(f) = 핑크노이즈 이론 스펙트럼 형태 (dB)
  ///   scapDb(f) = MicCalibrationDb 보정 후 실측 스펙트럼 (dB)
  ///   raw_ccv[f] = srefDb(f) - scapDb(f)
  ///
  /// de-mean: 20Hz~2kHz 관심 대역의 raw_ccv 평균을 빼서
  ///   전체 레벨 오프셋을 제거하고 "형태 편차"만 남김.
  ///   → 동일 신호를 비교하면 raw_ccv가 상수가 되어 de-mean 후 0이 됨
  ///     (피크가 사라지는 예전 버그 재발 불가)
  ///
  /// [scapBins]: MicCalibrationDb 기종 보정이 이미 적용된 스펙트럼
  static CCV calculateCCV(List<FrequencyBin> scapBins) {
    // 관심 대역 필터
    final band = scapBins
        .where((b) => b.frequency >= 20 && b.frequency <= 2000)
        .toList();
    if (band.isEmpty) return {};

    // raw CCV (dB 차이) 계산
    final rawCcv = <double, double>{}; // freq → raw dB correction
    for (final bin in band) {
      rawCcv[bin.frequency] = srefDb(bin.frequency) - bin.magnitude;
    }

    // de-mean: 관심 대역 평균 제거
    final mean = rawCcv.values.reduce((a, b) => a + b) / rawCcv.length;
    debugPrint('[CCV] 관심 대역 raw_ccv 평균: ${mean.toStringAsFixed(2)}dB (제거됨)');

    // binIndex 기반 Map으로 변환
    final ccv = <int, double>{};
    for (final entry in rawCcv.entries) {
      final binIndex = (entry.key * fftSize / sampleRate).round();
      ccv[binIndex] = entry.value - mean; // de-meaned dB 보정값
    }
    return ccv;
  }

  /// CCV 적용 — dB 덧셈
  static List<FrequencyBin> applyCCV(List<FrequencyBin> scapBins, CCV ccv) {
    return scapBins.map((bin) {
      final binIndex = (bin.frequency * fftSize / sampleRate).round();
      final correction = ccv[binIndex] ?? 0.0; // 없으면 보정 없음 (0dB)
      return FrequencyBin(
          frequency: bin.frequency, magnitude: bin.magnitude + correction);
    }).toList();
  }

  static List<ResonancePeak> detectPeaks(List<FrequencyBin> scmsBins) {
    final targetBins = scmsBins
        .where((b) => b.frequency >= 20 && b.frequency <= 500)
        .toList();
    debugPrint('[PEAK] scmsBins total: ${scmsBins.length}, 20-500Hz bins: ${targetBins.length}');
    if (targetBins.isEmpty) return [];

    final avg = targetBins.map((b) => b.magnitude).reduce((a, b) => a + b)
        / targetBins.length;
    // 65536포인트 FFT → 0.67Hz/bin 해상도: ±30bin = ±20Hz 윈도우로 로컬 최대 검색
    const halfWin = 30;
    final threshold = avg + 1.5;
    debugPrint('[PEAK] avg=${avg.toStringAsFixed(1)}dB, threshold=${threshold.toStringAsFixed(1)}dB, halfWin=$halfWin');

    final peaks = <ResonancePeak>[];
    int i = halfWin;
    while (i < targetBins.length - halfWin) {
      final curr = targetBins[i].magnitude;
      if (curr <= threshold) { i++; continue; }

      // 윈도우 내 최대값인지 확인
      bool isLocalMax = true;
      for (int j = i - halfWin; j <= i + halfWin; j++) {
        if (j != i && targetBins[j].magnitude >= curr) { isLocalMax = false; break; }
      }
      if (isLocalMax) {
        final gainToReduce = -(curr - avg).clamp(1.0, 24.0);
        peaks.add(ResonancePeak(
          frequency: targetBins[i].frequency,
          gain: gainToReduce,
          q: 4.0,
        ));
        i += halfWin; // 같은 피크 중복 방지
      } else {
        i++;
      }
    }

    debugPrint('[PEAK] raw peaks found: ${peaks.length}');
    peaks.sort((a, b) => a.gain.compareTo(b.gain));
    final result = peaks.take(4).toList();
    for (final p in result) { debugPrint('[PEAK] → $p'); }
    return result;
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
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

  /// Result of analysing one capture: the averaged spectrum, plus a real
  /// measure of how much that spectrum can be trusted.
  static CaptureAnalysis analyzeCapture(Float64List samples) =>
      _analyze(samples);

  /// Averages the power spectrum over the WHOLE recording (Welch's method:
  /// overlapping Hann-windowed frames, averaged in the power domain), rather
  /// than transforming one frame and discarding the rest.
  ///
  /// This used to run a single [fftSize] transform, which on a 10-second
  /// 44.1kHz capture meant analysing the first 65536 samples — **1.49 seconds
  /// of a 10-second recording, with the other 85% thrown away**. Two
  /// consequences, both visible in real-device captures:
  ///
  ///  * No averaging at all, so every bin carried the full variance of a
  ///    single snapshot. Random noise peaks looked exactly like room modes,
  ///    which is why repeat captures of the same room returned almost
  ///    entirely different "resonances" each time.
  ///  * The analysed slice was the WORST part of the recording: capture
  ///    starts before playback does, so the opening moments hold near-silence
  ///    plus whatever is still settling on the audio route.
  ///
  /// Averaging N frames cuts the standard deviation of each bin by about
  /// sqrt(N); a 10-second capture yields ~12 frames at 50% overlap, so the
  /// run-to-run spread shrinks several-fold. Nothing is fabricated — this is
  /// strictly more of the data that was already recorded.
  static List<FrequencyBin> performFFT(Float64List samples) =>
      _analyze(samples).bins;

  static CaptureAnalysis _analyze(Float64List samples) {
    if (samples.isEmpty) return CaptureAnalysis.empty;
    const frameSize = fftSize;
    const hop = frameSize ~/ 2; // 50% overlap
    final fft = FFT(frameSize);

    // Frame the recording; a capture shorter than one frame is zero-padded
    // and analysed as a single frame, exactly as before.
    final frameStarts = <int>[];
    if (samples.length <= frameSize) {
      frameStarts.add(0);
    } else {
      for (var start = 0; start + frameSize <= samples.length; start += hop) {
        frameStarts.add(start);
      }
    }

    // Frame energies, used to drop the near-silent lead-in/tail. Median-
    // relative so it needs no absolute threshold and adapts to playback
    // level: a frame more than 6dB below the median is not signal.
    final energies = [
      for (final start in frameStarts) _frameRms(samples, start, frameSize)
    ];
    final sortedEnergies = [...energies]..sort();
    final medianEnergy = sortedEnergies[sortedEnergies.length ~/ 2];
    // Digital silence carries no spectrum. Returning an all-floor curve here
    // would hand downstream analysis a fabricated "measurement".
    if (medianEnergy <= 0) return CaptureAnalysis.empty;
    final energyFloor = medianEnergy * 0.5;

    const nyquist = frameSize ~/ 2;
    final power = Float64List(nyquist);
    // Two independent accumulators over alternating frames. Averaging them
    // together gives the same spectrum as one accumulator would, but keeping
    // them apart also yields a genuine repeatability measure from a SINGLE
    // capture, at no extra recording time — see [CaptureAnalysis.agreement].
    final powerA = Float64List(nyquist);
    final powerB = Float64List(nyquist);
    var framesUsed = 0;
    var framesA = 0;
    var framesB = 0;

    for (var f = 0; f < frameStarts.length; f++) {
      if (frameStarts.length > 1 && energies[f] < energyFloor) continue;
      final start = frameStarts[f];
      final input = Float64List(frameSize);
      final copyLen = min(samples.length - start, frameSize);
      for (var i = 0; i < copyLen; i++) {
        final window = 0.5 * (1 - cos(2 * pi * i / (frameSize - 1)));
        input[i] = samples[start + i] * window;
      }
      final freq = fft.realFft(input);
      for (var i = 1; i < nyquist; i++) {
        final re = freq[i].x;
        final im = freq[i].y;
        // Accumulate POWER, not dB — averaging in the dB domain would bias
        // the result low and is not a mean spectrum at all.
        final p = (re * re + im * im) / (frameSize * frameSize.toDouble());
        power[i] += p;
        if (framesUsed.isEven) {
          powerA[i] += p;
        } else {
          powerB[i] += p;
        }
      }
      if (framesUsed.isEven) {
        framesA++;
      } else {
        framesB++;
      }
      framesUsed++;
    }
    if (framesUsed == 0) return CaptureAnalysis.empty;

    debugPrint('[FFT] Welch average over $framesUsed/${frameStarts.length} '
        'frames (${(samples.length / sampleRate).toStringAsFixed(1)}s capture)');

    final bins = <FrequencyBin>[];
    for (var i = 1; i < nyquist; i++) {
      final frequency = i * sampleRate / frameSize.toDouble();
      if (frequency < 20 || frequency > 20000) continue;
      final meanPower = power[i] / framesUsed;
      final db = meanPower > 0 ? 10 * log(meanPower) / ln10 : -120.0;
      bins.add(FrequencyBin(frequency: frequency, magnitude: db));
    }

    final agreement =
        _splitHalfAgreement(powerA, powerB, framesA, framesB, frameSize);
    debugPrint('[FFT] split-half agreement='
        '${agreement.toStringAsFixed(2)} (1.0 = the two halves of this '
        'capture describe the same spectrum)');
    return CaptureAnalysis(bins: bins, agreement: agreement);
  }

  /// How closely the even- and odd-numbered frames of the same capture agree,
  /// mapped to 0..1 over the room-mode analysis band.
  ///
  /// This measures how SETTLED the spectrum estimate is — whether enough of
  /// the recording was averaged for the result to stop moving. It replaces a
  /// `consistencyMetric` that was the fraction of finite bins: 1.0 by
  /// construction for any capture reaching this point, and so a number that
  /// measured nothing at all.
  ///
  /// What it does NOT do, deliberately stated so it is not read as more than
  /// it is: it cannot by itself separate a real room response from the
  /// microphone's noise floor. The excitation is pink noise, which is random,
  /// so both cases carry similar per-bin variance. Judging whether the
  /// analysed band actually received signal is a separate question — see the
  /// `[SIGNAL]` band-level logging in `measurement_controller.dart`.
  ///
  /// Returns 1.0 for perfect agreement, falling linearly to 0.0 at
  /// [_disagreementCeilingDb] of mean absolute difference.
  static double _splitHalfAgreement(Float64List powerA, Float64List powerB,
      int framesA, int framesB, int frameSize) {
    if (framesA == 0 || framesB == 0) return 0;
    var sum = 0.0;
    var count = 0;
    for (var i = 1; i < powerA.length; i++) {
      final frequency = i * sampleRate / frameSize.toDouble();
      if (frequency < 20 || frequency > roomModeSearchCeilingHz) continue;
      final a = powerA[i] / framesA;
      final b = powerB[i] / framesB;
      if (a <= 0 || b <= 0) continue;
      sum += (10 * log(a) / ln10 - 10 * log(b) / ln10).abs();
      count++;
    }
    if (count == 0) return 0;
    final meanAbsDiffDb = sum / count;
    return (1 - meanAbsDiffDb / _disagreementCeilingDb).clamp(0.0, 1.0);
  }

  /// Mean half-to-half difference at which a capture is treated as carrying
  /// no trustworthy spectrum at all. Two halves of a stable measurement agree
  /// within a couple of dB; 6dB of mean disagreement means the "spectrum" is
  /// dominated by noise that happened to land differently in each half.
  static const double _disagreementCeilingDb = 6;

  static double _frameRms(Float64List samples, int start, int frameSize) {
    final end = min(start + frameSize, samples.length);
    var sum = 0.0;
    for (var i = start; i < end; i++) {
      sum += samples[i] * samples[i];
    }
    final count = end - start;
    return count == 0 ? 0 : sqrt(sum / count);
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

  /// Room-mode search ceiling. Below the Schroeder frequency (~150–300Hz for
  /// a typical living-room-sized enclosure), room modes are sparse, discrete,
  /// and individually correctable. Above it, modal density rises until peaks
  /// overlap into a statistically diffuse field — an isolated local maximum
  /// up there is far more likely to be the speaker's own driver/cabinet
  /// response (or measurement noise) than an actual, correctable room mode,
  /// and "correcting" it risks fighting the speaker's real voicing rather
  /// than the room. 300Hz keeps a safety margin above typical small-room
  /// Schroeder frequencies while excluding the 350–450Hz band where this
  /// misattribution was observed.
  static const double roomModeSearchCeilingHz = 300;

  static List<ResonancePeak> detectPeaks(List<FrequencyBin> inputBins) {
    final targetBins = inputBins
        .where(
            (b) => b.frequency >= 20 && b.frequency <= roomModeSearchCeilingHz)
        .toList();
    debugPrint('[PEAK] input bins total: ${inputBins.length}, '
        '20-${roomModeSearchCeilingHz.toStringAsFixed(0)}Hz bins: ${targetBins.length}');
    if (targetBins.isEmpty) return [];

    final avg = targetBins.map((b) => b.magnitude).reduce((a, b) => a + b) /
        targetBins.length;
    // 65536포인트 FFT → 0.67Hz/bin 해상도: ±30bin = ±20Hz 윈도우로 로컬 최대 검색
    const halfWin = 30;
    final threshold = avg + 1.5;
    debugPrint(
        '[PEAK] avg=${avg.toStringAsFixed(1)}dB, threshold=${threshold.toStringAsFixed(1)}dB, halfWin=$halfWin');

    final peaks = <ResonancePeak>[];
    int i = halfWin;
    while (i < targetBins.length - halfWin) {
      final curr = targetBins[i].magnitude;
      if (curr <= threshold) {
        i++;
        continue;
      }

      // 윈도우 내 최대값인지 확인
      bool isLocalMax = true;
      for (int j = i - halfWin; j <= i + halfWin; j++) {
        if (j != i && targetBins[j].magnitude >= curr) {
          isLocalMax = false;
          break;
        }
      }
      if (isLocalMax) {
        final gainToReduce = -(curr - avg).clamp(1.0, 24.0);
        final q = _estimateQ(targetBins, i, curr, searchBins: halfWin);
        peaks.add(ResonancePeak(
          frequency: targetBins[i].frequency,
          gain: gainToReduce,
          q: q,
        ));
        i += halfWin; // 같은 피크 중복 방지
      } else {
        i++;
      }
    }

    debugPrint('[PEAK] raw peaks found: ${peaks.length}');
    peaks.sort((a, b) => a.gain.compareTo(b.gain));
    final result = peaks.take(4).toList();
    for (final p in result) {
      debugPrint('[PEAK] → $p');
    }
    return result;
  }

  /// Fallback Q used whenever the actual -3dB bandwidth can't be measured
  /// reliably (e.g. the bump is wider than the local-max search window and
  /// never crosses back down within it). This is the same fixed value every
  /// peak used to get unconditionally before Q was estimated from bandwidth.
  static const double defaultPeakQ = 4.0;

  /// Estimates a peak's Q from its own measured bandwidth — no new
  /// measurement or algorithm: it re-reads the same [bins] already scanned
  /// for the local maximum at [peakIndex].
  ///
  /// Q = centerFrequency / bandwidth, where bandwidth is the distance
  /// between the two -3dB (half-power) points either side of the peak,
  /// measured relative to the peak's own magnitude (not the band average) —
  /// the standard resonance-Q definition. A narrow, sharp room resonance
  /// yields a small bandwidth → high Q (surgical notch). A broad, gentle
  /// bass boom yields a large bandwidth → low Q (gentle shelf-like cut).
  static double _estimateQ(
    List<FrequencyBin> bins,
    int peakIndex,
    double peakMagnitude, {
    required int searchBins,
  }) {
    final halfPowerLevel = peakMagnitude - 3.0;

    int? leftIndex;
    for (var j = peakIndex - 1; j >= 0 && peakIndex - j <= searchBins; j--) {
      if (bins[j].magnitude <= halfPowerLevel) {
        leftIndex = j;
        break;
      }
    }
    int? rightIndex;
    for (var j = peakIndex + 1;
        j < bins.length && j - peakIndex <= searchBins;
        j++) {
      if (bins[j].magnitude <= halfPowerLevel) {
        rightIndex = j;
        break;
      }
    }
    // Either side never dropped 3dB within the local-max search window —
    // too wide/ambiguous to trust a bandwidth measurement from.
    if (leftIndex == null || rightIndex == null) return defaultPeakQ;

    final bandwidth = bins[rightIndex].frequency - bins[leftIndex].frequency;
    if (bandwidth <= 0) return defaultPeakQ;

    final q = bins[peakIndex].frequency / bandwidth;
    if (!q.isFinite || q <= 0) return defaultPeakQ;
    // Clamped to the same [0.3, 16] range RoomMeasurementValidator.validate()
    // requires (room_measurement.dart). A sharp real room mode measured at
    // ~0.67Hz FFT bin resolution can yield a bandwidth of only 1-2 bins,
    // producing a raw Q far above what the validator accepts — without this
    // clamp, a fully successful capture+peak-detection was thrown away by
    // downstream validation (StateError), which looked like Room Scan
    // silently bouncing back to its own screen.
    return q.clamp(minEstimatedQ, maxEstimatedQ);
  }

  static const double minEstimatedQ = 0.3;
  static const double maxEstimatedQ = 16.0;
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

/// One capture's analysed spectrum together with how far it can be trusted.
@immutable
class CaptureAnalysis {
  final List<FrequencyBin> bins;

  /// 0..1, from [AudioAnalyzer]'s split-half comparison. 1.0 means the two
  /// halves of the recording describe the same spectrum (a stable room);
  /// near 0 means they do not, so nothing detected in it should be presented
  /// to the user as a property of their room.
  final double agreement;

  const CaptureAnalysis({required this.bins, required this.agreement});

  static const empty = CaptureAnalysis(bins: [], agreement: 0);
}

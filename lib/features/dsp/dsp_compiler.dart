import 'dart:math';
import 'dart:typed_data';
import '../../core/audio_analyzer.dart';

/// Biquad IIR 노치 필터 계수
class BiquadCoefficients {
  final double b0, b1, b2, a1, a2;
  const BiquadCoefficients({
    required this.b0, required this.b1, required this.b2,
    required this.a1, required this.a2,
  });

  @override
  String toString() =>
      'Biquad(b0=$b0, b1=$b1, b2=$b2, a1=$a1, a2=$a2)';
}

/// DSP 레지스터 패킷
class RegisterPacket {
  final int pramTargetAddr;   // PRAM 목표 주소
  final List<int> coeffBytes; // 5개 계수 × 4바이트 = 20바이트

  const RegisterPacket({
    required this.pramTargetAddr,
    required this.coeffBytes,
  });
}

class DspCompiler {
  // ADAU1701 기본 샘플레이트 (48kHz 권장, 44.1kHz도 지원)
  static const int sampleRate = 48000;

  // ADAU1701 Safeload 레지스터 주소 (데이터시트 Rev.C Table 21)
  static const int safeloadData0 = 0x0810;
  static const int safeloadAddr0 = 0x0815;

  // BLE 프레임 상수
  static const int bleHeader = 0xAA;
  static const int bleFooter = 0x55;

  /// 표준 쌍선형 변환 (Bilinear Transform) Peaking EQ 노치 필터
  /// ※ ADAU1701 SigmaStudio 아키텍처: a1, a2 계수에 음의 부호 적용 필수
  static BiquadCoefficients calculateNotchBiquad(
      double f, double gainDb, double q) {
    final w0 = 2 * pi * f / sampleRate;
    final A = pow(10, gainDb / 40).toDouble(); // 진폭 스케일
    final alpha = sin(w0) / (2 * q);

    final b0 = 1 + alpha * A;
    final b1 = -2 * cos(w0);
    final b2 = 1 - alpha * A;
    final a0 = 1 + alpha / A;
    final a1 = -2 * cos(w0);
    final a2 = 1 - alpha / A;

    // a0으로 정규화 + SigmaStudio 부호 규칙: a1, a2에 음수 부호 적용
    return BiquadCoefficients(
      b0: b0 / a0,
      b1: b1 / a0,
      b2: b2 / a0,
      a1: -(a1 / a0), // SigmaStudio: 음의 부호 필수
      a2: -(a2 / a0), // SigmaStudio: 음의 부호 필수
    );
  }

  /// ADAU1701 5.23 고정소수점 변환 (28bit)
  /// 표현 범위: -16.0 ~ +15.9999999
  /// +1.0 = 0x00800000, -1.0 = 0xFF800000
  /// 변환: coeff × 2^23(8388608) → 28bit 마스킹
  static int toFixed523(double value) {
    final clamped = value.clamp(-16.0, 15.9999999);
    int fixedVal = (clamped * 8388608).round();
    if (fixedVal < 0) {
      fixedVal = (0x10000000 + fixedVal) & 0x0FFFFFFF;
    }
    return fixedVal;
  }

  /// 28bit 정수 → 4바이트 big-endian
  static List<int> toBytes4(int value) => [
    (value >> 24) & 0xFF,
    (value >> 16) & 0xFF,
    (value >> 8) & 0xFF,
    value & 0xFF,
  ];

  /// FPS → RegisterPacket 컴파일
  static RegisterPacket compilePeak(ResonancePeak peak, int pramAddr) {
    final coeff = calculateNotchBiquad(peak.frequency, peak.gain, peak.q);

    final bytes = <int>[];
    for (final c in [coeff.b0, coeff.b1, coeff.b2, coeff.a1, coeff.a2]) {
      bytes.addAll(toBytes4(toFixed523(c)));
    }

    return RegisterPacket(pramTargetAddr: pramAddr, coeffBytes: bytes);
  }

  /// 복수 피크 → 복수 패킷
  static List<RegisterPacket> compileAll(
      List<ResonancePeak> peaks, {int startPramAddr = 0x0010}) {
    final packets = <RegisterPacket>[];
    int addr = startPramAddr;
    for (final peak in peaks) {
      packets.add(compilePeak(peak, addr));
      addr += 5;
    }
    return packets;
  }

  /// BLE 전송용 27바이트 프레임 생성
  /// [Header(1)] [TargetAddr(2)] [Data(20)] [Checksum(1)] [Footer(1)]
  static Uint8List buildBleFrame(RegisterPacket packet) {
    final frame = Uint8List(27);
    int idx = 0;

    // Header
    frame[idx++] = bleHeader; // 0xAA

    // Target Address (2바이트, big-endian)
    frame[idx++] = (packet.pramTargetAddr >> 8) & 0xFF;
    frame[idx++] = packet.pramTargetAddr & 0xFF;

    // Data Payload (20바이트: b0,b1,b2,a1,a2 각 4바이트)
    for (final b in packet.coeffBytes) {
      frame[idx++] = b;
    }

    // Checksum: Header~Data 전체 XOR
    int checksum = 0;
    for (int i = 0; i < 23; i++) {
      checksum ^= frame[i];
    }
    frame[idx++] = checksum;

    // Footer
    frame[idx++] = bleFooter; // 0x55

    return frame;
  }

  /// I²C Safeload 트랜잭션 목록 생성 (MCU가 순서대로 실행)
  /// 1. Safeload Data 레지스터 0x0810~0x0814 에 계수 기입
  /// 2. Safeload Address 레지스터 0x0815 에 PRAM 목표 주소 기입 (트리거)
  static List<Uint8List> buildI2CTransactions(RegisterPacket packet) {
    final txs = <Uint8List>[];

    // Safeload Data (5개 계수)
    for (int i = 0; i < 5; i++) {
      final addr = safeloadData0 + i;
      final tx = Uint8List(6);
      tx[0] = (addr >> 8) & 0xFF;
      tx[1] = addr & 0xFF;
      tx.setRange(2, 6, packet.coeffBytes.sublist(i * 4, i * 4 + 4));
      txs.add(tx);
    }

    // Safeload Address → 트리거
    final targetBytes = toBytes4(packet.pramTargetAddr);
    final triggerTx = Uint8List(6);
    triggerTx[0] = (safeloadAddr0 >> 8) & 0xFF;
    triggerTx[1] = safeloadAddr0 & 0xFF;
    triggerTx.setRange(2, 6, targetBytes);
    txs.add(triggerTx);

    return txs;
  }
}

// ── T/S 기반 안전범위 자동 적용 ─────────────────────────────

/// T/S 파라미터로부터 HPF + Gain 안전 설정 자동 생성
class SafetyProfile {
  final double hpfFreq;      // 권장 HPF 주파수 (Hz)
  final double maxBassBoost; // 최대 저역 부스트 (dB)
  final double gainOffset;   // 감도 기준 게인 오프셋 (dB)

  const SafetyProfile({
    required this.hpfFreq,
    required this.maxBassBoost,
    required this.gainOffset,
  });
}

extension DspCompilerSafety on DspCompiler {
  /// T/S → SafetyProfile 변환
  static SafetyProfile safetyFromTs({
    required double fs,
    required double xmax,
    required double sensitivity,
  }) {
    return SafetyProfile(
      hpfFreq: fs * 0.85,
      maxBassBoost: xmax >= 10 ? 6.0 : xmax >= 6 ? 4.0 : xmax >= 3 ? 2.0 : 0.0,
      gainOffset: sensitivity - 85.0,
    );
  }

  /// HPF Biquad 계수 계산 (2nd order Butterworth)
  static BiquadCoefficients calculateHpf(double freq) {
    final w0 = 2 * pi * freq / DspCompiler.sampleRate;
    final q = 0.7071; // Butterworth Q
    final alpha = sin(w0) / (2 * q);
    final cosW = cos(w0);

    final b0 = (1 + cosW) / 2;
    final b1 = -(1 + cosW);
    final b2 = (1 + cosW) / 2;
    final a0 = 1 + alpha;
    final a1 = -2 * cosW;
    final a2 = 1 - alpha;

    return BiquadCoefficients(
      b0: b0 / a0,
      b1: b1 / a0,
      b2: b2 / a0,
      a1: -(a1 / a0),
      a2: -(a2 / a0),
    );
  }

  /// PEQ gainDb를 Xmax 기반으로 클램핑
  static double clampBassBoost(double gainDb, double freq, double maxBoostDb) {
    if (freq < 200 && gainDb > maxBoostDb) return maxBoostDb;
    return gainDb;
  }
}

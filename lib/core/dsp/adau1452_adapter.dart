import 'dsp_adapter.dart';

/// ADAU1452/1466 + CS42448 ("파란보드") 어댑터 — 스켈레톤
///
/// 실제 레지스터 주소는 SigmaStudio 프로젝트
/// (1466_cs42448_18out.dspproj) export → params.dat / .h 파일 확정 후 채울 것.
///
/// WONDOM ICP5와의 BLE 프로토콜은 ADAU1701과 다를 수 있음 —
/// WONDOM 문서 확인 후 buildBleFrame() 구현.
///
/// TODO: 다음 세션에서 SigmaStudio 주소맵 확정 시 구현
///   - _pramAddr(channelIndex, bandIndex) → ADAU1452 PRAM 주소
///   - buildBleFrame(addr, bytes) → ICP5 BLE 프레임 포맷
///   - writeCrossover / writeDelay / writeGain / writeSubsonicFilter
class Adau1452Adapter implements DspAdapter {
  // ignore: unused_field
  final RawWriteFn _writeRaw;

  Adau1452Adapter({required RawWriteFn writeRaw}) : _writeRaw = writeRaw;

  @override
  Future<void> writeBiquad(int channelIndex, int bandIndex, BiquadCoeffs coeffs) async {
    // TODO: ADAU1452 PRAM 주소 계산 + 5.27 고정소수점 변환 + ICP5 BLE 프레임
    // ADAU1452: 5.27 포맷 (ADAU1701의 5.23과 다름)
    throw UnimplementedError('ADAU1452 PRAM 주소맵 미확정 — SigmaStudio export 후 구현');
  }

  @override
  Future<void> writeCrossover(int channelIndex, CrossoverConfig config) async {
    // TODO: LR4 크로스오버 Biquad 계수 → writeBiquad 호출
    throw UnimplementedError('ADAU1452 크로스오버 미구현');
  }

  @override
  Future<void> writeDelay(int channelIndex, double delayMs) async {
    // TODO: ADAU1452 딜레이 셀 주소 기입
    throw UnimplementedError('ADAU1452 딜레이 미구현');
  }

  @override
  Future<void> writeGain(int channelIndex, double gainDb) async {
    // TODO: ADAU1452 게인 셀 주소 기입
    throw UnimplementedError('ADAU1452 게인 미구현');
  }

  @override
  Future<void> writeSubsonicFilter(int channelIndex, double freqHz) async {
    // TODO: 서브소닉 HPF Biquad → writeBiquad 호출
    throw UnimplementedError('ADAU1452 서브소닉 필터 미구현');
  }

  @override
  Future<DspState> readCurrentState() async {
    // TODO: ICP5 읽기 프로토콜 확인 후 구현
    return const DspState(raw: {});
  }

  // ── 내부 유틸 (구현 예정) ──────────────────────────────────

  /// TODO: ADAU1452 5.27 고정소수점 변환
  /// 변환: coeff × 2^27 → 32bit
  // static int _toFixed527(double value) { ... }

  /// TODO: ICP5 BLE 프레임 포맷 (WONDOM 문서 확인 필요)
  // static Uint8List _buildBleFrame(int addr, List<int> data) { ... }
}

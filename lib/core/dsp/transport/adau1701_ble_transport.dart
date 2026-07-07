import 'package:flutter/foundation.dart';
import 'dsp_transport.dart';

/// ADAU1701 BLE 전송 계층 — ICP5(WONDOM) BLE GATT fff2 경유.
/// BleController.sendRawFrame() 콜백을 통해 실제 전송을 위임한다.
class Adau1701BleTransport implements DspTransport {
  final Future<void> Function(Uint8List) _sendRawFrame;

  Adau1701BleTransport(this._sendRawFrame);

  /// 27바이트 ICP5 프레임: [AA][addr 2B][word0 4B][zeros 16B][XOR][55][zeros 2B]
  @override
  Future<void> writeParameter(int address, List<int> bytes4) async {
    assert(bytes4.length == 4, 'bytes4 must be exactly 4 bytes');
    final frame = _buildFrame(address, bytes4);
    try {
      await _sendRawFrame(frame);
    } catch (e) {
      debugPrint('[ADAU1701 BLE] writeParameter failed: $e'
          ' (addr=0x${address.toRadixString(16)})');
    }
  }

  static Uint8List _buildFrame(int addr, List<int> word0bytes) {
    final frame = Uint8List(27); // ICP5 MCU가 기대하는 고정 크기
    frame[0] = 0xAA;
    frame[1] = (addr >> 8) & 0xFF;
    frame[2] = addr & 0xFF;
    frame[3] = word0bytes[0];
    frame[4] = word0bytes[1];
    frame[5] = word0bytes[2];
    frame[6] = word0bytes[3];
    // frame[7..22]: word1~4 = 0 (Uint8List 초기화값)
    int chk = 0;
    for (int i = 0; i < 23; i++) {
      chk ^= frame[i];
    }
    frame[23] = chk;
    frame[24] = 0x55;
    // frame[25..26]: 패딩 0
    return frame;
  }

  @override
  Future<List<int>?> readParameter(int address) async => null;

  @override
  Future<bool> detectDevice() async => true;

  @override
  void dispose() {}
}

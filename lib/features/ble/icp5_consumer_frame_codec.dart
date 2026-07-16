import 'dart:convert';

/// Consumer-only subset of the capture-proven ICP5 frame codec.
///
/// The profile is deliberately kept internal. Consumer UI receives only a
/// boolean supported/unsupported result.
abstract final class Icp5ConsumerFrameCodec {
  static const identificationRequest = <int>[
    0x55,
    0x07,
    0x1A,
    0x00,
    0x00,
    0x00,
    0x00,
    0x00,
    0x76,
  ];

  static const _expectedProfile = 'DSP1701.100.00.01';

  static int checksum(Iterable<int> bytes) =>
      bytes.fold<int>(0, (sum, byte) => (sum + byte) & 0xff);

  static bool hasValidEnvelope(List<int> frame) =>
      frame.length >= 4 &&
      frame.first == 0x55 &&
      frame.length == frame[1] + 2 &&
      checksum(frame.take(frame.length - 1)) == frame.last;

  static bool isSupportedIdentity(List<int> frame) {
    if (!hasValidEnvelope(frame) || frame[2] != 0xe0 || frame.length < 10) {
      return false;
    }
    try {
      return ascii.decode(frame.sublist(8, frame.length - 1)) ==
          _expectedProfile;
    } on FormatException {
      return false;
    }
  }
}

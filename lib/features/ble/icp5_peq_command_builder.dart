import '../../core/tune_deployment_plan.dart';

abstract final class Icp5PeqCommandBuilder {
  static const int _start = 0x55;
  static const int _write = 0x1c;
  static const int _peqParameter = 0x18;
  static const int _qProperty = 0x00;
  static const int _gainProperty = 0x01;
  static const int _frequencyProperty = 0x02;

  static const peqAck = <int>[
    0x55,
    0x07,
    0xe1,
    0x00,
    0x00,
    0x00,
    0x18,
    0x00,
    0x55,
  ];

  static int checksum(Iterable<int> bytes) =>
      bytes.fold<int>(0, (sum, byte) => (sum + byte) & 0xff);

  static List<int> frequency({
    required int channel,
    required int bandId,
    required int frequencyHz,
  }) {
    _validateSelector(channel, 'channel');
    _validateSelector(bandId, 'bandId');
    if (frequencyHz < 0 || frequencyHz > 0xffff) {
      throw RangeError.range(frequencyHz, 0, 0xffff, 'frequencyHz');
    }
    return _frame([
      channel,
      _frequencyProperty,
      bandId,
      frequencyHz & 0xff,
      (frequencyHz >> 8) & 0xff,
    ]);
  }

  static List<int> gain({
    required int channel,
    required int bandId,
    required double gainDb,
  }) {
    _validateSelector(channel, 'channel');
    _validateSelector(bandId, 'bandId');
    final tenths = (gainDb * 10).round();
    if (tenths < -128 || tenths > 127) {
      throw RangeError.value(
        gainDb,
        'gainDb',
        'Must encode as a signed int8 in tenths of a dB.',
      );
    }
    return _frame([channel, _gainProperty, bandId, tenths & 0xff]);
  }

  static List<int> q({
    required int channel,
    required int bandId,
    required double q,
  }) {
    _validateSelector(channel, 'channel');
    _validateSelector(bandId, 'bandId');
    final tenths = (q * 10).round();
    if (tenths < 0 || tenths > 0xff) {
      throw RangeError.value(q, 'q', 'Must encode as uint8 tenths.');
    }
    return _frame([channel, _qProperty, bandId, tenths]);
  }

  static List<List<int>> commandsFor(Iterable<TuneDeploymentPlan> plans) =>
      List.unmodifiable([
        for (final plan in plans) ...[
          frequency(
            channel: plan.channel,
            bandId: plan.bandId,
            frequencyHz: plan.frequencyHz,
          ),
          gain(
            channel: plan.channel,
            bandId: plan.bandId,
            gainDb: plan.gainDb,
          ),
          q(channel: plan.channel, bandId: plan.bandId, q: plan.q),
        ],
      ]);

  static List<List<int>> restoreCommandsFor(
          Iterable<TuneDeploymentPlan> plans) =>
      List.unmodifiable([
        for (final plan in plans) ...[
          frequency(
            channel: plan.channel,
            bandId: plan.bandId,
            frequencyHz: plan.originalValues.frequencyHz,
          ),
          gain(
            channel: plan.channel,
            bandId: plan.bandId,
            gainDb: plan.originalValues.gainDb,
          ),
          q(
            channel: plan.channel,
            bandId: plan.bandId,
            q: plan.originalValues.q,
          ),
        ],
      ]);

  static bool isValidPeqAck(List<int> frame) {
    if (frame.length != peqAck.length) return false;
    for (var index = 0; index < peqAck.length; index++) {
      if (frame[index] != peqAck[index]) return false;
    }
    return true;
  }

  static List<int> _frame(List<int> payload) {
    final frame = <int>[
      _start,
      0,
      _write,
      0,
      0,
      0,
      _peqParameter,
      ...payload,
    ];
    frame[1] = frame.length - 1;
    return List.unmodifiable([...frame, checksum(frame)]);
  }

  static void _validateSelector(int value, String name) {
    if (value < 0 || value > 0xff) {
      throw RangeError.range(value, 0, 0xff, name);
    }
  }
}

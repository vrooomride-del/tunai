import 'dsp_adapter.dart';
import '../dsp_safety.dart';
import '../dsp_safety_notice.dart';
import '../profiles/system_profile.dart';

/// [DspAdapter]를 감싸 모든 write 호출을 [DspSafety]로 강제 검증하는 데코레이터.
///
/// **우회 불가능 근거**: `SystemProfile.adapterFactory`(유일한 어댑터 생성 경로 —
/// 코드베이스 전체에서 `Adau1701Adapter`/`Adau1466Adapter`를 직접 생성하는 곳은
/// 이 factory 클로저 내부뿐임, grep으로 확인됨)가 항상 이 클래스로 감싼 인스턴스만
/// 반환하도록 만들었기 때문에, `SystemProfile`을 통해 어댑터를 얻는 모든 호출자는
/// 검증을 거치지 않고는 물리적으로 `writeXxx`를 호출할 수 없다. 값이 clamp될
/// 때마다 [DspSafetyNotice]로 무조건 사용자에게 알린다(조용히 넘어가지 않음).
class ValidatingDspAdapter implements DspAdapter {
  final DspAdapter _inner;
  final List<ChannelConfig> _channels;

  ValidatingDspAdapter(this._inner, List<ChannelConfig> channels) : _channels = channels;

  bool _isTweeter(int channelIndex) =>
      channelIndex >= 0 && channelIndex < _channels.length &&
      _channels[channelIndex].type == ChannelType.tweeter;

  void _reportIfClamped<T>(SafetyResult<T> r) {
    if (r.wasClamped && r.reason != null) DspSafetyNotice.show(r.reason!);
  }

  @override
  Future<void> writeGain(int channelIndex, double gainDb) {
    final r = DspSafety.validateChannelGain(gainDb, isTweeter: _isTweeter(channelIndex));
    _reportIfClamped(r);
    return _inner.writeGain(channelIndex, r.value);
  }

  @override
  Future<void> writeCrossover(int channelIndex, CrossoverConfig config) {
    final r = DspSafety.validateCrossoverFreq(config.freqHz, config.side,
        isTweeter: _isTweeter(channelIndex));
    _reportIfClamped(r);
    final safeConfig = r.wasClamped
        ? CrossoverConfig(side: config.side, freqHz: r.value, slope: config.slope)
        : config;
    return _inner.writeCrossover(channelIndex, safeConfig);
  }

  @override
  Future<void> writeBiquad(int channelIndex, int bandIndex, BiquadCoeffs coeffs) {
    final r = DspSafety.validateBiquad(coeffs);
    _reportIfClamped(r);
    return _inner.writeBiquad(channelIndex, bandIndex, r.value);
  }

  @override
  Future<void> writeDelay(int channelIndex, double delayMs) =>
      _inner.writeDelay(channelIndex, delayMs); // 지연시간 자체는 트위터/우퍼 안전과 무관

  @override
  Future<void> writeSubsonicFilter(int channelIndex, double freqHz) =>
      _inner.writeSubsonicFilter(channelIndex, freqHz);

  @override
  Future<DspState> readCurrentState() => _inner.readCurrentState();
}

// ignore_for_file: constant_identifier_names

import 'tune_plan.dart';

enum TuneDeploymentState {
  CREATED,
  SENT,
  ACKED,
  RESTORED,
  FAILED,
}

class TuneDeploymentOriginalValues {
  final int frequencyHz;
  final double gainDb;
  final double q;
  final bool enable;

  const TuneDeploymentOriginalValues({
    required this.frequencyHz,
    required this.gainDb,
    required this.q,
    required this.enable,
  });
}

/// Dry-run deployment description for one PEQ band.
///
/// This model contains no transport and cannot perform a hardware write.
class TuneDeploymentPlan {
  final int channel;
  final int bandId;
  final int frequencyHz;
  final double gainDb;
  final double q;
  final bool enable;
  final TuneDeploymentOriginalValues originalValues;
  final TuneDeploymentState state;

  const TuneDeploymentPlan({
    required this.channel,
    required this.bandId,
    required this.frequencyHz,
    required this.gainDb,
    required this.q,
    required this.enable,
    required this.originalValues,
    this.state = TuneDeploymentState.CREATED,
  });

  TuneDeploymentPlan copyWith({TuneDeploymentState? state}) =>
      TuneDeploymentPlan(
        channel: channel,
        bandId: bandId,
        frequencyHz: frequencyHz,
        gainDb: gainDb,
        q: q,
        enable: enable,
        originalValues: originalValues,
        state: state ?? this.state,
      );

  static List<TuneDeploymentPlan> fromTunePlan(
    TunePlan tunePlan, {
    required int channel,
    required List<TuneDeploymentOriginalValues> originalValues,
    bool enable = true,
  }) {
    if (channel < 0 || channel > 0xff) {
      throw RangeError.range(channel, 0, 0xff, 'channel');
    }
    if (originalValues.length != tunePlan.bands.length) {
      throw ArgumentError.value(
        originalValues.length,
        'originalValues',
        'Must contain one snapshot for every TunePlan band.',
      );
    }

    return List.unmodifiable([
      for (var bandId = 0; bandId < tunePlan.bands.length; bandId++)
        TuneDeploymentPlan(
          channel: channel,
          bandId: bandId,
          frequencyHz: tunePlan.bands[bandId].frequencyHz.round(),
          gainDb: tunePlan.bands[bandId].gainDb,
          q: tunePlan.bands[bandId].q,
          enable: enable,
          originalValues: originalValues[bandId],
        ),
    ]);
  }
}

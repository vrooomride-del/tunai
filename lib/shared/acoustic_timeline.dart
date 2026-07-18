import 'package:flutter/material.dart';

/// Stages of the TUNAI consumer sound journey.
enum AcousticTimelineStep {
  factorySound,
  roomScan,
  acousticTune,
  listen,
  savedProfile,
}

enum _StepStatus { pending, active, completed }

/// Compact horizontal timeline showing the consumer's acoustic journey.
/// Pass [currentStep] to mark the step the user is currently at:
/// all earlier steps are shown as completed, all later steps as pending.
class AcousticTimeline extends StatelessWidget {
  final AcousticTimelineStep currentStep;
  final bool ko;

  const AcousticTimeline({
    super.key,
    required this.currentStep,
    required this.ko,
  });

  _StepStatus _statusFor(AcousticTimelineStep step) {
    if (step.index < currentStep.index) return _StepStatus.completed;
    if (step.index == currentStep.index) return _StepStatus.active;
    return _StepStatus.pending;
  }

  String _label(AcousticTimelineStep step) {
    if (ko) {
      return switch (step) {
        AcousticTimelineStep.factorySound => '처음 소리',
        AcousticTimelineStep.roomScan => '공간 분석',
        AcousticTimelineStep.acousticTune => 'Your Sound',
        AcousticTimelineStep.listen => '비교 청취',
        AcousticTimelineStep.savedProfile => '저장됨',
      };
    }
    return switch (step) {
      AcousticTimelineStep.factorySound => 'Factory Sound',
      AcousticTimelineStep.roomScan => 'Space Analysis',
      AcousticTimelineStep.acousticTune => 'Your Sound',
      AcousticTimelineStep.listen => 'Listen',
      AcousticTimelineStep.savedProfile => 'Saved Profile',
    };
  }

  @override
  Widget build(BuildContext context) {
    const steps = AcousticTimelineStep.values;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (int i = 0; i < steps.length; i++) ...[
          Expanded(
            child: _StepItem(
              label: _label(steps[i]),
              status: _statusFor(steps[i]),
            ),
          ),
          if (i < steps.length - 1)
            _Connector(completed: steps[i].index < currentStep.index),
        ],
      ],
    );
  }
}

class _StepItem extends StatelessWidget {
  final String label;
  final _StepStatus status;
  const _StepItem({required this.label, required this.status});

  Color get _dotFill => switch (status) {
        _StepStatus.completed => const Color(0xFF69F0AE),
        _StepStatus.active => Colors.white,
        _StepStatus.pending => Colors.transparent,
      };

  Color get _dotBorder => switch (status) {
        _StepStatus.completed => const Color(0xFF69F0AE),
        _StepStatus.active => Colors.white,
        _StepStatus.pending => Colors.white24,
      };

  Color get _labelColor => switch (status) {
        _StepStatus.completed => Colors.white.withValues(alpha: 0.5),
        _StepStatus.active => Colors.white,
        _StepStatus.pending => Colors.white.withValues(alpha: 0.2),
      };

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: _dotFill,
            border: Border.all(color: _dotBorder, width: 1.2),
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          label,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: _labelColor,
            fontSize: 9,
            height: 1.3,
            fontWeight: status == _StepStatus.active ? FontWeight.w500 : FontWeight.w300,
          ),
        ),
      ],
    );
  }
}

class _Connector extends StatelessWidget {
  final bool completed;
  const _Connector({required this.completed});

  @override
  Widget build(BuildContext context) => Padding(
        // offset to vertically center the line on the 8px dot
        padding: const EdgeInsets.only(top: 3.5),
        child: Container(
          width: 8,
          height: 1,
          color: completed
              ? const Color(0xFF69F0AE).withValues(alpha: 0.4)
              : Colors.white.withValues(alpha: 0.1),
        ),
      );
}

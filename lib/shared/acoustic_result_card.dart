import 'package:flutter/material.dart';

/// 공간 음향 분석 결과를 사용자가 이해할 수 있는 언어로 설명하는 카드.
/// Cause → Correction → Effect 구조.
class AcousticResultCard extends StatelessWidget {
  final String title;
  final String frequencyLabel;
  final String cause;
  final String correction;
  final String effect;
  final bool ko;

  const AcousticResultCard({
    super.key,
    required this.title,
    required this.frequencyLabel,
    required this.cause,
    required this.correction,
    required this.effect,
    required this.ko,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
      decoration: BoxDecoration(
        color: const Color(0xFF111111),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 타이틀 + 주파수
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                title,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w400,
                  letterSpacing: 0.3,
                ),
              ),
              const SizedBox(width: 10),
              Text(
                frequencyLabel,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.35),
                  fontSize: 11,
                  letterSpacing: 0.5,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          _Row(label: ko ? '원인' : 'Cause', value: cause),
          const SizedBox(height: 8),
          _Row(label: ko ? '조정' : 'Correction', value: correction),
          const SizedBox(height: 8),
          _Row(label: ko ? '효과' : 'Effect', value: effect),
        ],
      ),
    );
  }
}

class _Row extends StatelessWidget {
  final String label;
  final String value;
  const _Row({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 64,
          child: Text(
            label,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.28),
              fontSize: 10,
              letterSpacing: 1.2,
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.65),
              fontSize: 12,
              height: 1.5,
            ),
          ),
        ),
      ],
    );
  }
}

/// Sound Score breakdown row
class ScoreBreakdownRow extends StatelessWidget {
  final String label;
  final String value;
  final bool ko;
  const ScoreBreakdownRow({
    super.key,
    required this.label,
    required this.value,
    required this.ko,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(children: [
        Expanded(
          child: Text(
            label,
            style: TextStyle(color: Colors.white.withValues(alpha: 0.45), fontSize: 12),
          ),
        ),
        Text(
          value,
          style: const TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w400),
        ),
      ]),
    );
  }
}

/// Before/After 상태 설명 카드 (TUNE 완료 화면 및 Before/After 화면용)
class SoundStateCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final bool selected;

  const SoundStateCard({
    super.key,
    required this.title,
    required this.subtitle,
    this.selected = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: selected ? Colors.white.withValues(alpha: 0.04) : Colors.transparent,
        border: Border.all(
          color: selected ? Colors.white24 : Colors.white.withValues(alpha: 0.08),
        ),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              color: selected ? Colors.white : Colors.white.withValues(alpha: 0.5),
              fontSize: 13,
              fontWeight: FontWeight.w400,
              letterSpacing: 0.3,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.35),
              fontSize: 11,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}

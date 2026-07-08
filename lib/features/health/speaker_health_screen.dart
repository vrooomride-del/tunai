import 'package:flutter/material.dart';
import '../../core/health_status.dart';

class SpeakerHealthScreen extends StatelessWidget {
  const SpeakerHealthScreen({super.key});

  static const _cards = [
    HealthCard(
      title: 'Speaker Protection',
      titleKo: '스피커 보호',
      value: 'On',
      valueKo: '켜짐',
      subtitle: 'Your speaker is protected while Sound Profiles are applied.',
      subtitleKo: '사운드 프로파일 적용 중에도 스피커가 보호됩니다.',
      icon: Icons.shield_outlined,
    ),
    HealthCard(
      title: 'Volume Safety',
      titleKo: '볼륨 안전',
      value: 'Safe',
      valueKo: '안전',
      subtitle: 'Current volume is within a safe listening range.',
      subtitleKo: '현재 볼륨은 안전한 청취 범위 안에 있습니다.',
      icon: Icons.volume_down_outlined,
    ),
    HealthCard(
      title: 'Sound Profile Safety',
      titleKo: '사운드 프로파일 안전성',
      value: 'Verified',
      valueKo: '검증됨',
      subtitle: 'The current Sound Profile has been checked before playback.',
      subtitleKo: '현재 사운드 프로파일은 재생 전 안전성이 확인되었습니다.',
      icon: Icons.verified_outlined,
    ),
    HealthCard(
      title: 'System Temperature',
      titleKo: '시스템 온도',
      value: 'Normal',
      valueKo: '정상',
      subtitle: 'No unusual system heat detected.',
      subtitleKo: '비정상적인 발열이 감지되지 않았습니다.',
      icon: Icons.thermostat_outlined,
    ),
  ];

  bool _isKo(BuildContext ctx) =>
      Localizations.localeOf(ctx).languageCode == 'ko';

  @override
  Widget build(BuildContext context) {
    final ko = _isKo(context);
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0A0A0A),
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white70),
        title: Text(
          ko ? '시스템 상태' : 'System Health',
          style: const TextStyle(color: Colors.white, fontSize: 13, letterSpacing: 2),
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 40),
          children: [
            // Subtitle
            Text(
              ko
                  ? 'TUNAI는 스피커가 안전한 청취 범위 안에서 작동하도록 관리합니다.'
                  : 'TUNAI keeps your speaker operating within a safe listening range.',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.4),
                fontSize: 12,
                height: 1.6,
              ),
            ),
            const SizedBox(height: 20),

            // Status summary card
            _StatusSummaryCard(ko: ko),
            const SizedBox(height: 20),

            // Section header
            Text(
              ko ? '상세 상태' : 'Details',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.35),
                fontSize: 11,
                letterSpacing: 1.5,
              ),
            ),
            const SizedBox(height: 12),

            // Health cards
            for (final card in _cards) ...[
              _HealthDetailCard(card: card, ko: ko),
              const SizedBox(height: 10),
            ],

            const SizedBox(height: 20),

            // Warning state examples section
            Text(
              ko ? '상태 안내' : 'Status Guide',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.35),
                fontSize: 11,
                letterSpacing: 1.5,
              ),
            ),
            const SizedBox(height: 12),
            _WarningExampleCard(
              level: HealthLevel.attention,
              title: ko ? '청취 볼륨이 높은 편입니다' : 'High listening level',
              subtitle: ko
                  ? 'TUNAI가 안전한 범위 안에서 재생되도록 관리하고 있습니다.'
                  : 'TUNAI is keeping playback within a safe range.',
            ),
            const SizedBox(height: 10),
            _WarningExampleCard(
              level: HealthLevel.protected,
              title: ko ? '보호 재생 중' : 'Playback protected',
              subtitle: ko
                  ? 'TUNAI가 스피커 시스템 보호를 위해 출력을 조정했습니다.'
                  : 'TUNAI adjusted output to protect the speaker system.',
            ),
          ],
        ),
      ),
    );
  }
}

// ── Status Summary Card ────────────────────────────────────────────────────

class _StatusSummaryCard extends StatelessWidget {
  final bool ko;
  const _StatusSummaryCard({required this.ko});

  @override
  Widget build(BuildContext context) {
    const level = HealthLevel.normal;
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
      decoration: BoxDecoration(
        color: level.color.withValues(alpha: 0.05),
        border: Border.all(color: level.color.withValues(alpha: 0.3)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(children: [
        Icon(Icons.check_circle_outline, color: level.color, size: 24),
        const SizedBox(width: 14),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(
              ko ? '시스템 상태' : 'System Status',
              style: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontSize: 11, letterSpacing: 1.2),
            ),
            const SizedBox(height: 4),
            Text(
              level.label(ko),
              style: TextStyle(color: level.color, fontSize: 18, fontWeight: FontWeight.w300, letterSpacing: 0.5),
            ),
          ]),
        ),
      ]),
    );
  }
}

// ── Health Detail Card ────────────────────────────────────────────────────

class _HealthDetailCard extends StatelessWidget {
  final HealthCard card;
  final bool ko;
  const _HealthDetailCard({required this.card, required this.ko});

  @override
  Widget build(BuildContext context) {
    final color = card.level.color;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: const Color(0xFF111111),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(card.icon, color: color.withValues(alpha: 0.7), size: 18),
        const SizedBox(width: 14),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(
                child: Text(
                  ko ? card.titleKo : card.title,
                  style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w300),
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  border: Border.all(color: color.withValues(alpha: 0.35)),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  ko ? card.valueKo : card.value,
                  style: TextStyle(color: color, fontSize: 10, letterSpacing: 1),
                ),
              ),
            ]),
            const SizedBox(height: 6),
            Text(
              ko ? card.subtitleKo : card.subtitle,
              style: TextStyle(color: Colors.white.withValues(alpha: 0.4), fontSize: 11, height: 1.5),
            ),
          ]),
        ),
      ]),
    );
  }
}

// ── Warning Example Card ──────────────────────────────────────────────────

class _WarningExampleCard extends StatelessWidget {
  final HealthLevel level;
  final String title;
  final String subtitle;
  const _WarningExampleCard({
    required this.level,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    final color = level.color;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 13, 16, 13),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.04),
        border: Border.all(color: color.withValues(alpha: 0.25)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(
          level == HealthLevel.attention ? Icons.info_outline : Icons.warning_amber_outlined,
          color: color,
          size: 16,
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w400)),
            const SizedBox(height: 4),
            Text(subtitle, style: TextStyle(color: Colors.white.withValues(alpha: 0.45), fontSize: 11, height: 1.5)),
          ]),
        ),
      ]),
    );
  }
}

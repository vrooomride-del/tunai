import 'package:flutter/material.dart';

/// UI-only health status model. Does not affect protection logic.
enum HealthLevel { normal, attention, protected }

extension HealthLevelLabel on HealthLevel {
  String label(bool ko) => switch (this) {
        HealthLevel.normal => ko ? '정상' : 'Normal',
        HealthLevel.attention => ko ? '주의' : 'Attention',
        HealthLevel.protected => ko ? '보호 중' : 'Protected',
      };

  Color get color {
    switch (this) {
      case HealthLevel.normal:
        return const Color(0xFF69F0AE);
      case HealthLevel.attention:
        return const Color(0xFFFFB74D);
      case HealthLevel.protected:
        return const Color(0xFFEF5350);
    }
  }
}

class HealthCard {
  final String title;
  final String titleKo;
  final String value;
  final String valueKo;
  final String subtitle;
  final String subtitleKo;
  final HealthLevel level;
  final IconData icon;

  const HealthCard({
    required this.title,
    required this.titleKo,
    required this.value,
    required this.valueKo,
    required this.subtitle,
    required this.subtitleKo,
    this.level = HealthLevel.normal,
    required this.icon,
  });
}

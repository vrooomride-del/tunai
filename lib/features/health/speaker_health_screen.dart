import 'package:flutter/material.dart';
import '../../shared/widgets.dart';

/// Speaker Health — DSP Load / Amplifier / Tweeter·Woofer / Limiter 상태 표시.
///
/// 실기기에서 이 값들을 읽어올 방법이 아직 없다(BLE `fff1` NOTIFY 특성이 코드에
/// 정의만 돼 있고 실제 subscribe/parse 경로가 없음 — CONNECT 2단계에서 Firmware
/// 버전을 생략한 것과 같은 이유). 가짜 데이터를 보여주지 않기 위해 전부 "정보 없음"
/// 으로 표시하는 뼈대 화면만 제공한다. 실제 텔레메트리 프로토콜이 확인되면 그때
/// 값을 채울 것.
class SpeakerHealthScreen extends StatelessWidget {
  const SpeakerHealthScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0A0A0A),
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white70),
        title: const Text('SPEAKER HEALTH', style: TextStyle(color: Colors.white, fontSize: 13, letterSpacing: 2)),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                border: Border.all(color: Colors.amber.withValues(alpha: 0.4)),
                borderRadius: BorderRadius.circular(6),
                color: Colors.amber.withValues(alpha: 0.04),
              ),
              child: const Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Icon(Icons.construction, color: Colors.amber, size: 14),
                SizedBox(width: 8),
                Expanded(child: Text(
                  '하드웨어 지원 준비중 — 아래 값들은 아직 실기기에서 읽어올 수 없어\n'
                  '전부 "정보 없음"으로 표시됩니다.',
                  style: TextStyle(color: Colors.amber, fontSize: 11, height: 1.5),
                )),
              ]),
            ),
            const SizedBox(height: 20),
            const _HealthRow(label: 'DSP Load', icon: Icons.memory),
            const _HealthRow(label: 'Amplifier', icon: Icons.bolt_outlined),
            const _HealthRow(label: 'Tweeter', icon: Icons.speaker_outlined),
            const _HealthRow(label: 'Woofer', icon: Icons.speaker_outlined),
            const _HealthRow(label: 'Limiter', icon: Icons.shield_outlined),
          ],
        ),
      ),
    );
  }
}

class _HealthRow extends StatelessWidget {
  final String label;
  final IconData icon;
  const _HealthRow({required this.label, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: SectionCard(
        child: Row(children: [
          Icon(icon, color: Colors.white24, size: 18),
          const SizedBox(width: 12),
          Expanded(child: Text(label, style: const TextStyle(color: Colors.white70, fontSize: 13))),
          const Text('정보 없음', style: TextStyle(color: Colors.white24, fontSize: 12, letterSpacing: 1)),
        ]),
      ),
    );
  }
}

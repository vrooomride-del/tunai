import 'package:flutter/material.dart';
import '../../shared/widgets.dart';

/// FINE TUNE 탭 — 취향 프리셋(Warm/Neutral/Studio/Vocal/Movie/Bright)은 Task 5에서 완성된다.
class FineTuneScreen extends StatelessWidget {
  const FineTuneScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: Color(0xFF0A0A0A),
      body: SafeArea(
        child: Column(
          children: [
            TunaiTopBar(subtitle: 'FINE TUNE'),
            Expanded(
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: 24),
                child: SectionCard(
                  child: Column(children: [
                    Icon(Icons.tune, color: Colors.white24, size: 32),
                    SizedBox(height: 10),
                    Text('취향 프리셋 준비 중', style: TextStyle(color: Colors.white54, fontSize: 13)),
                  ]),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

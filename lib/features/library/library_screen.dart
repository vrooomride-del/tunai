import 'package:flutter/material.dart';
import '../../shared/widgets.dart';

/// LIBRARY 탭 — Factory/My Presets/Community Best. Task 7에서 완성된다.
class LibraryScreen extends StatelessWidget {
  const LibraryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: Color(0xFF0A0A0A),
      body: SafeArea(
        child: Column(
          children: [
            TunaiTopBar(subtitle: 'LIBRARY'),
            Expanded(
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: 24),
                child: SectionCard(
                  child: Column(children: [
                    Icon(Icons.library_music_outlined, color: Colors.white24, size: 32),
                    SizedBox(height: 10),
                    Text('프리셋 라이브러리 준비 중', style: TextStyle(color: Colors.white54, fontSize: 13)),
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

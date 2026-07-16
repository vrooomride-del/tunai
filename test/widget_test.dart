import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tunai/main.dart' show RootScreen;

void main() {
  testWidgets('Consumer navigation preserves CONNECT ROOM TUNE LISTEN MORE',
      (tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(home: RootScreen()),
      ),
    );

    for (final label in ['CONNECT', 'ROOM', 'TUNE', 'LISTEN', 'MORE']) {
      expect(find.text(label), findsOneWidget);
    }
    expect(find.byIcon(Icons.bluetooth), findsOneWidget);
  });
}

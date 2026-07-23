import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Guards the product boundary: TUNAI PRO AUTHORS factory voicings; the
/// Consumer app only READS them. Because the value constructor is private,
/// Consumer feature code physically cannot author a FactorySoundProfile — this
/// test additionally asserts the sanctioned read paths are the only ones used,
/// so a future contributor can't quietly re-introduce authoring by adding a
/// public constructor and calling it.
void main() {
  test('no Consumer feature code AUTHORS a factory profile — only the '
      'registry / fromJson read paths are used', () {
    final featureDir = Directory('lib/features');
    expect(featureDir.existsSync(), isTrue);

    final offenders = <String>[];
    for (final entity in featureDir.listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final text = entity.readAsStringSync();
      if (!text.contains('FactorySoundProfile')) continue;

      // Every reference must be one of the read-only paths:
      //  - FactorySoundProfileRegistry.*   (Pro-authored catalog read)
      //  - FactorySoundProfile.fromJson     (deserialize a delivered profile)
      //  - a type annotation / field type   (FactorySoundProfile? factory)
      // What must NOT appear is a value-constructor call: `FactorySoundProfile(`
      // with arguments (authoring). The constructor is private now, so this
      // also can't compile — the test documents and future-proofs the rule.
      final authoringCall = RegExp(r'FactorySoundProfile\s*\(');
      if (authoringCall.hasMatch(text)) {
        offenders.add(entity.path);
      }
    }

    expect(offenders, isEmpty,
        reason: 'Consumer feature files must not author a FactorySoundProfile '
            '(use FactorySoundProfileRegistry / fromJson): $offenders');
  });

  test('the only factory-profile construction site in lib/ is the Pro-authored '
      'catalog (factory_sound_profile.dart itself)', () {
    final libDir = Directory('lib');
    final authoringFiles = <String>[];
    for (final entity in libDir.listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final text = entity.readAsStringSync();
      // The private constructor `FactorySoundProfile._(` may only appear in the
      // model file; nothing else in the app can call it.
      if (RegExp(r'FactorySoundProfile\._\(').hasMatch(text)) {
        authoringFiles.add(entity.path);
      }
    }
    expect(authoringFiles, ['lib/core/factory_sound_profile.dart']);
  });
}

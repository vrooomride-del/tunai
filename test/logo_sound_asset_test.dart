import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:tunai/features/splash/brand_identity.dart';

/// Reads the `fmt `/`data` chunks of a canonical PCM WAV file and returns the
/// duration in seconds. Minimal on-purpose — this is test-only verification,
/// not a production audio decoder.
double _wavDurationSeconds(File file) {
  final bytes = file.readAsBytesSync();
  final data = ByteData.sublistView(Uint8List.fromList(bytes));
  int byteRate = 0;
  int dataSize = 0;
  var offset = 12; // past "RIFF" + size + "WAVE"
  while (offset + 8 <= bytes.length) {
    final chunkId = String.fromCharCodes(bytes.sublist(offset, offset + 4));
    final chunkSize = data.getUint32(offset + 4, Endian.little);
    final chunkStart = offset + 8;
    if (chunkId == 'fmt ') {
      byteRate = data.getUint32(chunkStart + 8, Endian.little);
    } else if (chunkId == 'data') {
      dataSize = chunkSize;
    }
    offset = chunkStart + chunkSize + (chunkSize.isOdd ? 1 : 0);
  }
  expect(byteRate, greaterThan(0), reason: 'fmt chunk not found/parsed');
  expect(dataSize, greaterThan(0), reason: 'data chunk not found/parsed');
  return dataSize / byteRate;
}

void main() {
  test('TUNAI logo sound asset exists and matches the brand duration target',
      () {
    final path = BrandIdentity.tunai.logoSoundAssetPath;
    final file = File(path);
    expect(file.existsSync(), isTrue,
        reason: '$path must exist for the Splash logo sound to play.');
    expect(file.lengthSync(), greaterThan(0));

    final header = file.readAsBytesSync().sublist(0, 4);
    expect(String.fromCharCodes(header), 'RIFF');

    final duration = _wavDurationSeconds(file);
    // Brand guideline target is ~2s (current asset); allow modest tolerance
    // for a future remaster without silently accepting a wildly different
    // length.
    expect(duration, inInclusiveRange(0.5, 2.5),
        reason: 'Logo sound duration ($duration s) is far outside the '
            '~2s brand target — verify this is the intended asset.');
  });

  test('assets/audio/ is registered in pubspec.yaml', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    expect(pubspec, contains('assets/audio/'));
  });
}

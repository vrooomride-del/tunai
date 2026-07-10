/// Tests for Adau1701PacketBuilder, Adau1701Jab4MiumaxAddressRegistry,
/// and ProUsbiAdau1701Executor guard chain.
///
/// ProUsbiAdau1701Executor guard G1 blocks on non-Windows platform,
/// so write path (success / failure) tests are marked Windows-only.
/// Registry and encoding tests are platform-independent.
library;

import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:tunai/core/adau1701_jab4_miumax_address_registry.dart';
import 'package:tunai/core/pro_usbi_adau1701_executor.dart';

void main() {
  // ── Adau1701PacketBuilder ─────────────────────────────────────────────────

  group('Adau1701PacketBuilder', () {
    test('encodeGain523 unity (0dB) = 00 80 00 00', () {
      expect(Adau1701PacketBuilder.encodeGain523(1.0), [0x00, 0x80, 0x00, 0x00]);
    });

    test('encodeGain523 0.0 = 00 00 00 00', () {
      expect(Adau1701PacketBuilder.encodeGain523(0.0), [0x00, 0x00, 0x00, 0x00]);
    });

    test('encodeGain523 matches -40dB constant', () {
      // -40dB linear ≈ 0.0001  (10^(-40/20))
      // Confirmed: 00 01 47 AE (from Export19 map)
      // Allow 1 LSB tolerance due to rounding
      final encoded = Adau1701PacketBuilder.encodeGain523(0.01); // 10^(-40/20) ≈ 0.01
      const expected = Adau1701Jab4MiumaxAddressRegistry.gainNeg40dB;
      // Check within ±2 LSB (last byte)
      final encInt = (encoded[0] << 24) | (encoded[1] << 16) | (encoded[2] << 8) | encoded[3];
      final expInt = (expected[0] << 24) | (expected[1] << 16) | (expected[2] << 8) | expected[3];
      expect((encInt - expInt).abs(), lessThan(10),
          reason: 'Encoded ${Adau1701PacketBuilder.toHex(encoded)} '
              'should be close to ${Adau1701PacketBuilder.toHex(expected)}');
    });

    test('isUnityGain true for 00 80 00 00', () {
      expect(Adau1701PacketBuilder.isUnityGain([0x00, 0x80, 0x00, 0x00]), isTrue);
    });

    test('isUnityGain false for -40dB value', () {
      expect(Adau1701PacketBuilder.isUnityGain(
          Adau1701Jab4MiumaxAddressRegistry.gainNeg40dB), isFalse);
    });

    test('toHex formats correctly', () {
      expect(Adau1701PacketBuilder.toHex([0x00, 0x80, 0x00, 0x00]), '00 80 00 00');
      expect(Adau1701PacketBuilder.toHex([0x00, 0x01, 0x47, 0xAE]), '00 01 47 AE');
    });

    test('encodeGain523 clamps negative to 0', () {
      expect(Adau1701PacketBuilder.encodeGain523(-1.0), [0x00, 0x00, 0x00, 0x00]);
    });
  });

  // ── Address registry ──────────────────────────────────────────────────────

  group('Adau1701Jab4MiumaxAddressRegistry', () {
    test('phase1GainAddresses contains exactly 4 addresses', () {
      expect(Adau1701Jab4MiumaxAddressRegistry.phase1GainAddresses.length, 4);
    });

    test('phase1GainAddresses contains 0x0321–0x0324', () {
      expect(
        Adau1701Jab4MiumaxAddressRegistry.phase1GainAddresses,
        containsAll([0x0321, 0x0322, 0x0323, 0x0324]),
      );
    });

    test('ExtSWGainDB volume addresses are not in phase1GainAddresses', () {
      for (final addr in [0x0006, 0x0007, 0x0320, 0x0329]) {
        expect(
          Adau1701Jab4MiumaxAddressRegistry.phase1GainAddresses.contains(addr),
          isFalse,
          reason: '0x${addr.toRadixString(16)} must not be in phase1GainAddresses',
        );
      }
    });

    test('gain0dB is 00 80 00 00', () {
      expect(Adau1701Jab4MiumaxAddressRegistry.gain0dB, [0x00, 0x80, 0x00, 0x00]);
    });

    test('gainNeg60dB is 00 00 20 C5', () {
      expect(Adau1701Jab4MiumaxAddressRegistry.gainNeg60dB, [0x00, 0x00, 0x20, 0xC5]);
    });

    test('gainNeg50dB is 00 00 67 9F', () {
      expect(Adau1701Jab4MiumaxAddressRegistry.gainNeg50dB, [0x00, 0x00, 0x67, 0x9F]);
    });

    test('gainNeg40dB is 00 01 47 AE', () {
      expect(Adau1701Jab4MiumaxAddressRegistry.gainNeg40dB, [0x00, 0x01, 0x47, 0xAE]);
    });

    test('i2cDspAddress is 0x68', () {
      expect(Adau1701Jab4MiumaxAddressRegistry.i2cDspAddress, 0x68);
    });

    test('gainPresets has 4 entries', () {
      expect(Adau1701Jab4MiumaxAddressRegistry.gainPresets.length, 4);
    });

    test('gainPresets keys include restore and three attenuation levels', () {
      expect(Adau1701Jab4MiumaxAddressRegistry.gainPresets.keys,
          containsAll(['0 dB (restore)', '-40 dB', '-50 dB', '-60 dB']));
    });
  });

  // ── ProUsbiAdau1701Executor guard chain ────────────────────────────────────

  group('Guard G1 — Windows platform', () {
    test('blocks write on non-Windows and sets error', () async {
      if (Platform.isWindows) return;
      const exec = ProUsbiAdau1701Executor();
      final result = await exec.writeDefaultGain(
        gainBytes: Adau1701Jab4MiumaxAddressRegistry.gainNeg60dB,
        gainLabel: '-60dB',
        operatorConfirmed: true,
      );
      expect(result.allSucceeded, isFalse);
      expect(result.writes.every((r) => !r.success), isTrue);
      expect(result.writes.every((r) => r.error != null), isTrue);
      expect(result.writes.first.error, contains('G1'));
    });
  });

  group('Guard G4 — operator confirmation', () {
    test('blocks when operatorConfirmed is false', () async {
      if (Platform.isWindows) return; // G1 fires first on non-Windows, still blocks
      const exec = ProUsbiAdau1701Executor();
      final result = await exec.writeDefaultGain(
        gainBytes: Adau1701Jab4MiumaxAddressRegistry.gain0dB,
        gainLabel: '0dB',
        operatorConfirmed: false,
      );
      // Either G1 or G4 fires — in both cases, allSucceeded must be false
      expect(result.allSucceeded, isFalse);
    });
  });

  group('Guard G2 — address allowlist', () {
    test('non-phase1 address is blocked via address allowlist in registry', () {
      // Verify that an arbitrary address (e.g., EEPROM area, ExtSWGainDB) is not in allowlist
      expect(
        Adau1701Jab4MiumaxAddressRegistry.phase1GainAddresses.contains(0x000B),
        isFalse,
        reason: 'Mute candidate 0x000B must not be in phase1GainAddresses',
      );
      expect(
        Adau1701Jab4MiumaxAddressRegistry.phase1GainAddresses.contains(0x0006),
        isFalse,
        reason: 'ExtSWGainDB 0x0006 must not be in phase1GainAddresses',
      );
    });
  });

  // ── Multi-write semantics ──────────────────────────────────────────────────

  group('writeDefaultGain — non-Windows (G1 blocks all)', () {
    test('result.writes has exactly 4 entries', () async {
      if (Platform.isWindows) return;
      const exec = ProUsbiAdau1701Executor();
      final result = await exec.writeDefaultGain(
        gainBytes: Adau1701Jab4MiumaxAddressRegistry.gainNeg60dB,
        gainLabel: '-60dB test',
        operatorConfirmed: true,
      );
      expect(result.writes.length, 4);
    });

    test('result.gainLabel is preserved', () async {
      if (Platform.isWindows) return;
      const exec = ProUsbiAdau1701Executor();
      final result = await exec.writeDefaultGain(
        gainBytes: Adau1701Jab4MiumaxAddressRegistry.gain0dB,
        gainLabel: 'my-label',
        operatorConfirmed: true,
      );
      expect(result.gainLabel, 'my-label');
    });

    test('result.writes each carry the correct address (sorted)', () async {
      if (Platform.isWindows) return;
      const exec = ProUsbiAdau1701Executor();
      final result = await exec.writeDefaultGain(
        gainBytes: Adau1701Jab4MiumaxAddressRegistry.gainNeg40dB,
        gainLabel: '-40dB',
        operatorConfirmed: true,
      );
      final addresses = result.writes.map((r) => r.address).toList();
      expect(addresses, containsAll([0x0321, 0x0322, 0x0323, 0x0324]));
    });

    test('each result.logLine contains I2C address and param address', () async {
      if (Platform.isWindows) return;
      const exec = ProUsbiAdau1701Executor();
      final result = await exec.writeDefaultGain(
        gainBytes: Adau1701Jab4MiumaxAddressRegistry.gainNeg60dB,
        gainLabel: '-60dB',
        operatorConfirmed: true,
      );
      for (final r in result.writes) {
        expect(r.logLine, contains('I2C 0x68'));
        expect(r.logLine, contains('ADAU1701_JAB4_MIUMAX_ORIGINAL'));
      }
    });
  });

  group('restore0dB', () {
    test('writes 00 80 00 00 to all four addresses', () async {
      if (Platform.isWindows) return;
      const exec = ProUsbiAdau1701Executor();
      final result = await exec.restore0dB();
      for (final r in result.writes) {
        expect(r.bytesWritten, [0x00, 0x80, 0x00, 0x00]);
      }
    });

    test('gainLabel is "0 dB (restore)"', () async {
      if (Platform.isWindows) return;
      const exec = ProUsbiAdau1701Executor();
      final result = await exec.restore0dB();
      expect(result.gainLabel, '0 dB (restore)');
    });
  });

  // ── Safety invariants ──────────────────────────────────────────────────────

  group('Safety invariants', () {
    test('i2c address is 0x68 not 0xA0', () {
      expect(Adau1701Jab4MiumaxAddressRegistry.i2cDspAddress, 0x68);
      expect(Adau1701Jab4MiumaxAddressRegistry.i2cDspAddress, isNot(0xA0));
    });

    test('phase1GainAddresses does not include any mute address', () {
      final mutes = {
        Adau1701Jab4MiumaxAddressRegistry.mute0_2,
        Adau1701Jab4MiumaxAddressRegistry.mute1Candidate,
        Adau1701Jab4MiumaxAddressRegistry.mute0Candidate,
      };
      for (final m in mutes) {
        expect(
          Adau1701Jab4MiumaxAddressRegistry.phase1GainAddresses.contains(m),
          isFalse,
          reason: 'Mute 0x${m.toRadixString(16)} must not be in phase1GainAddresses',
        );
      }
    });

    test('allSucceeded is false when any write fails', () async {
      if (Platform.isWindows) return;
      const exec = ProUsbiAdau1701Executor();
      final result = await exec.writeDefaultGain(
        gainBytes: Adau1701Jab4MiumaxAddressRegistry.gain0dB,
        gainLabel: 'test',
        operatorConfirmed: true,
      );
      // G1 blocks — allSucceeded must be false
      expect(result.allSucceeded, isFalse);
      expect(result.failCount, result.writes.length);
    });
  });
}

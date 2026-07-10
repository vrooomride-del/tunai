/// ADAU1701 / JAB4 Original DSP Test Tab.
///
/// Engineering screen — confirms TUNAI app → USBi WinUSB → ADAU1701 I2C
/// parameter write works end-to-end.
///
/// Phase 1 test only:
///   Four Default Gain addresses (0x0321–0x0324).
///   Buttons: -60dB / -50dB / -40dB / Restore 0dB.
///   Success criterion: Bluetooth music playing, output level changes on button press.
///
/// EEPROM 0xA0 write is NEVER exposed here.
/// Selfboot write is NOT implemented here.
library;

import 'package:flutter/material.dart';
import '../../../core/adau1701_jab4_miumax_address_registry.dart';
import '../../../core/pro_usbi_adau1701_executor.dart';

class Adau1701TestTab extends StatefulWidget {
  const Adau1701TestTab({super.key});

  @override
  State<Adau1701TestTab> createState() => _Adau1701TestTabState();
}

class _Adau1701TestTabState extends State<Adau1701TestTab> {
  final _executor = const ProUsbiAdau1701Executor();

  bool _operatorConfirmed = false;
  bool _busy = false;
  Adau1701MultiWriteResult? _lastResult;
  final List<String> _log = []; // most recent first, max 200

  // ── Gain buttons ─────────────────────────────────────────────────────────────

  static const _buttons = [
    (label: 'Set  −60 dB', key: '-60dB',  bytes: Adau1701Jab4MiumaxAddressRegistry.gainNeg60dB),
    (label: 'Set  −50 dB', key: '-50dB',  bytes: Adau1701Jab4MiumaxAddressRegistry.gainNeg50dB),
    (label: 'Set  −40 dB', key: '-40dB',  bytes: Adau1701Jab4MiumaxAddressRegistry.gainNeg40dB),
    (label: 'Restore  0 dB', key: '0dB',  bytes: Adau1701Jab4MiumaxAddressRegistry.gain0dB),
  ];

  bool get _canWrite => _operatorConfirmed && !_busy;

  Future<void> _writeGain(List<int> bytes, String label) async {
    setState(() => _busy = true);
    final result = await _executor.writeDefaultGain(
      gainBytes: bytes,
      gainLabel: label,
      operatorConfirmed: _operatorConfirmed,
    );
    setState(() {
      _busy = false;
      _lastResult = result;
      for (final r in result.writes) {
        _log.insert(0, r.logLine);
      }
      while (_log.length > 200) { _log.removeLast(); }
    });
  }

  Future<void> _restore() async {
    setState(() => _busy = true);
    final result = await _executor.restore0dB(operatorConfirmed: _operatorConfirmed);
    setState(() {
      _busy = false;
      _lastResult = result;
      for (final r in result.writes) {
        _log.insert(0, r.logLine);
      }
      while (_log.length > 200) { _log.removeLast(); }
    });
  }

  // ── Build ─────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 60),
      children: [
        // ── Engineering warning ────────────────────────────────────────────────
        const _WarningBanner(
          'Engineering test only. Phase 1: Default Gain addresses.\n'
          'EEPROM 0xA0 write is disabled. Selfboot not implemented.',
        ),
        const SizedBox(height: 20),

        // ── Connection info ────────────────────────────────────────────────────
        const _SectionHeader('Device / Transport'),
        const _InfoTable(rows: [
          ('DSP profile',   'ADAU1701 / JAB4 – Miumax Original'),
          ('Transport',     'USBi → WinUSB → I2C'),
          ('VID / PID',     '0x0456 / 0x7031'),
          ('DSP I2C',       '0x68'),
          ('EEPROM I2C',    '0xA0  ← WRITE DISABLED'),
          ('Gain format',   '5.23 fixed-point, 4-byte BE'),
          ('Profile',       'ADAU1701 / JAB4 – Miumax Original'),
        ]),
        const SizedBox(height: 24),

        // ── Phase 1 test addresses ─────────────────────────────────────────────
        const _SectionHeader('Phase 1 Test Addresses'),
        const SizedBox(height: 6),
        const _AddressTable(entries: [
          ('0x0321', 'Default Gain.Gain3 ch A', 'Gain1940AlgNS9',  true),
          ('0x0322', 'Default Gain.Gain3 ch B', 'Gain1940AlgNS10', true),
          ('0x0323', 'Default Gain.Gain1 ch B', 'Gain1940AlgNS2',  true),
          ('0x0324', 'Default Gain.Gain1 ch A', 'Gain1940AlgNS1',  true),
        ]),
        const SizedBox(height: 6),
        const Text(
          'All four addresses are written together on each button press.',
          style: TextStyle(color: Colors.white24, fontSize: 10, height: 1.5),
        ),
        const SizedBox(height: 24),

        // ── Operator confirmation ──────────────────────────────────────────────
        const _SectionHeader('Operator Confirmation'),
        const SizedBox(height: 6),
        _ConfirmCheckbox(
          value: _operatorConfirmed,
          onChanged: (v) => setState(() => _operatorConfirmed = v ?? false),
          label: 'I confirm Bluetooth music is playing. Ready to test output level change.',
        ),
        const SizedBox(height: 20),

        // ── Gain buttons ───────────────────────────────────────────────────────
        const _SectionHeader('Gain Test Buttons'),
        const SizedBox(height: 4),
        const Text(
          'Write the same gain value to all four addresses simultaneously.',
          style: TextStyle(color: Colors.white24, fontSize: 10, height: 1.5),
        ),
        const SizedBox(height: 14),

        ..._buttons.map((btn) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _GainButton(
                label: btn.label,
                bytes: btn.bytes,
                isRestore: btn.key == '0dB',
                enabled: _canWrite,
                busy: _busy,
                onTap: btn.key == '0dB'
                    ? _restore
                    : () => _writeGain(btn.bytes, btn.label.trim()),
              ),
            )),

        const SizedBox(height: 24),

        // ── Last result ────────────────────────────────────────────────────────
        if (_lastResult != null) ...[
          const _SectionHeader('Last Write Result'),
          const SizedBox(height: 6),
          _ResultCard(result: _lastResult!),
          const SizedBox(height: 24),
        ],

        // ── Write log ──────────────────────────────────────────────────────────
        const _SectionHeader('Write Log'),
        const SizedBox(height: 6),
        if (_log.isEmpty)
          const Text(
            'No writes yet.',
            style: TextStyle(color: Colors.white24, fontSize: 11),
          )
        else
          ..._log.take(20).map((line) => Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(
                  line,
                  style: const TextStyle(
                    color: Colors.white38,
                    fontSize: 10,
                    fontFamily: 'monospace',
                    height: 1.5,
                  ),
                ),
              )),

        // ── Phase 2 preview ────────────────────────────────────────────────────
        const SizedBox(height: 32),
        const _SectionHeader('After Phase 1 — Locked'),
        const SizedBox(height: 6),
        const Text(
          'After Default Gain test succeeds, unlock in order:\n'
          '• Mute 0x000B / 0x0325 / 0x0327 (polarity verification required)\n'
          '• Input source (Analog / Digital / Bluetooth)\n'
          '• 10-band EQ coefficient addresses\n'
          '• HPF / LPF filter addresses\n'
          '• DAC0–3 output gain\n'
          '• DAC0–3 delay\n'
          '• Phase / invert\n\n'
          'Do not implement these until address / value behavior is confirmed\n'
          'via Export map and Capture Window.',
          style: TextStyle(color: Colors.white24, fontSize: 10, height: 1.7),
        ),
      ],
    );
  }
}

// ── Widget components ─────────────────────────────────────────────────────────

class _WarningBanner extends StatelessWidget {
  final String text;
  const _WarningBanner(this.text);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: const Color(0xFFB45309)),
        borderRadius: BorderRadius.circular(6),
        color: const Color(0xFF1A0F00),
      ),
      child: Text(
        text,
        style: const TextStyle(color: Color(0xFFD97706), fontSize: 11, height: 1.6),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader(this.title);

  @override
  Widget build(BuildContext context) {
    return Text(
      title.toUpperCase(),
      style: const TextStyle(
        color: Colors.white54,
        fontSize: 10,
        letterSpacing: 1.5,
        fontWeight: FontWeight.w600,
      ),
    );
  }
}

class _InfoTable extends StatelessWidget {
  final List<(String, String)> rows;
  const _InfoTable({required this.rows});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.white12),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(
        children: rows.map((r) => Padding(
          padding: const EdgeInsets.only(bottom: 5),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 110,
                child: Text(r.$1,
                    style: const TextStyle(color: Colors.white38, fontSize: 11)),
              ),
              Expanded(
                child: Text(r.$2,
                    style: const TextStyle(
                        color: Colors.white70, fontSize: 11, fontFamily: 'monospace')),
              ),
            ],
          ),
        )).toList(),
      ),
    );
  }
}

class _AddressTable extends StatelessWidget {
  final List<(String, String, String, bool)> entries;
  const _AddressTable({required this.entries});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 6),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.white12),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(
        children: entries.map((e) {
          final (addr, cell, param, safe) = e;
          return Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 54,
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                  decoration: BoxDecoration(
                    color: safe ? const Color(0xFF0D2B0D) : const Color(0xFF1A0A0A),
                    borderRadius: BorderRadius.circular(3),
                  ),
                  child: Text(
                    addr,
                    style: TextStyle(
                      color: safe ? Colors.greenAccent : Colors.redAccent,
                      fontSize: 10,
                      fontFamily: 'monospace',
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(cell,
                          style: const TextStyle(color: Colors.white70, fontSize: 11)),
                      Text(param,
                          style: const TextStyle(
                              color: Colors.white38, fontSize: 10, fontStyle: FontStyle.italic)),
                    ],
                  ),
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }
}

class _ConfirmCheckbox extends StatelessWidget {
  final bool value;
  final ValueChanged<bool?> onChanged;
  final String label;
  const _ConfirmCheckbox({required this.value, required this.onChanged, required this.label});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => onChanged(!value),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          border: Border.all(
              color: value ? Colors.greenAccent.withValues(alpha: 0.4) : Colors.white12),
          borderRadius: BorderRadius.circular(6),
          color: value ? Colors.green.withValues(alpha: 0.05) : null,
        ),
        child: Row(
          children: [
            Checkbox(
              value: value,
              onChanged: onChanged,
              activeColor: Colors.greenAccent,
              checkColor: Colors.black,
              side: const BorderSide(color: Colors.white24),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  color: value ? Colors.greenAccent : Colors.white54,
                  fontSize: 12,
                  height: 1.5,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _GainButton extends StatelessWidget {
  final String label;
  final List<int> bytes;
  final bool isRestore;
  final bool enabled;
  final bool busy;
  final VoidCallback onTap;

  const _GainButton({
    required this.label,
    required this.bytes,
    required this.isRestore,
    required this.enabled,
    required this.busy,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final byteStr = Adau1701PacketBuilder.toHex(bytes);
    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 150),
        opacity: enabled ? 1.0 : 0.35,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          decoration: BoxDecoration(
            border: Border.all(
              color: isRestore
                  ? Colors.green.withValues(alpha: 0.5)
                  : Colors.white24,
            ),
            borderRadius: BorderRadius.circular(6),
            color: isRestore
                ? Colors.green.withValues(alpha: 0.06)
                : null,
          ),
          child: Row(
            children: [
              if (busy)
                const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                      strokeWidth: 1.5, color: Colors.white38),
                )
              else
                Icon(
                  isRestore ? Icons.restore : Icons.speaker,
                  size: 16,
                  color: isRestore ? Colors.greenAccent : Colors.white54,
                ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: TextStyle(
                        color: isRestore ? Colors.greenAccent : Colors.white,
                        fontSize: 13,
                        letterSpacing: 0.5,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '→ 0x0321–0x0324 ← $byteStr',
                      style: const TextStyle(
                          color: Colors.white24, fontSize: 10, fontFamily: 'monospace'),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.send_rounded, size: 14, color: Colors.white24),
            ],
          ),
        ),
      ),
    );
  }
}

class _ResultCard extends StatelessWidget {
  final Adau1701MultiWriteResult result;
  const _ResultCard({required this.result});

  @override
  Widget build(BuildContext context) {
    final ok = result.allSucceeded;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(
            color: ok
                ? Colors.greenAccent.withValues(alpha: 0.4)
                : Colors.redAccent.withValues(alpha: 0.5)),
        borderRadius: BorderRadius.circular(6),
        color: ok
            ? Colors.green.withValues(alpha: 0.04)
            : Colors.red.withValues(alpha: 0.04),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(
              ok ? Icons.check_circle_outline : Icons.error_outline,
              color: ok ? Colors.greenAccent : Colors.redAccent,
              size: 16,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                result.summary,
                style: TextStyle(
                    color: ok ? Colors.greenAccent : Colors.redAccent,
                    fontSize: 12,
                    height: 1.4),
              ),
            ),
          ]),
          const SizedBox(height: 8),
          ...result.writes.map((r) => Padding(
                padding: const EdgeInsets.only(bottom: 3),
                child: Text(
                  r.logLine,
                  style: TextStyle(
                    color: r.success ? Colors.white38 : Colors.redAccent.withValues(alpha: 0.8),
                    fontSize: 10,
                    fontFamily: 'monospace',
                    height: 1.5,
                  ),
                ),
              )),
        ],
      ),
    );
  }
}

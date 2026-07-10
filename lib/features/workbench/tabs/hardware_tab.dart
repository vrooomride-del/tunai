/// PRO Engineering — Hardware Tab: USBi Temporary Executor panel.
///
/// Access: TUNAI PRO → Workbench → Hardware.
/// NOT accessible from the normal Consumer app flow.
///
/// USBi is a TEMPORARY Windows engineering transport.
/// ICP5 (BLE) remains the final production write target.
///
/// Scope: Master Volume L/R only (addresses 0x0067 / 0x0064).
/// No PEQ / XO / Gain / Delay / SafeLoad / EEPROM.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../../../core/pro_usbi_native_backend.dart';
import '../../../core/pro_usbi_temporary_executor.dart';
import '../../../core/transport_command_envelope.dart';
import '../../../core/dsp_address_registry.dart';

class HardwareTab extends StatefulWidget {
  const HardwareTab({super.key});

  @override
  State<HardwareTab> createState() => _HardwareTabState();
}

class _HardwareTabState extends State<HardwareTab> {
  late final ProUsbiNativeBackend _backend;
  late final ProUsbiTemporaryExecutor _executor;

  // ── UI state ───────────────────────────────────────────────────────────────
  CommandType _selectedCommand = CommandType.masterVolumeL;
  double _selectedValue = 1.0;
  bool _operatorConfirmed = false;
  bool _showDetails = false;

  // ── Execution log ──────────────────────────────────────────────────────────
  final List<_LogEntry> _log = [];
  ExecutionResult? _lastResult;

  @override
  void initState() {
    super.initState();
    _backend = ProUsbiNativeBackend.createDefault();
    _executor = ProUsbiTemporaryExecutor(_backend);
  }

  int get _address => _selectedCommand == CommandType.masterVolumeL
      ? DspAddressRegistry.adau1466MasterVolumeL
      : DspAddressRegistry.adau1466MasterVolumeR;

  bool get _canExecute {
    // Mirror the executor's guard chain in the UI to keep the button state accurate.
    // Guard D1: Windows (or allow in debug for testing — UI still shows warning)
    // Guard D3: Backend connected
    // Guard D7: Operator confirmed
    return _backend.isConnected && _operatorConfirmed;
  }

  // ── Actions ────────────────────────────────────────────────────────────────

  Future<void> _checkBackend() async {
    _addLog('Checking USBi backend...');
    final status = await _backend.checkAvailability();
    setState(() {});
    _addLog('Backend status: ${status.name}'
        '${_backend.statusDetail != null ? " — ${_backend.statusDetail}" : ""}');
  }

  Future<void> _openDevice() async {
    _addLog('Opening USBi device...');
    final status = await _backend.openDevice();
    setState(() {});
    _addLog('Open result: ${status.name}'
        '${_backend.statusDetail != null ? " — ${_backend.statusDetail}" : ""}');
  }

  Future<void> _closeDevice() async {
    _addLog('Closing USBi device...');
    await _backend.closeDevice();
    setState(() {});
    _addLog('Device closed. Status: ${_backend.status.name}');
  }

  Future<void> _execute() async {
    if (!_canExecute) return;

    final confirmed = await _showConfirmDialog();
    if (!confirmed) {
      _addLog('Write cancelled by operator.');
      return;
    }

    final cmd = TransportCommandEnvelope(
      transport: HardwareTransportBackend.usbiWindowsTemporary,
      commandType: _selectedCommand,
      address: _address,
      value: _selectedValue,
      operatorConfirmed: true,
    );

    _addLog('--- Executing Master Volume Write ---');
    _addLog('Command: ${_selectedCommand.name}  '
        'Addr: 0x${_address.toRadixString(16).toUpperCase()}  '
        'Value: $_selectedValue');

    final result = await _executor.executeMasterVolumeWrite(cmd);

    setState(() {
      _lastResult = result;
    });

    if (result.setupBytes != null) {
      _addLog('Setup:   ${ProUsbiPacketBuilder.toHex(result.setupBytes!)}');
    }
    if (result.bodyBytes != null) {
      _addLog('Body:    ${ProUsbiPacketBuilder.toHex(result.bodyBytes!)}');
    }
    if (result.ackBytes != null) {
      _addLog('ACK:     ${ProUsbiPacketBuilder.toHex(result.ackBytes!)}');
    }
    _addLog('wasActualWrite: ${result.wasActualWrite}');
    _addLog('ackReceived:    ${result.ackReceived}');
    _addLog('ackSuccess:     ${result.ackSuccess}');
    if (result.failureReason != null) {
      _addLog('FAILURE: ${result.failureReason}');
    }
    if (result.validationAttempt != null) {
      final a = result.validationAttempt!;
      _addLog('Validation: ${a.resultStatus.name}  '
          'liveWriteVerified=${a.liveWriteVerified}');
    }
    _addLog('--- Done ---');
  }

  Future<void> _restoreVolume() async {
    if (!_backend.isConnected) {
      _addLog('Cannot restore — backend not connected.');
      return;
    }
    _addLog('--- Restore Master Volume to 1.0 ---');
    for (final cmd in [CommandType.masterVolumeL, CommandType.masterVolumeR]) {
      final envelope = TransportCommandEnvelope(
        transport: HardwareTransportBackend.usbiWindowsTemporary,
        commandType: cmd,
        address: cmd == CommandType.masterVolumeL
            ? DspAddressRegistry.adau1466MasterVolumeL
            : DspAddressRegistry.adau1466MasterVolumeR,
        value: 1.0,
        operatorConfirmed: true,
      );
      final result = await _executor.executeMasterVolumeWrite(envelope);
      _addLog('Restore ${cmd.name}: '
          'wasActualWrite=${result.wasActualWrite}  '
          'ackSuccess=${result.ackSuccess}');
    }
    setState(() {});
    _addLog('--- Restore complete ---');
  }

  void _addLog(String msg) {
    if (kDebugMode) debugPrint('[HardwareTab] $msg');
    setState(() {
      _log.add(_LogEntry(msg, DateTime.now()));
      if (_log.length > 200) _log.removeAt(0);
    });
  }

  Future<bool> _showConfirmDialog() async {
    return await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            backgroundColor: const Color(0xFF1A1A1A),
            title: const Text('Confirm USBi Write',
                style: TextStyle(color: Colors.white, fontSize: 14, letterSpacing: 1)),
            content: Column(mainAxisSize: MainAxisSize.min, children: [
              _ConfirmRow('Command', _selectedCommand.name),
              _ConfirmRow('Address',
                  '0x${_address.toRadixString(16).toUpperCase()}'),
              _ConfirmRow('Value', _selectedValue.toStringAsFixed(3)),
              const _ConfirmRow('Transport', 'USBi Windows (TEMPORARY)'),
              const SizedBox(height: 12),
              const Text(
                'This writes to volatile PRAM only.\n'
                'Power cycle restores factory values.',
                style: TextStyle(color: Colors.white38, fontSize: 11, height: 1.5),
              ),
            ]),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel', style: TextStyle(color: Colors.white38)),
              ),
              TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('WRITE',
                    style: TextStyle(color: Color(0xFFFF6B35), fontWeight: FontWeight.w600)),
              ),
            ],
          ),
        ) ??
        false;
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 40),
      children: [
        // ── Engineering warning ──────────────────────────────────────────────
        const _WarningBanner(
          'USBi is temporary engineering transport. ICP5 remains the final target.',
        ),
        const SizedBox(height: 20),

        // ── Backend status ───────────────────────────────────────────────────
        const _SectionHeader('USBi Native Backend'),
        _StatusCard(backend: _backend),
        const SizedBox(height: 12),
        Row(children: [
          _ProButton(
            label: 'Check Backend',
            onTap: _checkBackend,
          ),
          const SizedBox(width: 10),
          _ProButton(
            label: 'Open Device',
            onTap: _backend.status == UsbiBackendStatus.deviceDetected ||
                    _backend.status == UsbiBackendStatus.driverAvailable
                ? _openDevice
                : null,
          ),
          const SizedBox(width: 10),
          _ProButton(
            label: 'Close Device',
            onTap: _backend.isConnected ? _closeDevice : null,
            destructive: true,
          ),
        ]),

        const SizedBox(height: 28),

        // ── Master Volume write ──────────────────────────────────────────────
        const _SectionHeader('Master Volume Write  (ADAU1466 / USBi)'),
        const SizedBox(height: 4),
        const Text(
          'Scope: Master Volume L/R only. '
          'No PEQ / XO / Gain / Delay / SafeLoad / EEPROM.',
          style: TextStyle(color: Colors.white24, fontSize: 10, height: 1.5),
        ),
        const SizedBox(height: 14),

        // Command selector
        Row(children: [
          for (final cmd in CommandType.values) ...[
            _SelectChip(
              label: cmd == CommandType.masterVolumeL ? 'Vol L (0x0067)' : 'Vol R (0x0064)',
              selected: _selectedCommand == cmd,
              onTap: () => setState(() => _selectedCommand = cmd),
            ),
            if (cmd != CommandType.values.last) const SizedBox(width: 10),
          ],
        ]),
        const SizedBox(height: 14),

        // Value selector
        _ValueSelector(
          value: _selectedValue,
          onChanged: (v) => setState(() => _selectedValue = v),
        ),
        const SizedBox(height: 14),

        // Operator confirmation
        GestureDetector(
          onTap: () => setState(() => _operatorConfirmed = !_operatorConfirmed),
          child: Row(children: [
            Container(
              width: 18,
              height: 18,
              decoration: BoxDecoration(
                border: Border.all(
                    color: _operatorConfirmed ? const Color(0xFFFF6B35) : Colors.white24),
                borderRadius: BorderRadius.circular(3),
                color: _operatorConfirmed
                    ? const Color(0xFFFF6B35).withValues(alpha: 0.15)
                    : Colors.transparent,
              ),
              child: _operatorConfirmed
                  ? const Icon(Icons.check, size: 12, color: Color(0xFFFF6B35))
                  : null,
            ),
            const SizedBox(width: 10),
            const Text(
              'I confirm this is an intentional engineering write to volatile PRAM',
              style: TextStyle(color: Colors.white54, fontSize: 11),
            ),
          ]),
        ),
        const SizedBox(height: 16),

        // Execute + Restore
        Row(children: [
          Expanded(
            child: _ProButton(
              label: 'Execute Write',
              onTap: _canExecute ? _execute : null,
              accent: true,
            ),
          ),
          const SizedBox(width: 10),
          _ProButton(
            label: 'Restore 1.0',
            onTap: _backend.isConnected ? _restoreVolume : null,
          ),
        ]),

        // Last result summary
        if (_lastResult != null) ...[
          const SizedBox(height: 16),
          _ResultSummary(result: _lastResult!),
        ],

        const SizedBox(height: 28),

        // ── Execution log ────────────────────────────────────────────────────
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const _SectionHeader('Execution Log'),
            GestureDetector(
              onTap: () => setState(() => _showDetails = !_showDetails),
              child: Text(
                _showDetails ? 'Hide details' : 'Show details',
                style: const TextStyle(color: Colors.white24, fontSize: 10),
              ),
            ),
          ],
        ),
        if (_showDetails && _log.isNotEmpty)
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.black,
              border: Border.all(color: Colors.white12),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: _log.reversed.take(50).map((e) => Text(
                '[${_ts(e.time)}] ${e.message}',
                style: const TextStyle(
                    color: Color(0xFF69F0AE), fontSize: 10, fontFamily: 'monospace', height: 1.4),
              )).toList(),
            ),
          ),
        if (!_showDetails && _log.isNotEmpty)
          Text(
            _log.last.message,
            style: const TextStyle(color: Colors.white24, fontSize: 10),
          ),
      ],
    );
  }

  String _ts(DateTime t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}:${t.second.toString().padLeft(2, '0')}';
}

// ── Supporting widgets ────────────────────────────────────────────────────────

class _WarningBanner extends StatelessWidget {
  final String text;
  const _WarningBanner(this.text);
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          border: Border.all(color: const Color(0xFFFF6B35).withValues(alpha: 0.4)),
          borderRadius: BorderRadius.circular(6),
          color: const Color(0xFFFF6B35).withValues(alpha: 0.06),
        ),
        child: Row(children: [
          const Icon(Icons.warning_amber_rounded, color: Color(0xFFFF6B35), size: 14),
          const SizedBox(width: 8),
          Expanded(
            child: Text(text,
                style: const TextStyle(color: Color(0xFFFF6B35), fontSize: 11, height: 1.4)),
          ),
        ]),
      );
}

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader(this.title);
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Text(title,
            style: TextStyle(
                color: Colors.white.withValues(alpha: 0.35),
                fontSize: 10,
                letterSpacing: 1.5)),
      );
}

class _StatusCard extends StatelessWidget {
  final ProUsbiNativeBackend backend;
  const _StatusCard({required this.backend});

  Color get _color => switch (backend.status) {
        UsbiBackendStatus.connected => const Color(0xFF69F0AE),
        UsbiBackendStatus.deviceDetected ||
        UsbiBackendStatus.driverAvailable =>
          const Color(0xFFFFD700),
        UsbiBackendStatus.pending => Colors.white38,
        UsbiBackendStatus.accessDenied || UsbiBackendStatus.error => Colors.redAccent,
        UsbiBackendStatus.unavailable => Colors.white24,
      };

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          border: Border.all(color: _color.withValues(alpha: 0.3)),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(children: [
          Container(width: 7, height: 7,
              decoration: BoxDecoration(color: _color, shape: BoxShape.circle)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(backend.status.name,
                  style: TextStyle(color: _color, fontSize: 12, letterSpacing: 0.5)),
              if (backend.statusDetail != null)
                Text(backend.statusDetail!,
                    style: const TextStyle(color: Colors.white24, fontSize: 10, height: 1.4)),
            ]),
          ),
        ]),
      );
}

class _SelectChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _SelectChip({required this.label, required this.selected, required this.onTap});
  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(
            color: selected ? Colors.white.withValues(alpha: 0.07) : Colors.transparent,
            border: Border.all(
                color: selected ? Colors.white54 : Colors.white.withValues(alpha: 0.15)),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(label,
              style: TextStyle(
                  color: selected ? Colors.white : Colors.white38,
                  fontSize: 11,
                  fontFamily: 'monospace')),
        ),
      );
}

class _ValueSelector extends StatelessWidget {
  final double value;
  final ValueChanged<double> onChanged;
  const _ValueSelector({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    const presets = [0.0, 0.5, 1.0];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          Text('Value: ${value.toStringAsFixed(3)}',
              style: const TextStyle(color: Colors.white54, fontSize: 11, fontFamily: 'monospace')),
          const SizedBox(width: 12),
          ...presets.map((p) => Padding(
                padding: const EdgeInsets.only(right: 8),
                child: GestureDetector(
                  onTap: () => onChanged(p),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      border: Border.all(
                          color: value == p ? Colors.white54 : Colors.white12),
                      borderRadius: BorderRadius.circular(3),
                    ),
                    child: Text(p.toStringAsFixed(1),
                        style: TextStyle(
                            color: value == p ? Colors.white : Colors.white38,
                            fontSize: 11,
                            fontFamily: 'monospace')),
                  ),
                ),
              )),
        ]),
        const SizedBox(height: 8),
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            activeTrackColor: Colors.white54,
            inactiveTrackColor: Colors.white12,
            thumbColor: Colors.white,
            overlayColor: Colors.white12,
            trackHeight: 1,
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
          ),
          child: Slider(
            value: value,
            min: 0.0,
            max: 1.0,
            divisions: 100,
            onChanged: onChanged,
          ),
        ),
      ],
    );
  }
}

class _ResultSummary extends StatelessWidget {
  final ExecutionResult result;
  const _ResultSummary({required this.result});

  @override
  Widget build(BuildContext context) {
    final ok = result.fullSuccess;
    final color = ok ? const Color(0xFF69F0AE) : Colors.redAccent;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: color.withValues(alpha: 0.3)),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(ok ? 'Write succeeded' : 'Write failed / blocked',
            style: TextStyle(color: color, fontSize: 12)),
        const SizedBox(height: 6),
        _Kv('wasActualWrite', '${result.wasActualWrite}'),
        _Kv('ackReceived', '${result.ackReceived}'),
        _Kv('ackSuccess', '${result.ackSuccess}'),
        if (result.validationAttempt != null)
          _Kv('validationStatus', result.validationAttempt!.resultStatus.name),
        if (result.failureReason != null)
          _Kv('failure', result.failureReason!),
      ]),
    );
  }
}

class _Kv extends StatelessWidget {
  final String k;
  final String v;
  const _Kv(this.k, this.v);
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 2),
        child: Row(children: [
          Text('$k: ', style: const TextStyle(color: Colors.white38, fontSize: 10, fontFamily: 'monospace')),
          Expanded(child: Text(v, style: const TextStyle(color: Colors.white54, fontSize: 10, fontFamily: 'monospace'))),
        ]),
      );
}

class _ConfirmRow extends StatelessWidget {
  final String label;
  final String value;
  const _ConfirmRow(this.label, this.value);
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Row(children: [
          SizedBox(width: 80,
              child: Text('$label:', style: const TextStyle(color: Colors.white38, fontSize: 12))),
          Text(value, style: const TextStyle(color: Colors.white, fontSize: 12, fontFamily: 'monospace')),
        ]),
      );
}

class _ProButton extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;
  final bool accent;
  final bool destructive;
  const _ProButton({required this.label, this.onTap, this.accent = false, this.destructive = false});

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    final color = destructive
        ? Colors.redAccent
        : accent
            ? const Color(0xFFFF6B35)
            : Colors.white54;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: BoxDecoration(
          border: Border.all(color: enabled ? color.withValues(alpha: 0.5) : Colors.white12),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(label,
            style: TextStyle(
                color: enabled ? color : Colors.white24,
                fontSize: 11,
                letterSpacing: 0.5)),
      ),
    );
  }
}

// ── Log entry ─────────────────────────────────────────────────────────────────

class _LogEntry {
  final String message;
  final DateTime time;
  const _LogEntry(this.message, this.time);
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../../core/device_service.dart';
import '../../core/speaker_profile.dart';

final deviceProvider = StateNotifierProvider<DeviceNotifier, TunaiDevice?>(
  (ref) => DeviceNotifier(),
);

class DeviceNotifier extends StateNotifier<TunaiDevice?> {
  DeviceNotifier() : super(null) { _load(); }
  Future<void> _load() async { state = await DeviceService.loadDevice(); }
  Future<void> setDevice(TunaiDevice d) async { await DeviceService.saveDevice(d); state = d; }
  Future<void> clear() async { await DeviceService.clearDevice(); state = null; }

  SpeakerProfile? toSpeakerProfile() {
    if (state == null) return null;
    return SpeakerProfile(
      id: state!.serial, name: state!.model, description: '시리얼: ${state!.serial}',
      fs: state!.woofer.fs, qts: state!.woofer.qts, vas: state!.woofer.vas,
      xmax: state!.woofer.xmax, sensitivity: state!.woofer.sensitivity,
    );
  }
}

class DeviceScreen extends ConsumerStatefulWidget {
  const DeviceScreen({super.key});
  @override
  ConsumerState<DeviceScreen> createState() => _DeviceScreenState();
}

class _DeviceScreenState extends ConsumerState<DeviceScreen> {
  bool _scanning = false;
  bool _loading = false;
  String _status = '';
  TunaiDevice? _scanned;

  void _onDetect(BarcodeCapture capture) async {
    if (_loading) return;
    final raw = capture.barcodes.firstOrNull?.rawValue;
    if (raw == null) return;

    // QR URL 파싱: https://tunai.kr/register/T1-261001542
    String serial;
    if (raw.contains('tunai.kr/register/')) {
      serial = Uri.parse(raw).pathSegments.last;
    } else {
      serial = raw.trim();
    }

    setState(() { _loading = true; _scanning = false; _status = '서버 조회 중...'; });
    final device = await DeviceService.fetchDevice(serial);
    if (device == null) {
      setState(() { _loading = false; _status = '등록되지 않은 시리얼입니다: $serial'; });
      return;
    }
    setState(() { _loading = false; _scanned = device; _status = ''; });
  }

  Future<void> _register() async {
    if (_scanned == null) return;
    setState(() { _loading = true; _status = '등록 중...'; });
    await ref.read(deviceProvider.notifier).setDevice(_scanned!);
    setState(() { _loading = false; _scanned = null; _status = '등록 완료!'; });
  }

  @override
  Widget build(BuildContext context) {
    final device = ref.watch(deviceProvider);
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const Text('MY SPEAKER', style: TextStyle(color: Colors.white70, fontSize: 11, letterSpacing: 3)),
            const SizedBox(height: 24),

            // 등록된 디바이스 표시
            if (device != null) ...[
              _DeviceCard(device: device),
              const SizedBox(height: 16),
              GestureDetector(
                onTap: () => ref.read(deviceProvider.notifier).clear(),
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  decoration: BoxDecoration(border: Border.all(color: Colors.white24), borderRadius: BorderRadius.circular(6)),
                  child: const Center(child: Text('재등록', style: TextStyle(color: Colors.white38, fontSize: 11, letterSpacing: 2))),
                ),
              ),
            ],

            // 미등록 상태
            if (device == null) ...[
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(border: Border.all(color: Colors.white12), borderRadius: BorderRadius.circular(8)),
                child: const Column(children: [
                  Icon(Icons.qr_code_scanner, color: Colors.white24, size: 48),
                  SizedBox(height: 12),
                  Text('TUNAI ONE 후면 QR을 스캔하세요', style: TextStyle(color: Colors.white54, fontSize: 13)),
                  SizedBox(height: 4),
                  Text('스피커 T/S 데이터가 자동으로 로드됩니다', style: TextStyle(color: Colors.white24, fontSize: 11)),
                ]),
              ),
              const SizedBox(height: 16),

              // QR 스캐너
              if (_scanning) ...[
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: SizedBox(
                    height: 280,
                    child: MobileScanner(onDetect: _onDetect),
                  ),
                ),
                const SizedBox(height: 12),
                GestureDetector(
                  onTap: () => setState(() => _scanning = false),
                  child: const Center(child: Text('취소', style: TextStyle(color: Colors.white38, fontSize: 11))),
                ),
              ] else ...[
                ElevatedButton.icon(
                  onPressed: _loading ? null : () => setState(() { _scanning = true; _scanned = null; _status = ''; }),
                  icon: const Icon(Icons.qr_code_scanner, size: 18),
                  label: Text(_loading ? '조회 중...' : 'QR 스캔'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white, foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                  ),
                ),
                const SizedBox(height: 8),
                // 수동 입력
                _ManualInput(onSerial: (serial) async {
                  setState(() { _loading = true; _status = '조회 중...'; });
                  final d = await DeviceService.fetchDevice(serial);
                  setState(() { _loading = false; _scanned = d; _status = d == null ? '등록되지 않은 시리얼' : ''; });
                }),
              ],

              // 스캔 결과
              if (_scanned != null) ...[
                const SizedBox(height: 16),
                _DeviceCard(device: _scanned!),
                const SizedBox(height: 12),
                ElevatedButton(
                  onPressed: _loading ? null : _register,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white, foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                  ),
                  child: const Text('이 스피커로 등록', style: TextStyle(fontSize: 12, letterSpacing: 2)),
                ),
              ],

              if (_status.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(_status, style: TextStyle(
                  color: _status.contains('완료') ? Colors.white60 : Colors.redAccent,
                  fontSize: 11,
                )),
              ],
            ],
          ]),
        ),
      ),
    );
  }
}

class _DeviceCard extends StatelessWidget {
  final TunaiDevice device;
  const _DeviceCard({required this.device});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(border: Border.all(color: Colors.white24), borderRadius: BorderRadius.circular(8), color: Colors.white.withOpacity(0.03)),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        const Icon(Icons.speaker, color: Colors.white54, size: 18),
        const SizedBox(width: 10),
        Text(device.model, style: const TextStyle(color: Colors.white, fontSize: 13, letterSpacing: 2)),
        const Spacer(),
        Text(device.manufactured, style: const TextStyle(color: Colors.white38, fontSize: 10)),
      ]),
      const SizedBox(height: 4),
      Text(device.serial, style: const TextStyle(color: Colors.white38, fontSize: 10, letterSpacing: 1)),
      const SizedBox(height: 12),
      const Divider(color: Colors.white12),
      const SizedBox(height: 8),
      const Text('WOOFER', style: TextStyle(color: Colors.white24, fontSize: 9, letterSpacing: 2)),
      const SizedBox(height: 6),
      Row(children: [
        _Spec('Fs', '${device.woofer.fs.toStringAsFixed(0)}Hz'),
        _Spec('Qts', device.woofer.qts.toStringAsFixed(2)),
        _Spec('Xmax', '${device.woofer.xmax.toStringAsFixed(1)}mm'),
        _Spec('SPL', '${device.woofer.sensitivity.toStringAsFixed(1)}dB'),
      ]),
      const SizedBox(height: 10),
      const Text('TWEETER', style: TextStyle(color: Colors.white24, fontSize: 9, letterSpacing: 2)),
      const SizedBox(height: 6),
      Row(children: [
        _Spec('Fs', '${device.tweeter.fs.toStringAsFixed(0)}Hz'),
        _Spec('SPL', '${device.tweeter.sensitivity.toStringAsFixed(1)}dB'),
        _Spec('Re', '${device.tweeter.re.toStringAsFixed(1)}Ω'),
      ]),
    ]),
  );
}

class _Spec extends StatelessWidget {
  final String label, value;
  const _Spec(this.label, this.value);
  @override
  Widget build(BuildContext context) => Expanded(child: Column(children: [
    Text(label, style: const TextStyle(color: Colors.white24, fontSize: 9)),
    Text(value, style: const TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.w500)),
  ]));
}

class _ManualInput extends StatefulWidget {
  final void Function(String) onSerial;
  const _ManualInput({required this.onSerial});
  @override
  State<_ManualInput> createState() => _ManualInputState();
}

class _ManualInputState extends State<_ManualInput> {
  final _ctrl = TextEditingController();
  bool _show = false;
  @override
  Widget build(BuildContext context) => Column(children: [
    GestureDetector(
      onTap: () => setState(() => _show = !_show),
      child: const Text('시리얼 직접 입력', style: TextStyle(color: Colors.white24, fontSize: 11, decoration: TextDecoration.underline)),
    ),
    if (_show) ...[
      const SizedBox(height: 8),
      Row(children: [
        Expanded(child: TextField(
          controller: _ctrl,
          style: const TextStyle(color: Colors.white, fontSize: 12),
          decoration: const InputDecoration(
            hintText: 'T1-261001542',
            hintStyle: TextStyle(color: Colors.white12),
            isDense: true,
            contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 10),
            enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: Colors.white24)),
            focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: Colors.white54)),
          ),
        )),
        const SizedBox(width: 8),
        GestureDetector(
          onTap: () { if (_ctrl.text.isNotEmpty) widget.onSerial(_ctrl.text.trim()); },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(border: Border.all(color: Colors.white38), borderRadius: BorderRadius.circular(4)),
            child: const Text('조회', style: TextStyle(color: Colors.white54, fontSize: 11)),
          ),
        ),
      ]),
    ],
  ]);
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/enclosure_hash.dart';
import '../../core/api_service.dart';

class EnclosureScreen extends ConsumerStatefulWidget {
  const EnclosureScreen({super.key});
  @override
  ConsumerState<EnclosureScreen> createState() => _EnclosureScreenState();
}

class _EnclosureScreenState extends ConsumerState<EnclosureScreen> {
  String _type = 'ported';
  double _portDiameter = 50.0;
  double _portDepth = 80.0;
  double _volume = 15.0;
  bool _loading = false;
  List<dynamic> _matchedPresets = [];
  String? _currentHash;

  final _types = ['ported', 'sealed', 'passive'];

  String _buildHash() => EnclosureHash.generate(
    volumeL:      _volume,
    portLengthMm: _type == 'ported' ? _portDepth    : null,
    portDiamMm:   _type == 'ported' ? _portDiameter : null,
  );

  Future<void> _search() async {
    setState(() { _loading = true; _matchedPresets = []; });
    final hash = _buildHash();
    setState(() => _currentHash = hash);
    final res = await ApiService.getPresets(hash: hash);
    setState(() {
      _matchedPresets = res['status'] == 'ok' ? (res['data'] ?? []) : [];
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('ENCLOSURE',
                  style: TextStyle(color: Colors.white, fontSize: 18,
                      fontWeight: FontWeight.w200, letterSpacing: 6)),
              const SizedBox(height: 4),
              const Text('인클로저 스펙을 입력하면 동일한 스피커의 프리셋을 찾습니다.',
                  style: TextStyle(color: Colors.white38, fontSize: 11)),
              const SizedBox(height: 32),

              // 타입 선택
              _label('TYPE'),
              const SizedBox(height: 8),
              Row(
                children: _types.map((t) => GestureDetector(
                  onTap: () => setState(() => _type = t),
                  child: Container(
                    margin: const EdgeInsets.only(right: 8),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      border: Border.all(color: _type == t ? Colors.white : Colors.white24),
                      borderRadius: BorderRadius.circular(4),
                      color: _type == t ? Colors.white.withValues(alpha: 0.05) : Colors.transparent,
                    ),
                    child: Text(t.toUpperCase(),
                        style: TextStyle(
                          color: _type == t ? Colors.white : Colors.white38,
                          fontSize: 10, letterSpacing: 1,
                        )),
                  ),
                )).toList(),
              ),
              const SizedBox(height: 24),

              // 포트 직경
              if (_type == 'ported') ...[
                _SliderField(
                  label: 'PORT DIAMETER',
                  value: _portDiameter,
                  unit: 'mm',
                  min: 20, max: 100,
                  onChanged: (v) => setState(() => _portDiameter = v),
                ),
                const SizedBox(height: 16),
                _SliderField(
                  label: 'PORT DEPTH',
                  value: _portDepth,
                  unit: 'mm',
                  min: 20, max: 300,
                  onChanged: (v) => setState(() => _portDepth = v),
                ),
                const SizedBox(height: 16),
              ],

              // 내부 용적
              _SliderField(
                label: 'INTERNAL VOLUME',
                value: _volume,
                unit: 'L',
                min: 1, max: 100,
                onChanged: (v) => setState(() => _volume = v),
              ),
              const SizedBox(height: 32),

              // 해시 표시
              if (_currentHash != null)
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.white12),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('ENCLOSURE HASH',
                          style: TextStyle(color: Colors.white24, fontSize: 9, letterSpacing: 2)),
                      const SizedBox(height: 6),
                      Text(_currentHash!,
                          style: const TextStyle(
                            color: Colors.white38, fontSize: 9,
                            fontFamily: 'monospace',
                          )),
                    ],
                  ),
                ),

              const SizedBox(height: 16),

              // 검색 버튼
              GestureDetector(
                onTap: _loading ? null : _search,
                child: Container(
                  height: 48,
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.white),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Center(
                    child: _loading
                        ? const CircularProgressIndicator(color: Colors.white, strokeWidth: 1)
                        : const Text('FIND MATCHING PRESETS',
                            style: TextStyle(color: Colors.white, fontSize: 11, letterSpacing: 3)),
                  ),
                ),
              ),

              // 매칭 결과
              if (_matchedPresets.isNotEmpty) ...[
                const SizedBox(height: 24),
                Text('${_matchedPresets.length}개 프리셋 매칭됨',
                    style: const TextStyle(color: Colors.white54, fontSize: 12)),
                const SizedBox(height: 12),
                ..._matchedPresets.map((p) => Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.white12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(p['title'] ?? '',
                                style: const TextStyle(color: Colors.white, fontSize: 13)),
                            const SizedBox(height: 4),
                            Text('by ${p['nickname'] ?? ''}  ·  ↓${p['downloads'] ?? 0}',
                                style: const TextStyle(color: Colors.white38, fontSize: 10)),
                          ],
                        ),
                      ),
                      GestureDetector(
                        onTap: () {
                          ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('${p['title']} — COMMUNITY 탭에서 GET 하세요')));
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                          decoration: BoxDecoration(
                            border: Border.all(color: Colors.white24),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: const Text('GET',
                              style: TextStyle(color: Colors.white, fontSize: 10, letterSpacing: 2)),
                        ),
                      ),
                    ],
                  ),
                )),
              ] else if (_currentHash != null && !_loading)
                const Padding(
                  padding: EdgeInsets.only(top: 16),
                  child: Text('이 인클로저와 매칭되는 프리셋이 없습니다.\n측정 후 첫 번째로 공유해보세요!',
                      style: TextStyle(color: Colors.white38, fontSize: 12, height: 1.6)),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _label(String text) => Text(text,
      style: const TextStyle(color: Colors.white38, fontSize: 9, letterSpacing: 3));
}

class _SliderField extends StatelessWidget {
  final String label;
  final double value;
  final String unit;
  final double min, max;
  final Function(double) onChanged;
  const _SliderField({
    required this.label, required this.value, required this.unit,
    required this.min, required this.max, required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(label, style: const TextStyle(color: Colors.white38, fontSize: 9, letterSpacing: 2)),
            const Spacer(),
            Text('${value.toStringAsFixed(1)} $unit',
                style: const TextStyle(color: Colors.white, fontSize: 12)),
          ],
        ),
        SliderTheme(
          data: SliderThemeData(
            activeTrackColor: Colors.white,
            inactiveTrackColor: Colors.white12,
            thumbColor: Colors.white,
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
            trackHeight: 1,
            overlayShape: SliderComponentShape.noOverlay,
          ),
          child: Slider(value: value, min: min, max: max, onChanged: onChanged),
        ),
      ],
    );
  }
}

import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class WooferProfile {
  final double fs, qts, vas, xmax, sensitivity, re;
  const WooferProfile({required this.fs, required this.qts, required this.vas, required this.xmax, required this.sensitivity, required this.re});
  factory WooferProfile.fromJson(Map j) => WooferProfile(fs: (j['fs'] as num).toDouble(), qts: (j['qts'] as num).toDouble(), vas: (j['vas'] as num).toDouble(), xmax: (j['xmax'] as num).toDouble(), sensitivity: (j['sensitivity'] as num).toDouble(), re: (j['re'] as num).toDouble());
}

class TweeterProfile {
  final double fs, sensitivity, re;
  const TweeterProfile({required this.fs, required this.sensitivity, required this.re});
  factory TweeterProfile.fromJson(Map j) => TweeterProfile(fs: (j['fs'] as num).toDouble(), sensitivity: (j['sensitivity'] as num).toDouble(), re: (j['re'] as num).toDouble());
}

class TunaiDevice {
  final String serial, model, manufactured;
  final WooferProfile woofer;
  final TweeterProfile tweeter;
  final bool registered;

  const TunaiDevice({required this.serial, required this.model, required this.manufactured, required this.woofer, required this.tweeter, required this.registered});

  factory TunaiDevice.fromJson(Map j) => TunaiDevice(
    serial: j['serial'], model: j['model'], manufactured: j['manufactured'],
    woofer: WooferProfile.fromJson(j['woofer']),
    tweeter: TweeterProfile.fromJson(j['tweeter']),
    registered: j['registered'] ?? false,
  );
}

class DeviceService {
  static const _base = 'https://api.tunai.kr';
  static const _key = 'registered_device';

  static Future<TunaiDevice?> fetchDevice(String serial) async {
    try {
      final res = await http.get(Uri.parse('$_base/device/$serial'));
      final json = jsonDecode(res.body);
      if (json['status'] == 'ok') return TunaiDevice.fromJson(json['data']);
    } catch (_) {}
    return null;
  }

  static Future<bool> registerDevice(String serial, String token) async {
    try {
      final res = await http.post(
        Uri.parse('$_base/device/$serial/register'),
        headers: {'X-Auth-Token': token, 'Content-Type': 'application/json'},
      );
      final json = jsonDecode(res.body);
      return json['status'] == 'ok';
    } catch (_) {}
    return false;
  }

  static Future<void> saveDevice(TunaiDevice device) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode({
      'serial': device.serial, 'model': device.model, 'manufactured': device.manufactured,
      'woofer': {'fs': device.woofer.fs, 'qts': device.woofer.qts, 'vas': device.woofer.vas, 'xmax': device.woofer.xmax, 'sensitivity': device.woofer.sensitivity, 're': device.woofer.re},
      'tweeter': {'fs': device.tweeter.fs, 'sensitivity': device.tweeter.sensitivity, 're': device.tweeter.re},
      'registered': device.registered,
    }));
  }

  static Future<TunaiDevice?> loadDevice() async {
    final prefs = await SharedPreferences.getInstance();
    final str = prefs.getString(_key);
    if (str == null) return null;
    try { return TunaiDevice.fromJson(jsonDecode(str)); } catch (_) { return null; }
  }

  static Future<void> clearDevice() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
  }
}

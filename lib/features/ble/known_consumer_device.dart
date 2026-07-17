import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

@immutable
class KnownConsumerDevice {
  final String identifier;
  final String advertisedName;
  final String validatedProductIdentity;
  final DateTime lastSuccessfulConnectionAt;
  final bool autoReconnectEnabled;
  final bool lastDisconnectWasUserInitiated;

  const KnownConsumerDevice({
    required this.identifier,
    required this.advertisedName,
    required this.validatedProductIdentity,
    required this.lastSuccessfulConnectionAt,
    this.autoReconnectEnabled = true,
    this.lastDisconnectWasUserInitiated = false,
  });

  KnownConsumerDevice copyWith({
    DateTime? lastSuccessfulConnectionAt,
    bool? autoReconnectEnabled,
    bool? lastDisconnectWasUserInitiated,
  }) =>
      KnownConsumerDevice(
        identifier: identifier,
        advertisedName: advertisedName,
        validatedProductIdentity: validatedProductIdentity,
        lastSuccessfulConnectionAt:
            lastSuccessfulConnectionAt ?? this.lastSuccessfulConnectionAt,
        autoReconnectEnabled: autoReconnectEnabled ?? this.autoReconnectEnabled,
        lastDisconnectWasUserInitiated: lastDisconnectWasUserInitiated ??
            this.lastDisconnectWasUserInitiated,
      );

  Map<String, Object> toJson() => {
        'identifier': identifier,
        'advertisedName': advertisedName,
        'validatedProductIdentity': validatedProductIdentity,
        'lastSuccessfulConnectionAt':
            lastSuccessfulConnectionAt.toIso8601String(),
        'autoReconnectEnabled': autoReconnectEnabled,
        'lastDisconnectWasUserInitiated': lastDisconnectWasUserInitiated,
      };

  factory KnownConsumerDevice.fromJson(Map<String, dynamic> json) =>
      KnownConsumerDevice(
        identifier: json['identifier'] as String,
        advertisedName: json['advertisedName'] as String,
        validatedProductIdentity: json['validatedProductIdentity'] as String,
        lastSuccessfulConnectionAt:
            DateTime.parse(json['lastSuccessfulConnectionAt'] as String),
        autoReconnectEnabled: json['autoReconnectEnabled'] as bool? ?? true,
        lastDisconnectWasUserInitiated:
            json['lastDisconnectWasUserInitiated'] as bool? ?? false,
      );
}

abstract interface class KnownConsumerDevicePersistence {
  Future<KnownConsumerDevice?> load();
  Future<void> save(KnownConsumerDevice device);
  Future<void> clear();
}

class KnownConsumerDeviceStore implements KnownConsumerDevicePersistence {
  static const storageKey = 'tunai_known_consumer_device_v1';

  @override
  Future<KnownConsumerDevice?> load() async {
    try {
      final raw = (await SharedPreferences.getInstance()).getString(storageKey);
      if (raw == null) return null;
      return KnownConsumerDevice.fromJson(
        Map<String, dynamic>.from(jsonDecode(raw) as Map),
      );
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> save(KnownConsumerDevice device) async {
    final saved = await (await SharedPreferences.getInstance()).setString(
      storageKey,
      jsonEncode(device.toJson()),
    );
    if (!saved) throw StateError('Known Consumer device could not be saved.');
  }

  @override
  Future<void> clear() async {
    final cleared =
        await (await SharedPreferences.getInstance()).remove(storageKey);
    if (!cleared && await load() != null) {
      throw StateError('Known Consumer device could not be forgotten.');
    }
  }
}

import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// A previously connected BLE device, persisted locally.
class PairedDevice {
  final String remoteId;
  final String name;
  final DateTime lastConnected;

  PairedDevice({
    required this.remoteId,
    required this.name,
    required this.lastConnected,
  });

  Map<String, dynamic> toJson() => {
        'remoteId': remoteId,
        'name': name,
        'lastConnected': lastConnected.toIso8601String(),
      };

  factory PairedDevice.fromJson(Map<String, dynamic> json) => PairedDevice(
        remoteId: json['remoteId'] as String,
        name: json['name'] as String,
        lastConnected: DateTime.parse(json['lastConnected'] as String),
      );
}

/// Persists a list of previously connected devices using SharedPreferences.
class DeviceHistoryService {
  static const _key = 'paired_devices';

  Future<List<PairedDevice>> loadDevices() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_key);
    if (raw == null) return [];
    return raw
        .map((s) => PairedDevice.fromJson(
            jsonDecode(s) as Map<String, dynamic>))
        .toList()
      ..sort((a, b) => b.lastConnected.compareTo(a.lastConnected));
  }

  Future<void> addOrUpdate(String remoteId, String name) async {
    final devices = await loadDevices();
    devices.removeWhere((d) => d.remoteId == remoteId);
    devices.insert(
      0,
      PairedDevice(
        remoteId: remoteId,
        name: name,
        lastConnected: DateTime.now(),
      ),
    );
    await _save(devices);
  }

  Future<void> remove(String remoteId) async {
    final devices = await loadDevices();
    devices.removeWhere((d) => d.remoteId == remoteId);
    await _save(devices);
  }

  Future<void> _save(List<PairedDevice> devices) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = devices.map((d) => jsonEncode(d.toJson())).toList();
    await prefs.setStringList(_key, raw);
  }
}

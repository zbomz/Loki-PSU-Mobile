import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import '../ble/ble_service.dart';

/// ChangeNotifier that exposes BLE scan results, connection state,
/// and connect / disconnect actions to the UI.
class BleProvider extends ChangeNotifier {
  final BleService _bleService;

  BleProvider(this._bleService) {
    _bleService.stateStream.listen((_) => notifyListeners());
  }

  // ---------------------------------------------------------------------------
  // State
  // ---------------------------------------------------------------------------

  BleConnectionState get connectionState => _bleService.state;
  bool get isConnected =>
      _bleService.state == BleConnectionState.connected;
  BluetoothDevice? get connectedDevice => _bleService.connectedDevice;

  List<ScanResult> _scanResults = [];
  List<ScanResult> get scanResults => _scanResults;

  bool _isScanning = false;
  bool get isScanning => _isScanning;

  String? _error;
  String? get error => _error;

  // ---------------------------------------------------------------------------
  // Actions
  // ---------------------------------------------------------------------------

  void clearError() {
    _error = null;
    notifyListeners();
  }

  Future<void> startScan() async {
    _error = null;
    _scanResults = [];
    _isScanning = true;
    notifyListeners();

    try {
      // Listen to scan results.
      final sub = _bleService.scanResults.listen((results) {
        _scanResults = results;
        notifyListeners();
      });

      await _bleService.startScan(timeout: const Duration(seconds: 5));

      // Scan completed (timeout elapsed).
      await sub.cancel();
    } catch (e) {
      _error = e.toString();
    } finally {
      _isScanning = false;
      notifyListeners();
    }
  }

  Future<void> stopScan() async {
    await _bleService.stopScan();
    _isScanning = false;
    notifyListeners();
  }

  Future<void> connect(BluetoothDevice device) async {
    _error = null;
    notifyListeners();

    try {
      await _bleService.connect(device);
    } catch (e) {
      _error = e.toString();
    }
    notifyListeners();
  }

  Future<void> disconnect() async {
    await _bleService.disconnect();
    notifyListeners();
  }

  @override
  void dispose() {
    _bleService.dispose();
    super.dispose();
  }
}

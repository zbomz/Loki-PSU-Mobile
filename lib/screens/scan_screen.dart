import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:provider/provider.dart';

import '../ble/ble_service.dart';
import '../providers/ble_provider.dart';
import 'dashboard_screen.dart';

/// BLE scan screen — lists discovered Loki PSU devices and allows connecting.
class ScanScreen extends StatefulWidget {
  const ScanScreen({super.key});

  @override
  State<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends State<ScanScreen> {
  BluetoothAdapterState _adapterState = BluetoothAdapterState.unknown;

  @override
  void initState() {
    super.initState();
    _checkBluetoothState();
  }

  Future<void> _checkBluetoothState() async {
    try {
      // Get initial state
      final initialState = await FlutterBluePlus.adapterState.first;
      if (mounted) {
        setState(() {
          _adapterState = initialState;
        });
      }
      
      // Listen to Bluetooth adapter state changes
      FlutterBluePlus.adapterState.listen((state) {
        if (mounted) {
          setState(() {
            _adapterState = state;
          });
        }
      });
    } catch (e) {
      // Platform not supported (e.g., in tests) - silently skip
      // Bluetooth state will remain as 'unknown'
    }
  }

  @override
  Widget build(BuildContext context) {
    final ble = context.watch<BleProvider>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Loki PSU — Scan'),
        actions: [
          // Connection state chip
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Center(
              child: _ConnectionChip(state: ble.connectionState),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          // Bluetooth state warning
          if (_adapterState != BluetoothAdapterState.on)
            MaterialBanner(
              content: Text(
                _getBluetoothStateMessage(_adapterState),
                style: const TextStyle(color: Colors.white),
              ),
              backgroundColor: Colors.orange.shade700,
              actions: [
                TextButton(
                  onPressed: () {},
                  child: const Text('OK', style: TextStyle(color: Colors.white)),
                ),
              ],
            ),

          // Error banner
          if (ble.error != null)
            MaterialBanner(
              content: Text(
                _formatErrorMessage(ble.error!),
                style: const TextStyle(color: Colors.white),
              ),
              backgroundColor: Colors.red.shade700,
              actions: [
                TextButton(
                  onPressed: ble.clearError,
                  child: const Text('DISMISS', style: TextStyle(color: Colors.white)),
                ),
              ],
            ),

          // Scan results list
          Expanded(
            child: ble.scanResults.isEmpty
                ? Center(
                    child: Text(
                      ble.isScanning
                          ? 'Scanning for Loki PSU devices...'
                          : 'Tap the scan button to find devices',
                      style: Theme.of(context).textTheme.bodyLarge,
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    itemCount: ble.scanResults.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final result = ble.scanResults[index];
                      return _DeviceTile(
                        result: result,
                        onTap: () => _onDeviceTap(context, ble, result),
                      );
                    },
                  ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: ble.isScanning ? ble.stopScan : ble.startScan,
        icon: Icon(ble.isScanning ? Icons.stop : Icons.bluetooth_searching),
        label: Text(ble.isScanning ? 'Stop' : 'Scan'),
      ),
    );
  }

  Future<void> _onDeviceTap(
      BuildContext context, BleProvider ble, ScanResult result) async {
    await ble.connect(result.device);
    if (!context.mounted) return;
    if (ble.isConnected) {
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const DashboardScreen()),
      );
    }
  }

  String _formatErrorMessage(String error) {
    // Make Bluetooth errors more user-friendly
    if (error.toLowerCase().contains('bluetooth is not ready')) {
      return 'Bluetooth is initializing. Please wait a moment and try again.';
    }
    if (error.toLowerCase().contains('bluetooth must be turned on') ||
        error.toLowerCase().contains('cbmanagerstateunknown') ||
        error.toLowerCase().contains('cbmanagerstatepoweredoff')) {
      return 'Please turn on Bluetooth in your iPhone settings and try again.';
    }
    if (error.toLowerCase().contains('unauthorized') ||
        error.toLowerCase().contains('permission')) {
      return 'Please enable Bluetooth permissions for Loki PSU in Settings.';
    }
    return error;
  }

  String _getBluetoothStateMessage(BluetoothAdapterState state) {
    switch (state) {
      case BluetoothAdapterState.unavailable:
        return 'Bluetooth is not available on this device.';
      case BluetoothAdapterState.unauthorized:
        return 'Bluetooth permission required. Please enable it in Settings.';
      case BluetoothAdapterState.off:
        return 'Bluetooth is turned off. Please turn it on to scan for devices.';
      case BluetoothAdapterState.turningOn:
        return 'Bluetooth is turning on...';
      case BluetoothAdapterState.turningOff:
        return 'Bluetooth is turning off...';
      case BluetoothAdapterState.unknown:
        return 'Checking Bluetooth status...';
      case BluetoothAdapterState.on:
        return 'Bluetooth is ready.';
    }
  }
}

// -----------------------------------------------------------------------------
// Sub-widgets
// -----------------------------------------------------------------------------

class _ConnectionChip extends StatelessWidget {
  final BleConnectionState state;
  const _ConnectionChip({required this.state});

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (state) {
      BleConnectionState.disconnected => ('Disconnected', Colors.grey),
      BleConnectionState.connecting => ('Connecting...', Colors.orange),
      BleConnectionState.connected => ('Connected', Colors.green),
    };
    return Chip(
      label: Text(label, style: const TextStyle(fontSize: 12)),
      backgroundColor: color.withOpacity(0.2),
      side: BorderSide(color: color),
      padding: EdgeInsets.zero,
      visualDensity: VisualDensity.compact,
    );
  }
}

class _DeviceTile extends StatelessWidget {
  final ScanResult result;
  final VoidCallback onTap;

  const _DeviceTile({required this.result, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final deviceName = result.device.platformName.isNotEmpty
        ? result.device.platformName
        : 'Unknown';
    final deviceId = result.device.remoteId.toString();

    return ListTile(
      leading: const Icon(Icons.power, size: 32),
      title: Text(deviceName),
      subtitle: Text(deviceId),
      trailing: Text('${result.rssi} dBm'),
      onTap: onTap,
    );
  }
}

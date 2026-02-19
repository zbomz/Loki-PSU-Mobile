import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:provider/provider.dart';

import '../providers/ble_provider.dart';
import '../providers/wifi_provider.dart';
import '../wifi/provisioning_service.dart';

/// WiFi provisioning screen.
///
/// Flow:
///  1. Detect already-connected device (from BleProvider) OR scan for
///     provisioning-capable devices advertising as PROV_LOKI_*
///  2. User selects a device
///  3. User enters WiFi SSID + password
///  4. Provisioning runs (handshake → credentials → status polling)
///  5. Success or failure result
class ProvisioningScreen extends StatefulWidget {
  const ProvisioningScreen({super.key});

  @override
  State<ProvisioningScreen> createState() => _ProvisioningScreenState();
}

class _ProvisioningScreenState extends State<ProvisioningScreen> {
  final _ssidController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _obscurePassword = true;

  /// Devices found via BLE scan (PROV_LOKI_* advertisement filter).
  List<ScanResult> _provDevices = [];

  /// The device that is already connected via the main BleService/BleProvider
  /// (used for telemetry). Connected BLE devices never appear in scan results
  /// on iOS or Android, so we surface this separately.
  BluetoothDevice? _alreadyConnectedDevice;

  BluetoothDevice? _selectedDevice;
  StreamSubscription<List<ScanResult>>? _scanSub;

  ProvisioningResult? _result;
  bool _provisioning = false;

  bool _isScanning = false;
  String? _scanError;

  @override
  void initState() {
    super.initState();

    // Check for an existing BLE connection from the main telemetry service.
    // Connected devices are invisible to BLE scans, so we pull the device
    // directly from BleProvider and pre-select it.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final ble = context.read<BleProvider>();
      if (ble.isConnected && ble.connectedDevice != null) {
        setState(() {
          _alreadyConnectedDevice = ble.connectedDevice;
          // Auto-select the connected device so the user can go straight to
          // entering WiFi credentials without any extra tap.
          _selectedDevice = ble.connectedDevice;
        });
      }
    });

    _startScan();
  }

  @override
  void dispose() {
    _scanSub?.cancel();
    _ssidController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _startScan() {
    final wifi = context.read<WiFiProvider>();
    final service = wifi.provisioningService;

    setState(() {
      _isScanning = true;
      _scanError = null;
      _provDevices = [];
      // NOTE: Do NOT reset _alreadyConnectedDevice or _selectedDevice here —
      // the pre-connected device must survive a rescan.
    });

    _scanSub?.cancel();
    _scanSub = service
        .scanForProvisionableDevices(timeout: const Duration(seconds: 10))
        .listen(
      (results) {
        if (mounted) {
          setState(() {
            // Deduplicate: exclude the already-connected device from scan
            // results (it won't appear anyway, but guard just in case).
            _provDevices = _alreadyConnectedDevice == null
                ? results
                : results
                    .where((r) =>
                        r.device.remoteId !=
                        _alreadyConnectedDevice!.remoteId)
                    .toList();
          });
        }
      },
      onError: (Object e) {
        if (mounted) {
          setState(() {
            _isScanning = false;
            _scanError = e.toString().replaceFirst('Exception: ', '');
          });
        }
      },
      onDone: () {
        if (mounted) setState(() => _isScanning = false);
      },
    );
  }

  /// True when there is at least one device the user can select.
  bool get _hasAnyDevice =>
      _alreadyConnectedDevice != null || _provDevices.isNotEmpty;

  @override
  Widget build(BuildContext context) {
    final wifi = context.watch<WiFiProvider>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('WiFi Provisioning'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ---- Step 1: Device selection ----
            Text(
              'Step 1: Select Device',
              style: Theme.of(context)
                  .textTheme
                  .titleMedium!
                  .copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),

            // Already-connected device card (shown even while scanning).
            if (_alreadyConnectedDevice != null)
              _buildDeviceCard(
                device: _alreadyConnectedDevice!,
                subtitle: 'Currently connected via Bluetooth',
                rssi: null,
                isConnectedDevice: true,
              ),

            // Scanning spinner (only when no devices at all are visible yet).
            if (_isScanning && !_hasAnyDevice)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    children: [
                      const CircularProgressIndicator(),
                      const SizedBox(height: 16),
                      Text(
                        'Scanning for Loki PSU provisioning devices…',
                        style: Theme.of(context).textTheme.bodyMedium,
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              )
            else if (_scanError != null && !_hasAnyDevice)
              // Only surface the scan error when there is no device to use.
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    children: [
                      const Icon(Icons.bluetooth_disabled,
                          size: 40, color: Colors.red),
                      const SizedBox(height: 16),
                      Text(
                        _scanError!,
                        style: Theme.of(context)
                            .textTheme
                            .bodyMedium!
                            .copyWith(color: Colors.red),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 8),
                      TextButton.icon(
                        onPressed: _startScan,
                        icon: const Icon(Icons.refresh),
                        label: const Text('Retry'),
                      ),
                    ],
                  ),
                ),
              )
            else if (!_isScanning && !_hasAnyDevice)
              // Scan finished with zero results and no pre-connected device.
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    children: [
                      const Icon(Icons.wifi_off, size: 40),
                      const SizedBox(height: 16),
                      Text(
                        'No provisioning devices found.\n'
                        'If you are already connected to the Loki PSU via '
                        'Bluetooth, go back and reconnect, then return here.\n\n'
                        'Otherwise, ensure the Loki PSU is in provisioning '
                        'mode (advertising as PROV_LOKI_…).',
                        style: Theme.of(context).textTheme.bodyMedium,
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 8),
                      TextButton.icon(
                        onPressed: _startScan,
                        icon: const Icon(Icons.refresh),
                        label: const Text('Rescan'),
                      ),
                    ],
                  ),
                ),
              ),

            // Additional devices found via scan (PROV_LOKI_* advertisement).
            for (final r in _provDevices)
              _buildDeviceCard(
                device: r.device,
                subtitle: r.device.remoteId.toString(),
                rssi: r.rssi,
                isConnectedDevice: false,
              ),

            // Small progress indicator while scan is running alongside devices.
            if (_isScanning && _hasAnyDevice)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Row(
                  children: [
                    const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Scanning for additional devices…',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),

            const SizedBox(height: 24),

            // ---- Step 2: WiFi credentials ----
            Text(
              'Step 2: Enter WiFi Credentials',
              style: Theme.of(context)
                  .textTheme
                  .titleMedium!
                  .copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),

            TextField(
              controller: _ssidController,
              decoration: const InputDecoration(
                labelText: 'WiFi Network Name (SSID)',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.wifi),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _passwordController,
              decoration: InputDecoration(
                labelText: 'WiFi Password',
                border: const OutlineInputBorder(),
                prefixIcon: const Icon(Icons.lock_outlined),
                suffixIcon: IconButton(
                  icon: Icon(_obscurePassword
                      ? Icons.visibility
                      : Icons.visibility_off),
                  onPressed: () =>
                      setState(() => _obscurePassword = !_obscurePassword),
                ),
              ),
              obscureText: _obscurePassword,
            ),

            const SizedBox(height: 24),

            // ---- Step 3: Provision button ----
            StreamBuilder<ProvisioningStep>(
              stream: wifi.provisioningStepStream,
              initialData: wifi.provisioningStep,
              builder: (context, snapshot) {
                final step = snapshot.data ?? ProvisioningStep.idle;

                if (_provisioning) {
                  return Card(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        children: [
                          if (step != ProvisioningStep.success &&
                              step != ProvisioningStep.failed)
                            const CircularProgressIndicator(),
                          if (step == ProvisioningStep.success)
                            const Icon(Icons.check_circle,
                                color: Colors.green, size: 48),
                          if (step == ProvisioningStep.failed)
                            const Icon(Icons.error,
                                color: Colors.red, size: 48),
                          const SizedBox(height: 16),
                          Text(
                            _stepLabel(step),
                            style: Theme.of(context).textTheme.titleSmall,
                            textAlign: TextAlign.center,
                          ),
                          if (_result != null) ...[
                            const SizedBox(height: 8),
                            Text(
                              _result!.message,
                              style: Theme.of(context).textTheme.bodyMedium,
                              textAlign: TextAlign.center,
                            ),
                          ],
                          if (step == ProvisioningStep.success ||
                              step == ProvisioningStep.failed) ...[
                            const SizedBox(height: 16),
                            FilledButton(
                              onPressed: () {
                                if (_result?.success == true) {
                                  Navigator.of(context).pop(true);
                                } else {
                                  setState(() {
                                    _provisioning = false;
                                    _result = null;
                                  });
                                }
                              },
                              child: Text(_result?.success == true
                                  ? 'Done'
                                  : 'Try Again'),
                            ),
                          ],
                        ],
                      ),
                    ),
                  );
                }

                return FilledButton.icon(
                  onPressed: _canProvision() ? _startProvisioning : null,
                  icon: const Icon(Icons.wifi_protected_setup),
                  label: const Text('Start Provisioning'),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDeviceCard({
    required BluetoothDevice device,
    required String subtitle,
    required int? rssi,
    required bool isConnectedDevice,
  }) {
    final isSelected = _selectedDevice?.remoteId == device.remoteId;
    return Card(
      color: isSelected
          ? Theme.of(context).colorScheme.primaryContainer
          : null,
      child: ListTile(
        leading: Icon(
          isConnectedDevice ? Icons.bluetooth_connected : Icons.wifi_tethering,
        ),
        title: Row(
          children: [
            Flexible(
              child: Text(
                device.platformName.isNotEmpty
                    ? device.platformName
                    : device.remoteId.toString(),
              ),
            ),
            if (isConnectedDevice) ...[
              const SizedBox(width: 8),
              Chip(
                label: const Text('Connected'),
                padding: EdgeInsets.zero,
                labelPadding:
                    const EdgeInsets.symmetric(horizontal: 6),
                visualDensity: VisualDensity.compact,
                backgroundColor:
                    Theme.of(context).colorScheme.primaryContainer,
              ),
            ],
          ],
        ),
        subtitle: Text(
          rssi != null ? '$subtitle  ($rssi dBm)' : subtitle,
        ),
        trailing: isSelected
            ? const Icon(Icons.check_circle, color: Colors.green)
            : null,
        onTap: () => setState(() => _selectedDevice = device),
      ),
    );
  }

  bool _canProvision() {
    return _selectedDevice != null &&
        _ssidController.text.trim().isNotEmpty &&
        _passwordController.text.isNotEmpty &&
        !_provisioning;
  }

  Future<void> _startProvisioning() async {
    setState(() {
      _provisioning = true;
      _result = null;
    });

    final wifi = context.read<WiFiProvider>();
    final service = wifi.provisioningService;

    // Stop scanning before provisioning
    await service.stopScan();
    _scanSub?.cancel();

    final result = await service.provision(
      device: _selectedDevice!,
      ssid: _ssidController.text.trim(),
      password: _passwordController.text,
    );

    if (mounted) {
      setState(() => _result = result);

      // Refresh node list if provisioning succeeded
      if (result.success && wifi.isLoggedIn) {
        // Give the cloud a moment to register the new node
        await Future<void>.delayed(const Duration(seconds: 3));
        await wifi.refreshNodes();
      }
    }
  }

  String _stepLabel(ProvisioningStep step) {
    switch (step) {
      case ProvisioningStep.idle:
        return 'Ready';
      case ProvisioningStep.scanning:
        return 'Scanning...';
      case ProvisioningStep.connecting:
        return 'Connecting to device...';
      case ProvisioningStep.handshake:
        return 'Performing security handshake...';
      case ProvisioningStep.sendingCredentials:
        return 'Sending WiFi credentials...';
      case ProvisioningStep.waitingForConnection:
        return 'Waiting for device to connect to WiFi...';
      case ProvisioningStep.success:
        return 'Provisioning Successful!';
      case ProvisioningStep.failed:
        return 'Provisioning Failed';
    }
  }
}

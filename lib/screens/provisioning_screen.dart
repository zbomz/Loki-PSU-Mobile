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
///  1. Auto-detect the already-connected BLE device from BleProvider.
///  2. Connect + Security1 handshake + query the ESP32 for nearby Wi-Fi APs.
///  3. User selects an SSID from the paginated list.
///  4. User enters the password (if required) in the field below the list.
///  5. Provisioning runs (sends credentials → status polling).
///  6. Success or failure result.
class ProvisioningScreen extends StatefulWidget {
  const ProvisioningScreen({super.key});

  @override
  State<ProvisioningScreen> createState() => _ProvisioningScreenState();
}

class _ProvisioningScreenState extends State<ProvisioningScreen> {
  final _passwordController = TextEditingController();
  bool _obscurePassword = true;

  /// The device that is already connected via the main BleService/BleProvider.
  BluetoothDevice? _selectedDevice;

  /// Wi-Fi networks discovered by the ESP32.
  List<WifiAccessPoint> _wifiNetworks = [];
  WifiAccessPoint? _selectedNetwork;

  bool _isLoadingNetworks = false;
  String? _networkError;

  ProvisioningResult? _result;
  bool _provisioning = false;

  @override
  void initState() {
    super.initState();

    // Grab the already-connected device and immediately kick off the Wi-Fi scan.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final ble = context.read<BleProvider>();
      if (ble.isConnected && ble.connectedDevice != null) {
        setState(() => _selectedDevice = ble.connectedDevice);
        _loadNetworks();
      } else {
        setState(() {
          _networkError =
              'No Loki PSU connected via Bluetooth.\n'
              'Go back, connect to your device, then return here.';
        });
      }
    });
  }

  @override
  void dispose() {
    _passwordController.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Network loading
  // ---------------------------------------------------------------------------

  Future<void> _loadNetworks() async {
    if (_selectedDevice == null) return;

    setState(() {
      _isLoadingNetworks = true;
      _networkError = null;
      _wifiNetworks = [];
      _selectedNetwork = null;
    });

    final wifi = context.read<WiFiProvider>();
    final service = wifi.provisioningService;

    try {
      final networks = await service.scanWifiNetworks(_selectedDevice!);
      if (mounted) {
        setState(() {
          _wifiNetworks = networks;
          _isLoadingNetworks = false;
          if (networks.isEmpty) {
            _networkError = 'No Wi-Fi networks found. Tap refresh to try again.';
          }
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoadingNetworks = false;
          _networkError = e.toString().replaceFirst('Exception: ', '');
        });
      }
    }
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final wifi = context.watch<WiFiProvider>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('WiFi Provisioning'),
        actions: [
          if (!_provisioning)
            IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: 'Refresh networks',
              onPressed: _isLoadingNetworks ? null : _loadNetworks,
            ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ---- Network list ----
            _buildNetworkSection(),

            const SizedBox(height: 24),

            // ---- Password field ----
            if (_selectedNetwork != null || _wifiNetworks.isNotEmpty) ...[
              Text(
                'Password',
                style: Theme.of(context)
                    .textTheme
                    .titleMedium!
                    .copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _passwordController,
                decoration: InputDecoration(
                  labelText: _selectedNetwork?.authMode == 0
                      ? 'Password (open network — leave blank)'
                      : 'WiFi Password',
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
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 24),
            ],

            // ---- Provision button / progress ----
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
                  label: const Text('Connect'),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Network list section
  // ---------------------------------------------------------------------------

  Widget _buildNetworkSection() {
    // Loading state
    if (_isLoadingNetworks) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              const CircularProgressIndicator(),
              const SizedBox(height: 16),
              Text(
                'Scanning for Wi-Fi networks…',
                style: Theme.of(context).textTheme.bodyMedium,
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    // Error state (no networks loaded yet)
    if (_networkError != null && _wifiNetworks.isEmpty) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              const Icon(Icons.wifi_off, size: 40),
              const SizedBox(height: 16),
              Text(
                _networkError!,
                style: Theme.of(context).textTheme.bodyMedium,
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    // Network list
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Select Wi-Fi Network',
          style: Theme.of(context)
              .textTheme
              .titleMedium!
              .copyWith(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        ...(_wifiNetworks.map((ap) => _buildNetworkTile(ap))),
        if (_wifiNetworks.isNotEmpty && _networkError != null) ...[
          const SizedBox(height: 4),
          Text(
            _networkError!,
            style: Theme.of(context)
                .textTheme
                .bodySmall!
                .copyWith(color: Theme.of(context).colorScheme.error),
            textAlign: TextAlign.center,
          ),
        ],
      ],
    );
  }

  Widget _buildNetworkTile(WifiAccessPoint ap) {
    final isSelected = _selectedNetwork?.ssid == ap.ssid;
    final isOpen = ap.authMode == 0;

    return Card(
      color: isSelected
          ? Theme.of(context).colorScheme.primaryContainer
          : null,
      child: ListTile(
        leading: _wifiSignalIcon(ap.rssi),
        title: Text(ap.ssid),
        subtitle: Text(isOpen ? 'Open network' : 'Secured'),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!isOpen)
              const Icon(Icons.lock, size: 16),
            if (isSelected)
              const Padding(
                padding: EdgeInsets.only(left: 4),
                child: Icon(Icons.check_circle, color: Colors.green),
              ),
          ],
        ),
        onTap: _provisioning
            ? null
            : () {
                setState(() {
                  _selectedNetwork = ap;
                  // Clear password when switching networks
                  _passwordController.clear();
                });
              },
      ),
    );
  }

  /// Returns a Wi-Fi signal strength icon based on RSSI.
  Icon _wifiSignalIcon(int rssi) {
    if (rssi >= -55) return const Icon(Icons.signal_wifi_4_bar);
    if (rssi >= -70) return const Icon(Icons.network_wifi_3_bar);
    if (rssi >= -80) return const Icon(Icons.network_wifi_2_bar);
    return const Icon(Icons.network_wifi_1_bar);
  }

  // ---------------------------------------------------------------------------
  // Provisioning
  // ---------------------------------------------------------------------------

  bool _canProvision() {
    if (_selectedDevice == null || _selectedNetwork == null || _provisioning) {
      return false;
    }
    // Open networks don't require a password
    if (_selectedNetwork!.authMode != 0 &&
        _passwordController.text.isEmpty) {
      return false;
    }
    return true;
  }

  Future<void> _startProvisioning() async {
    setState(() {
      _provisioning = true;
      _result = null;
    });

    final wifi = context.read<WiFiProvider>();
    final service = wifi.provisioningService;

    final result = await service.provision(
      device: _selectedDevice!,
      ssid: _selectedNetwork!.ssid,
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

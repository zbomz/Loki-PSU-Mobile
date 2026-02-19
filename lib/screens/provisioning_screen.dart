import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:provider/provider.dart';

import '../providers/wifi_provider.dart';
import '../wifi/provisioning_service.dart';

/// WiFi provisioning screen.
///
/// Flow:
///  1. Scan for provisioning-capable devices (PROV_LOKI_*)
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

  List<ScanResult> _provDevices = [];
  BluetoothDevice? _selectedDevice;
  StreamSubscription<List<ScanResult>>? _scanSub;

  ProvisioningResult? _result;
  bool _provisioning = false;

  @override
  void initState() {
    super.initState();
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

    _scanSub?.cancel();
    _scanSub = service
        .scanForProvisionableDevices(timeout: const Duration(seconds: 10))
        .listen((results) {
      if (mounted) {
        setState(() => _provDevices = results);
      }
    });
  }

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

            if (_provDevices.isEmpty)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    children: [
                      const CircularProgressIndicator(),
                      const SizedBox(height: 16),
                      Text(
                        'Scanning for Loki PSU provisioning devices...',
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
              )
            else
              ...(_provDevices.map((r) => Card(
                    color: _selectedDevice == r.device
                        ? Theme.of(context)
                            .colorScheme
                            .primaryContainer
                        : null,
                    child: ListTile(
                      leading: const Icon(Icons.wifi_tethering),
                      title: Text(r.device.platformName),
                      subtitle: Text(
                          '${r.device.remoteId}  (${r.rssi} dBm)'),
                      trailing: _selectedDevice == r.device
                          ? const Icon(Icons.check_circle,
                              color: Colors.green)
                          : null,
                      onTap: () =>
                          setState(() => _selectedDevice = r.device),
                    ),
                  ))),

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

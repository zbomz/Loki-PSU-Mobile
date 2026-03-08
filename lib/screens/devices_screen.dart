import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/ble_provider.dart';
import '../services/device_history_service.dart';
import 'device_detail_screen.dart';
import 'scan_screen.dart';

/// Lists previously paired devices and the currently connected device.
/// Tapping a device navigates to its detail/control screen.
class DevicesScreen extends StatefulWidget {
  const DevicesScreen({super.key});

  @override
  State<DevicesScreen> createState() => _DevicesScreenState();
}

class _DevicesScreenState extends State<DevicesScreen> {
  final _historyService = DeviceHistoryService();
  List<PairedDevice> _pairedDevices = [];

  @override
  void initState() {
    super.initState();
    _loadDevices();
  }

  Future<void> _loadDevices() async {
    final devices = await _historyService.loadDevices();
    if (mounted) setState(() => _pairedDevices = devices);
  }

  @override
  Widget build(BuildContext context) {
    final ble = context.watch<BleProvider>();
    final connectedId = ble.connectedDevice?.remoteId.toString();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Devices'),
        actions: [
          IconButton(
            icon: const Icon(Icons.bluetooth_searching),
            tooltip: 'Scan for devices',
            onPressed: () async {
              await Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const ScanScreen()),
              );
              _loadDevices();
            },
          ),
        ],
      ),
      body: _pairedDevices.isEmpty
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.devices, size: 64,
                      color: Theme.of(context).colorScheme.outline),
                  const SizedBox(height: 16),
                  Text(
                    'No paired devices',
                    style: Theme.of(context).textTheme.bodyLarge,
                  ),
                  const SizedBox(height: 8),
                  FilledButton.tonal(
                    onPressed: () async {
                      await Navigator.of(context).push(
                        MaterialPageRoute(
                            builder: (_) => const ScanScreen()),
                      );
                      _loadDevices();
                    },
                    child: const Text('Scan for Devices'),
                  ),
                ],
              ),
            )
          : RefreshIndicator(
              onRefresh: _loadDevices,
              child: ListView.separated(
                padding: const EdgeInsets.symmetric(vertical: 8),
                itemCount: _pairedDevices.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final device = _pairedDevices[index];
                  final isConnected = device.remoteId == connectedId;
                  return ListTile(
                    leading: Icon(
                      Icons.power,
                      size: 32,
                      color: isConnected
                          ? Colors.green
                          : Theme.of(context).colorScheme.outline,
                    ),
                    title: Text(device.name),
                    subtitle: Text(
                      isConnected
                          ? 'Connected'
                          : 'Last connected ${_formatDate(device.lastConnected)}',
                    ),
                    trailing: isConnected
                        ? const Icon(Icons.chevron_right)
                        : null,
                    onTap: isConnected
                        ? () {
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                  builder: (_) =>
                                      const DeviceDetailScreen()),
                            );
                          }
                        : null,
                  );
                },
              ),
            ),
    );
  }

  String _formatDate(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inHours < 1) return '${diff.inMinutes}m ago';
    if (diff.inDays < 1) return '${diff.inHours}h ago';
    if (diff.inDays < 30) return '${diff.inDays}d ago';
    return '${dt.month}/${dt.day}/${dt.year}';
  }
}

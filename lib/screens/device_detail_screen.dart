import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../ble/ble_service.dart';
import '../models/psu_state.dart';
import '../protocol/common_protocol.dart';
import '../providers/ble_provider.dart';
import '../providers/psu_state_provider.dart';
import '../providers/wifi_provider.dart';
import 'settings_screen.dart';

/// Device detail / control screen — shows telemetry, toggles, value editors,
/// and commands for the connected Loki PSU. Extracted from the former
/// DashboardScreen.
class DeviceDetailScreen extends StatelessWidget {
  const DeviceDetailScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final ble = context.watch<BleProvider>();
    final psuProvider = context.watch<PsuStateProvider>();
    final wifi = context.watch<WiFiProvider>();

    final isCloudMode = wifi.activeTransport == ActiveTransport.cloud;
    final psu = isCloudMode ? wifi.cloudState : psuProvider.state;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Loki PSU'),
        actions: [
          _TransportChip(
            transport: wifi.activeTransport,
            bleState: ble.connectionState,
          ),
          const SizedBox(width: 8),
          IconButton(
            icon: const Icon(Icons.settings),
            tooltip: 'Settings',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const SettingsScreen()),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh all',
            onPressed: ble.isConnected
                ? () {
                    psuProvider.refreshTelemetry();
                    psuProvider.refreshAllConfigs();
                  }
                : null,
          ),
          IconButton(
            icon: const Icon(Icons.bluetooth_disabled),
            tooltip: 'Disconnect',
            onPressed: ble.isConnected
                ? () {
                    ble.disconnect();
                    Navigator.of(context).pop();
                  }
                : null,
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: !ble.isConnected && !isCloudMode
          ? const Center(child: Text('Not connected'))
          : psuProvider.loading
              ? const Center(child: CircularProgressIndicator())
              : ListView(
                  padding: const EdgeInsets.all(12),
                  children: [
                    if (psuProvider.error != null) ...[
                      Container(
                        padding: const EdgeInsets.all(8),
                        color: Colors.red.shade100,
                        child: Text(
                          psuProvider.error!,
                          style: TextStyle(color: Colors.red.shade900),
                        ),
                      ),
                      const SizedBox(height: 8),
                    ],

                    // Telemetry
                    const _SectionHeader(title: 'Telemetry'),
                    const SizedBox(height: 4),
                    _TelemetryGrid(psu: psu),

                    const SizedBox(height: 20),

                    // Toggles
                    const _SectionHeader(title: 'Configuration — Toggles'),
                    const SizedBox(height: 4),
                    _BoolConfigTile(
                      label: 'PSU Output Enable',
                      value: psu.outputEnable,
                      onChanged: (v) => psuProvider.writeBool(
                          ProtocolTag.psuOutputEnable, v),
                      info: 'Master power switch. When disabled, the PSU '
                          'immediately shuts down all output and clears '
                          'fault conditions. Does not persist across '
                          'reboots — the PSU always boots with output enabled.',
                    ),
                    _BoolConfigTile(
                      label: 'Voltage Regulation Enable',
                      value: psu.voltageRegulationEnable,
                      onChanged: (v) => psuProvider.writeBool(
                          ProtocolTag.psuVoltageRegulationEnable, v),
                      info: 'Controls the voltage regulation feedback loop. '
                          'When enabled, the PSU continuously adjusts PWM '
                          'duty cycle to maintain the target voltage. When '
                          'disabled, the duty cycle freezes and output '
                          'voltage will drift with load changes.',
                    ),
                    _BoolConfigTile(
                      label: 'Max Power Shutoff Enable',
                      value: psu.maxPowerShutoffEnable,
                      onChanged: (v) => psuProvider.writeBool(
                          ProtocolTag.psuMaxPowerShutoffEnable, v),
                      info: 'Safety feature that shuts down the PSU if power '
                          'consumption exceeds the configured threshold '
                          '(default 1320W). Prevents circuit breaker trips '
                          'and electrical hazards. Highly recommended to '
                          'keep enabled.',
                    ),
                    _BoolConfigTile(
                      label: 'Thermostat Enable',
                      value: psu.thermostatEnable,
                      onChanged: (v) => psuProvider.writeBool(
                          ProtocolTag.psuThermostatEnable, v),
                      info: 'Monitors inlet air temperature and disables the '
                          'PSU if it exceeds the target temperature. Uses '
                          '1°C hysteresis to prevent oscillation. Useful for '
                          'controlling ambient temperature in enclosed spaces.',
                    ),
                    _BoolConfigTile(
                      label: 'Fan Silence Enable',
                      value: psu.silenceFanEnable,
                      onChanged: (v) => psuProvider.writeBool(
                          ProtocolTag.psuSilenceFanEnable, v),
                      info: 'Reduces PSU fan speed for quieter operation by '
                          'pulling down the fan control voltage. Warning: '
                          'this disables the PSU\'s hardware over-temperature '
                          'protection, so software OTP is automatically '
                          'enabled and cannot be turned off while this is on.',
                    ),
                    _BoolConfigTile(
                      label: 'Spoof Above Max Voltage Enable',
                      value: psu.spoofAboveMaxVoltageEnable,
                      onChanged: (v) => psuProvider.writeBool(
                          ProtocolTag.spoofAboveMaxOutputVoltageEnable, v),
                      info: 'When a miner requests voltage above the PSU\'s '
                          'hardware maximum (13.9V), the PSU clamps to 13.9V '
                          'internally. With this enabled, the PSU echoes back '
                          'the requested voltage to the miner. When disabled, '
                          'it reports the actual clamped voltage.',
                    ),
                    _BoolConfigTile(
                      label: 'Auto Retry After Fault Enable',
                      value: psu.autoRetryAfterFaultEnable,
                      onChanged: (v) => psuProvider.writeBool(
                          ProtocolTag.automaticRetryAfterPowerFaultEnable, v),
                      info: 'Automatically restarts the PSU after a power '
                          'fault (non-thermal) once the configured timeout '
                          'elapses. Does not retry during OTP or thermostat '
                          'faults. Useful for recovering from transient '
                          'power issues without manual intervention.',
                    ),
                    _BoolConfigTile(
                      label: 'OTP Enable',
                      value: psu.otpEnable,
                      onChanged: (v) =>
                          psuProvider.writeBool(ProtocolTag.psuOtpEnable, v),
                      info: 'Software over-temperature protection. Shuts down '
                          'the PSU if internal temperature exceeds the '
                          'threshold (default 75°C), and re-enables when it '
                          'drops 7°C below. Cannot be disabled while Fan '
                          'Silence is enabled — it is the only thermal '
                          'protection in that mode.',
                    ),

                    const SizedBox(height: 20),

                    // Float values
                    const _SectionHeader(title: 'Configuration — Values'),
                    const SizedBox(height: 4),
                    _PickerConfigTile(
                      label: 'Target Output Voltage',
                      value: psu.targetOutputVoltage,
                      unit: 'V',
                      min: 11.9,
                      max: 13.9,
                      step: 0.1,
                      decimals: 1,
                      onChanged: (v) => psuProvider.writeFloat(
                          ProtocolTag.psuTargetOutputVoltage, v),
                      info: 'The voltage setpoint the PSU regulates to when '
                          'voltage regulation is enabled. The PSU adjusts '
                          'PWM duty cycle to maintain this voltage under '
                          'varying load conditions.',
                    ),
                    _PickerConfigTile(
                      label: 'Max Power Threshold',
                      value: psu.maxPowerThreshold,
                      unit: 'W',
                      min: 100,
                      max: 1450,
                      step: 10,
                      decimals: 0,
                      onChanged: (v) => psuProvider.writeFloat(
                          ProtocolTag.maxPsuOutputPowerThreshold, v),
                      info: 'The power limit used by Max Power Shutoff. If '
                          'measured power exceeds this value, the PSU shuts '
                          'down. Default is 1320W (110V x 15A x 0.8 safety '
                          'factor). Maximum allowed is 1920W.',
                    ),
                    _PickerConfigTile(
                      label: 'Target Inlet Temperature',
                      value: psu.targetInletTemperature,
                      unit: '°C',
                      min: -20,
                      max: 50,
                      step: 1,
                      decimals: 0,
                      onChanged: (v) => psuProvider.writeFloat(
                          ProtocolTag.targetPsuInletTemperature, v),
                      info: 'The temperature setpoint used by the thermostat. '
                          'When inlet air temperature exceeds this value by '
                          '1°C, the PSU shuts down. It re-enables when '
                          'temperature drops 1°C below. Range: -20°C to 50°C. '
                          'Default: 21°C.',
                    ),
                    _PickerConfigTile(
                      label: 'Power Fault Timeout',
                      value: psu.powerFaultTimeout,
                      unit: 's',
                      min: 1,
                      max: 86400,
                      step: 1,
                      decimals: 0,
                      onChanged: (v) => psuProvider.writeFloat(
                          ProtocolTag.powerFaultTimeout, v),
                      info: 'How long to wait before automatically restarting '
                          'the PSU after a power fault, when Auto Retry is '
                          'enabled. Range: 1 second to 86,400 seconds '
                          '(24 hours). Default: 10 seconds.',
                    ),
                    _PickerConfigTile(
                      label: 'OTP Threshold',
                      value: psu.otpThreshold,
                      unit: '°C',
                      min: 40,
                      max: 85,
                      step: 1,
                      decimals: 0,
                      onChanged: (v) => psuProvider.writeFloat(
                          ProtocolTag.psuOtpThreshold, v),
                      info: 'The internal temperature at which OTP shuts down '
                          'the PSU. The PSU re-enables when temperature drops '
                          '7°C below this threshold (hysteresis). Range: 40°C '
                          'to 85°C. Default: 75°C.',
                    ),

                    const SizedBox(height: 20),

                    // Model / FW
                    const _SectionHeader(title: 'Configuration — Model / FW'),
                    const SizedBox(height: 4),
                    _Uint8ConfigTile(
                      label: 'Spoofed HW Model',
                      value: psu.spoofedHardwareModel,
                      onEdit: (v) => psuProvider.writeUint8(
                          ProtocolTag.spoofedPsuHardwareModel, v),
                      info: 'The hardware model byte reported to the miner '
                          'over the Bitmain I2C protocol. Different models '
                          'affect how the miner interprets PSU capabilities. '
                          'Default: 0x75.',
                    ),
                    _Uint8ConfigTile(
                      label: 'Spoofed FW Version',
                      value: psu.spoofedFirmwareVersion,
                      onEdit: (v) => psuProvider.writeUint8(
                          ProtocolTag.spoofedPsuFirmwareVersion, v),
                      info: 'The firmware version byte reported to the miner '
                          'over the Bitmain I2C protocol. Some miners check '
                          'this for compatibility. Default: 0x16.',
                    ),

                    const SizedBox(height: 20),

                    // Commands
                    const _SectionHeader(title: 'Commands'),
                    const SizedBox(height: 4),
                    Card(
                      child: ListTile(
                        leading: const Icon(Icons.restart_alt),
                        title: Row(
                          children: [
                            const Expanded(
                                child: Text('Reset Energy Counter')),
                            GestureDetector(
                              onTap: () => showDialog(
                                context: context,
                                builder: (ctx) => AlertDialog(
                                  title: const Text('Reset Energy Counter'),
                                  content: const Text(
                                    'Resets the cumulative energy counter '
                                    '(Wh) back to zero. This counter tracks '
                                    'total energy delivered since last reset. '
                                    'The counter does not persist across '
                                    'reboots.',
                                  ),
                                  actions: [
                                    TextButton(
                                      onPressed: () => Navigator.pop(ctx),
                                      child: const Text('OK'),
                                    ),
                                  ],
                                ),
                              ),
                              child: Icon(
                                Icons.info_outline,
                                size: 20,
                                color: Theme.of(context).colorScheme.outline,
                              ),
                            ),
                          ],
                        ),
                        subtitle: const Text('Set kWh counter back to 0'),
                        trailing: FilledButton.tonal(
                          onPressed: ble.isConnected
                              ? () => psuProvider.resetEnergyCounter()
                              : null,
                          child: const Text('RESET'),
                        ),
                      ),
                    ),

                    const SizedBox(height: 40),
                  ],
                ),
    );
  }
}

// =============================================================================
// Reusable sub-widgets (moved from dashboard_screen.dart)
// =============================================================================

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader({required this.title});

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: Theme.of(context)
          .textTheme
          .titleMedium!
          .copyWith(fontWeight: FontWeight.bold),
    );
  }
}

class _TransportChip extends StatelessWidget {
  final ActiveTransport transport;
  final BleConnectionState bleState;
  const _TransportChip({required this.transport, required this.bleState});

  @override
  Widget build(BuildContext context) {
    final (label, icon, color) = switch (transport) {
      ActiveTransport.cloud => ('Cloud', Icons.cloud, Colors.blue),
      ActiveTransport.ble => switch (bleState) {
          BleConnectionState.disconnected =>
            ('BLE Off', Icons.bluetooth_disabled, Colors.grey),
          BleConnectionState.connecting =>
            ('BLE...', Icons.bluetooth_searching, Colors.orange),
          BleConnectionState.connected =>
            ('BLE', Icons.bluetooth_connected, Colors.green),
        },
      ActiveTransport.none => switch (bleState) {
          BleConnectionState.disconnected =>
            ('Offline', Icons.signal_wifi_off, Colors.grey),
          BleConnectionState.connecting =>
            ('BLE...', Icons.bluetooth_searching, Colors.orange),
          BleConnectionState.connected =>
            ('BLE', Icons.bluetooth_connected, Colors.green),
        },
    };
    return Chip(
      avatar: Icon(icon, size: 16, color: color),
      label: Text(label, style: const TextStyle(fontSize: 12)),
      backgroundColor: color.withValues(alpha: 0.2),
      side: BorderSide(color: color),
      padding: EdgeInsets.zero,
      visualDensity: VisualDensity.compact,
    );
  }
}

// Telemetry grid

class _TelemetryGrid extends StatelessWidget {
  final PsuState psu;
  const _TelemetryGrid({required this.psu});

  @override
  Widget build(BuildContext context) {
    final items = [
      _TelemetryItem('Output Voltage', psu.outputVoltage, 'V'),
      _TelemetryItem('Output Current', psu.outputCurrent, 'A'),
      _TelemetryItem('Output Power', psu.outputPower, 'W'),
      _TelemetryItem('Inlet Temp', psu.inletTemperature, '°C'),
      _TelemetryItem('Internal Temp', psu.internalTemperature, '°C'),
      _TelemetryItem('Energy', psu.energyWh, 'Wh'),
    ];

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        childAspectRatio: 2.4,
        mainAxisSpacing: 6,
        crossAxisSpacing: 6,
      ),
      itemCount: items.length,
      itemBuilder: (context, index) {
        final item = items[index];
        return Card(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  item.label,
                  style: Theme.of(context).textTheme.bodySmall,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  item.value != null
                      ? '${item.value!.toStringAsFixed(2)} ${item.unit}'
                      : '--',
                  style: Theme.of(context)
                      .textTheme
                      .titleLarge!
                      .copyWith(fontFamily: 'monospace'),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _TelemetryItem {
  final String label;
  final double? value;
  final String unit;
  _TelemetryItem(this.label, this.value, this.unit);
}

// Bool config tile

class _BoolConfigTile extends StatelessWidget {
  final String label;
  final bool? value;
  final ValueChanged<bool> onChanged;
  final String? info;

  const _BoolConfigTile({
    required this.label,
    required this.value,
    required this.onChanged,
    this.info,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: SwitchListTile(
        title: Text(label),
        subtitle: Row(
          children: [
            Text(value == null ? '--' : (value! ? 'ON' : 'OFF')),
            if (info != null) ...[
              const SizedBox(width: 8),
              GestureDetector(
                onTap: () => showDialog(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: Text(label),
                    content: Text(info!),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(ctx),
                        child: const Text('OK'),
                      ),
                    ],
                  ),
                ),
                child: Icon(
                  Icons.info_outline,
                  size: 18,
                  color: Theme.of(context).colorScheme.outline,
                ),
              ),
            ],
          ],
        ),
        value: value ?? false,
        onChanged: value != null ? onChanged : null,
      ),
    );
  }
}

// Float config tile

class _PickerConfigTile extends StatelessWidget {
  final String label;
  final double? value;
  final String unit;
  final double min;
  final double max;
  final double step;
  final int decimals;
  final ValueChanged<double> onChanged;
  final String? info;

  const _PickerConfigTile({
    required this.label,
    required this.value,
    required this.unit,
    required this.min,
    required this.max,
    required this.step,
    required this.decimals,
    required this.onChanged,
    this.info,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        title: Text(label),
        subtitle: Row(
          children: [
            Text(
              value != null
                  ? '${value!.toStringAsFixed(decimals)} $unit'
                  : '--',
              style: const TextStyle(fontFamily: 'monospace'),
            ),
            if (info != null) ...[
              const SizedBox(width: 8),
              GestureDetector(
                onTap: () => showDialog(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: Text(label),
                    content: Text(info!),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(ctx),
                        child: const Text('OK'),
                      ),
                    ],
                  ),
                ),
                child: Icon(
                  Icons.info_outline,
                  size: 18,
                  color: Theme.of(context).colorScheme.outline,
                ),
              ),
            ],
          ],
        ),
        trailing: const Icon(Icons.edit),
        onTap: value != null
            ? () async {
                final result = await _showWheelPicker(
                  context: context,
                  label: label,
                  unit: unit,
                  currentValue: value!,
                  min: min,
                  max: max,
                  step: step,
                  decimals: decimals,
                );
                if (result != null) onChanged(result);
              }
            : null,
      ),
    );
  }
}

Future<double?> _showWheelPicker({
  required BuildContext context,
  required String label,
  required String unit,
  required double currentValue,
  required double min,
  required double max,
  required double step,
  required int decimals,
}) async {
  final itemCount = ((max - min) / step).round() + 1;
  final initialIndex =
      ((currentValue.clamp(min, max) - min) / step).round();
  final controller =
      FixedExtentScrollController(initialItem: initialIndex);
  double selectedValue = currentValue.clamp(min, max);

  return showModalBottomSheet<double>(
    context: context,
    builder: (ctx) => SizedBox(
      height: 320,
      child: Column(
        children: [
          Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                OutlinedButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Cancel'),
                ),
                Text(label,
                    style: Theme.of(context).textTheme.titleMedium),
                OutlinedButton(
                  onPressed: () => Navigator.pop(ctx, selectedValue),
                  child: const Text('Set'),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: Stack(
              alignment: Alignment.center,
              children: [
                // Selection highlight band
                Positioned(
                  left: 24,
                  right: 24,
                  height: 42,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: Theme.of(context)
                          .colorScheme
                          .primary
                          .withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: Theme.of(context)
                            .colorScheme
                            .primary
                            .withValues(alpha: 0.3),
                      ),
                    ),
                  ),
                ),
                ListWheelScrollView.useDelegate(
                  controller: controller,
                  itemExtent: 42,
                  diameterRatio: 1.2,
                  physics: const FixedExtentScrollPhysics(),
                  onSelectedItemChanged: (index) {
                    selectedValue = min + index * step;
                    HapticFeedback.selectionClick();
                  },
                  childDelegate: ListWheelChildBuilderDelegate(
                    childCount: itemCount,
                    builder: (context, index) {
                      final v = min + index * step;
                      return Center(
                        child: Text(
                          '${v.toStringAsFixed(decimals)} $unit',
                          style: Theme.of(context)
                              .textTheme
                              .titleLarge!
                              .copyWith(fontFamily: 'monospace'),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

// Uint8 config tile

class _Uint8ConfigTile extends StatelessWidget {
  final String label;
  final int? value;
  final ValueChanged<int> onEdit;
  final String? info;

  const _Uint8ConfigTile({
    required this.label,
    required this.value,
    required this.onEdit,
    this.info,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        title: Text(label),
        subtitle: Row(
          children: [
            Text(
              value != null
                  ? '0x${value!.toRadixString(16).padLeft(2, '0').toUpperCase()}'
                  : '--',
              style: const TextStyle(fontFamily: 'monospace'),
            ),
            if (info != null) ...[
              const SizedBox(width: 8),
              GestureDetector(
                onTap: () => showDialog(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: Text(label),
                    content: Text(info!),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(ctx),
                        child: const Text('OK'),
                      ),
                    ],
                  ),
                ),
                child: Icon(
                  Icons.info_outline,
                  size: 18,
                  color: Theme.of(context).colorScheme.outline,
                ),
              ),
            ],
          ],
        ),
        trailing: IconButton(
          icon: const Icon(Icons.edit),
          onPressed: value != null
              ? () => _showUint8EditDialog(context, label, value!, onEdit)
              : null,
        ),
      ),
    );
  }
}

Future<void> _showUint8EditDialog(
  BuildContext context,
  String label,
  int currentValue,
  ValueChanged<int> onSave,
) async {
  final controller = TextEditingController(
    text: '0x${currentValue.toRadixString(16).padLeft(2, '0').toUpperCase()}',
  );

  final result = await showDialog<int>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text('Edit $label'),
      content: TextField(
        controller: controller,
        decoration: InputDecoration(
          labelText: label,
          hintText: '0x00 - 0xFF',
          border: const OutlineInputBorder(),
        ),
        autofocus: true,
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('CANCEL'),
        ),
        FilledButton(
          onPressed: () {
            final text = controller.text.trim();
            int? val;
            if (text.startsWith('0x') || text.startsWith('0X')) {
              val = int.tryParse(text.substring(2), radix: 16);
            } else {
              val = int.tryParse(text);
            }
            if (val != null && val >= 0 && val <= 255) {
              Navigator.pop(ctx, val);
            }
          },
          child: const Text('SAVE'),
        ),
      ],
    ),
  );

  if (result != null) {
    onSave(result);
  }
}

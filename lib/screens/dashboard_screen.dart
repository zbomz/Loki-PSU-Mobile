import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../ble/ble_service.dart';
import '../models/psu_state.dart';
import '../protocol/common_protocol.dart';
import '../providers/ble_provider.dart';
import '../providers/psu_state_provider.dart';

/// Wireframe dashboard that shows all telemetry points, config values,
/// and command actions for the connected Loki PSU.
class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final ble = context.watch<BleProvider>();
    final psuProvider = context.watch<PsuStateProvider>();
    final psu = psuProvider.state;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Loki PSU — Dashboard'),
        actions: [
          _ConnectionChip(state: ble.connectionState),
          const SizedBox(width: 8),
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
      body: !ble.isConnected
          ? const Center(child: Text('Not connected'))
          : psuProvider.loading
              ? const Center(child: CircularProgressIndicator())
              : ListView(
                  padding: const EdgeInsets.all(12),
                  children: [
                    // Error banner
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

                    // ---- Telemetry ----
                    const _SectionHeader(title: 'Telemetry'),
                    const SizedBox(height: 4),
                    _TelemetryGrid(psu: psu),

                    const SizedBox(height: 20),

                    // ---- Configuration — Toggles ----
                    const _SectionHeader(title: 'Configuration — Toggles'),
                    const SizedBox(height: 4),
                    _BoolConfigTile(
                      label: 'PSU Output Enable',
                      value: psu.outputEnable,
                      onChanged: (v) => psuProvider.writeBool(
                          ProtocolTag.psuOutputEnable, v),
                    ),
                    _BoolConfigTile(
                      label: 'Voltage Regulation Enable',
                      value: psu.voltageRegulationEnable,
                      onChanged: (v) => psuProvider.writeBool(
                          ProtocolTag.psuVoltageRegulationEnable, v),
                    ),
                    _BoolConfigTile(
                      label: 'Max Power Shutoff Enable',
                      value: psu.maxPowerShutoffEnable,
                      onChanged: (v) => psuProvider.writeBool(
                          ProtocolTag.psuMaxPowerShutoffEnable, v),
                    ),
                    _BoolConfigTile(
                      label: 'Thermostat Enable',
                      value: psu.thermostatEnable,
                      onChanged: (v) => psuProvider.writeBool(
                          ProtocolTag.psuThermostatEnable, v),
                    ),
                    _BoolConfigTile(
                      label: 'Fan Silence Enable',
                      value: psu.silenceFanEnable,
                      onChanged: (v) => psuProvider.writeBool(
                          ProtocolTag.psuSilenceFanEnable, v),
                    ),
                    _BoolConfigTile(
                      label: 'Spoof Above Max Voltage Enable',
                      value: psu.spoofAboveMaxVoltageEnable,
                      onChanged: (v) => psuProvider.writeBool(
                          ProtocolTag.spoofAboveMaxOutputVoltageEnable, v),
                    ),
                    _BoolConfigTile(
                      label: 'Auto Retry After Fault Enable',
                      value: psu.autoRetryAfterFaultEnable,
                      onChanged: (v) => psuProvider.writeBool(
                          ProtocolTag.automaticRetryAfterPowerFaultEnable, v),
                    ),
                    _BoolConfigTile(
                      label: 'OTP Enable',
                      value: psu.otpEnable,
                      onChanged: (v) =>
                          psuProvider.writeBool(ProtocolTag.psuOtpEnable, v),
                    ),

                    const SizedBox(height: 20),

                    // ---- Configuration — Float values ----
                    const _SectionHeader(title: 'Configuration — Values'),
                    const SizedBox(height: 4),
                    _FloatConfigTile(
                      label: 'Target Output Voltage',
                      value: psu.targetOutputVoltage,
                      unit: 'V',
                      onEdit: (v) => psuProvider.writeFloat(
                          ProtocolTag.psuTargetOutputVoltage, v),
                    ),
                    _FloatConfigTile(
                      label: 'Max Power Threshold',
                      value: psu.maxPowerThreshold,
                      unit: 'W',
                      onEdit: (v) => psuProvider.writeFloat(
                          ProtocolTag.maxPsuOutputPowerThreshold, v),
                    ),
                    _FloatConfigTile(
                      label: 'Target Inlet Temperature',
                      value: psu.targetInletTemperature,
                      unit: '°C',
                      onEdit: (v) => psuProvider.writeFloat(
                          ProtocolTag.targetPsuInletTemperature, v),
                    ),
                    _FloatConfigTile(
                      label: 'Power Fault Timeout',
                      value: psu.powerFaultTimeout,
                      unit: 's',
                      onEdit: (v) => psuProvider.writeFloat(
                          ProtocolTag.powerFaultTimeout, v),
                    ),
                    _FloatConfigTile(
                      label: 'OTP Threshold',
                      value: psu.otpThreshold,
                      unit: '°C',
                      onEdit: (v) => psuProvider.writeFloat(
                          ProtocolTag.psuOtpThreshold, v),
                    ),

                    const SizedBox(height: 20),

                    // ---- Configuration — Uint8 selectors ----
                    const _SectionHeader(title: 'Configuration — Model / FW'),
                    const SizedBox(height: 4),
                    _Uint8ConfigTile(
                      label: 'Spoofed HW Model',
                      value: psu.spoofedHardwareModel,
                      onEdit: (v) => psuProvider.writeUint8(
                          ProtocolTag.spoofedPsuHardwareModel, v),
                    ),
                    _Uint8ConfigTile(
                      label: 'Spoofed FW Version',
                      value: psu.spoofedFirmwareVersion,
                      onEdit: (v) => psuProvider.writeUint8(
                          ProtocolTag.spoofedPsuFirmwareVersion, v),
                    ),

                    const SizedBox(height: 20),

                    // ---- Commands ----
                    const _SectionHeader(title: 'Commands'),
                    const SizedBox(height: 4),
                    Card(
                      child: ListTile(
                        leading: const Icon(Icons.restart_alt),
                        title: const Text('Reset Energy Counter'),
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
// Reusable sub-widgets
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
      backgroundColor: color.withValues(alpha: 0.2),
      side: BorderSide(color: color),
      padding: EdgeInsets.zero,
      visualDensity: VisualDensity.compact,
    );
  }
}

// -----------------------------------------------------------------------------
// Telemetry grid
// -----------------------------------------------------------------------------

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

// -----------------------------------------------------------------------------
// Bool config tile (Switch)
// -----------------------------------------------------------------------------

class _BoolConfigTile extends StatelessWidget {
  final String label;
  final bool? value;
  final ValueChanged<bool> onChanged;

  const _BoolConfigTile({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: SwitchListTile(
        title: Text(label),
        subtitle: Text(value == null ? '--' : (value! ? 'ON' : 'OFF')),
        value: value ?? false,
        onChanged: value != null ? onChanged : null,
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// Float config tile (tap to edit)
// -----------------------------------------------------------------------------

class _FloatConfigTile extends StatelessWidget {
  final String label;
  final double? value;
  final String unit;
  final ValueChanged<double> onEdit;

  const _FloatConfigTile({
    required this.label,
    required this.value,
    required this.unit,
    required this.onEdit,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        title: Text(label),
        subtitle: Text(
          value != null ? '${value!.toStringAsFixed(2)} $unit' : '--',
          style: const TextStyle(fontFamily: 'monospace'),
        ),
        trailing: IconButton(
          icon: const Icon(Icons.edit),
          onPressed: value != null
              ? () => _showEditDialog(context, label, value!, unit, onEdit)
              : null,
        ),
      ),
    );
  }
}

Future<void> _showEditDialog(
  BuildContext context,
  String label,
  double currentValue,
  String unit,
  ValueChanged<double> onSave,
) async {
  final controller =
      TextEditingController(text: currentValue.toStringAsFixed(2));

  final result = await showDialog<double>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text('Edit $label'),
      content: TextField(
        controller: controller,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: InputDecoration(
          labelText: label,
          suffixText: unit,
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
            final val = double.tryParse(controller.text);
            if (val != null) {
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

// -----------------------------------------------------------------------------
// Uint8 config tile (tap to edit with hex display)
// -----------------------------------------------------------------------------

class _Uint8ConfigTile extends StatelessWidget {
  final String label;
  final int? value;
  final ValueChanged<int> onEdit;

  const _Uint8ConfigTile({
    required this.label,
    required this.value,
    required this.onEdit,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        title: Text(label),
        subtitle: Text(
          value != null ? '0x${value!.toRadixString(16).padLeft(2, '0').toUpperCase()}' : '--',
          style: const TextStyle(fontFamily: 'monospace'),
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

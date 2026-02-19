import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/wifi_provider.dart';
import '../wifi/rainmaker_constants.dart';
import 'auth_screen.dart';
import 'provisioning_screen.dart';

/// Settings screen for WiFi / cloud connectivity management.
///
/// Sections:
///  - **Cloud Account**: Login status, sign in / sign out
///  - **WiFi Provisioning**: Provision a device with WiFi credentials
///  - **Remote Configuration**: Toggle allow_remote_config on the device
///  - **Node Selection**: Choose which node to monitor (if multiple)
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final wifi = context.watch<WiFiProvider>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
      ),
      body: ListView(
        children: [
          // ---- Cloud Account ----
          const _SectionHeader(title: 'Cloud Account'),
          if (wifi.isLoggedIn) ...[
            ListTile(
              leading: const Icon(Icons.person),
              title: Text(wifi.userEmail ?? 'Unknown'),
              subtitle: const Text('Signed in'),
              trailing: FilledButton.tonal(
                onPressed: () async {
                  final confirm = await showDialog<bool>(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      title: const Text('Sign Out'),
                      content: const Text(
                          'Sign out of your RainMaker account? '
                          'You will lose remote monitoring access.'),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(ctx, false),
                          child: const Text('Cancel'),
                        ),
                        FilledButton(
                          onPressed: () => Navigator.pop(ctx, true),
                          child: const Text('Sign Out'),
                        ),
                      ],
                    ),
                  );
                  if (confirm == true) {
                    await wifi.logout();
                  }
                },
                child: const Text('Sign Out'),
              ),
            ),
          ] else ...[
            ListTile(
              leading: const Icon(Icons.cloud_off),
              title: const Text('Not signed in'),
              subtitle: const Text(
                  'Sign in to enable remote monitoring and control'),
              trailing: FilledButton.tonal(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => const AuthScreen()),
                  );
                },
                child: const Text('Sign In'),
              ),
            ),
          ],

          const Divider(),

          // ---- WiFi Provisioning ----
          const _SectionHeader(title: 'WiFi Provisioning'),
          ListTile(
            leading: const Icon(Icons.wifi_protected_setup),
            title: const Text('Provision Device WiFi'),
            subtitle: const Text(
                'Connect your Loki PSU to a WiFi network over BLE'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => const ProvisioningScreen()),
              );
            },
          ),

          const Divider(),

          // ---- Active Transport ----
          const _SectionHeader(title: 'Communication Mode'),
          ListTile(
            leading: Icon(
              wifi.activeTransport == ActiveTransport.cloud
                  ? Icons.cloud
                  : Icons.bluetooth,
              color: wifi.activeTransport == ActiveTransport.cloud
                  ? Colors.blue
                  : Colors.blueGrey,
            ),
            title: Text(
              wifi.activeTransport == ActiveTransport.cloud
                  ? 'Cloud (Remote)'
                  : 'BLE (Local)',
            ),
            subtitle: Text(
              wifi.activeTransport == ActiveTransport.cloud
                  ? 'Monitoring via RainMaker cloud API'
                  : 'Direct BLE connection to device',
            ),
          ),
          if (wifi.isLoggedIn && wifi.isCloudAvailable)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: SegmentedButton<ActiveTransport>(
                segments: const [
                  ButtonSegment(
                    value: ActiveTransport.ble,
                    label: Text('BLE'),
                    icon: Icon(Icons.bluetooth),
                  ),
                  ButtonSegment(
                    value: ActiveTransport.cloud,
                    label: Text('Cloud'),
                    icon: Icon(Icons.cloud),
                  ),
                ],
                selected: {wifi.activeTransport},
                onSelectionChanged: (selected) {
                  wifi.setActiveTransport(selected.first);
                },
              ),
            ),
          if (!wifi.isLoggedIn || !wifi.isCloudAvailable)
            Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Text(
                !wifi.isLoggedIn
                    ? 'Sign in to enable cloud mode.'
                    : 'No nodes found. Provision a device first.',
                style: Theme.of(context)
                    .textTheme
                    .bodySmall!
                    .copyWith(color: Theme.of(context).colorScheme.outline),
              ),
            ),

          const Divider(),

          // ---- Remote Configuration Gate ----
          const _SectionHeader(title: 'Remote Configuration'),
          if (wifi.cloudState.allowRemoteConfig != null)
            SwitchListTile(
              secondary: const Icon(Icons.admin_panel_settings),
              title: const Text('Allow Remote Config'),
              subtitle: const Text(
                  'When enabled, cloud API can write configuration '
                  'parameters. Disable for local-only control.'),
              value: wifi.cloudState.allowRemoteConfig ?? false,
              onChanged: (value) {
                wifi.writeCloudParam(
                    RainMakerConstants.paramAllowRemoteConfig,
                    value);
              },
            )
          else
            const ListTile(
              leading: Icon(Icons.admin_panel_settings),
              title: Text('Allow Remote Config'),
              subtitle: Text(
                  'Connect to a device to see the current setting. '
                  'This can only be changed over BLE for security.'),
            ),

          const Divider(),

          // ---- Node Selection ----
          if (wifi.nodeIds.length > 1) ...[
            const _SectionHeader(title: 'Node Selection'),
            ...wifi.nodeIds.map((nodeId) => RadioListTile<String>(
                  title: Text(nodeId),
                  value: nodeId,
                  groupValue: wifi.selectedNodeId,
                  onChanged: (val) {
                    if (val != null) wifi.selectNode(val);
                  },
                )),
            const Divider(),
          ],

          // ---- Cloud status ----
          if (wifi.cloudError != null)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Card(
                color: Colors.red.shade50,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      Icon(Icons.warning_amber,
                          color: Colors.red.shade700),
                      const SizedBox(width: 8),
                      Expanded(
                          child: Text(wifi.cloudError!,
                              style: TextStyle(
                                  color: Colors.red.shade900))),
                    ],
                  ),
                ),
              ),
            ),

          const SizedBox(height: 32),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader({required this.title});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Text(
        title,
        style: Theme.of(context).textTheme.labelLarge!.copyWith(
              color: Theme.of(context).colorScheme.primary,
              fontWeight: FontWeight.bold,
            ),
      ),
    );
  }
}

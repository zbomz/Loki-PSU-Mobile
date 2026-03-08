import 'package:flutter/material.dart';

/// Placeholder for the Home tab — will display historical device data
/// fetched from the Espressif RainMaker backend once API wrappers are built.
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Home'),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.timeline,
                  size: 64,
                  color: Theme.of(context).colorScheme.outline),
              const SizedBox(height: 16),
              Text(
                'Historical Data',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              Text(
                'Device history and analytics will appear here once '
                'the RainMaker data API is integrated.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.outline,
                    ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'ble/ble_service.dart';
import 'providers/ble_provider.dart';
import 'providers/psu_state_provider.dart';
import 'screens/scan_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const LokiPsuApp());
}

class LokiPsuApp extends StatefulWidget {
  const LokiPsuApp({super.key});

  @override
  State<LokiPsuApp> createState() => _LokiPsuAppState();
}

class _LokiPsuAppState extends State<LokiPsuApp> {
  // Single shared BLE service instance.
  late final BleService _bleService;

  @override
  void initState() {
    super.initState();
    _bleService = BleService();
  }

  @override
  void dispose() {
    _bleService.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(
          create: (_) => BleProvider(_bleService),
        ),
        ChangeNotifierProvider(
          create: (_) => PsuStateProvider(_bleService),
        ),
      ],
      child: MaterialApp(
        title: 'Loki PSU',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          colorSchemeSeed: Colors.blueGrey,
          useMaterial3: true,
          brightness: Brightness.light,
        ),
        darkTheme: ThemeData(
          colorSchemeSeed: Colors.blueGrey,
          useMaterial3: true,
          brightness: Brightness.dark,
        ),
        themeMode: ThemeMode.system,
        home: const ScanScreen(),
      ),
    );
  }
}

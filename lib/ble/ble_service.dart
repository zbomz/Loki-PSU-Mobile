import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import '../protocol/tlv_codec.dart';
import 'ble_constants.dart';
import 'security1_session.dart';

/// Connection state exposed to the rest of the app.
enum BleConnectionState { disconnected, connecting, connected }

/// Low-level BLE service that wraps flutter_blue_plus for the Loki PSU.
///
/// Responsibilities:
///  - Scan for Loki PSU devices
///  - Connect / disconnect
///  - Subscribe to TLV response notifications
///  - Send TLV requests and await the response with timeout + retry
class BleService {
  BluetoothDevice? _device;
  BluetoothCharacteristic? _requestChar;
  BluetoothCharacteristic? _responseChar;

  StreamSubscription<List<int>>? _notifySub;
  StreamSubscription<BluetoothConnectionState>? _connectionSub;

  /// Continuously updated Bluetooth adapter state for faster scan response
  BluetoothAdapterState _cachedAdapterState = BluetoothAdapterState.unknown;
  StreamSubscription<BluetoothAdapterState>? _adapterStateSub;

  /// Completer that gets completed when a notification arrives.
  Completer<Uint8List>? _responseCompleter;

  /// Async lock to serialize BLE requests.  The firmware processes one
  /// request at a time and uses a single response completer, so concurrent
  /// calls to [sendRequest] must be queued.
  Future<void>? _requestLock;

  /// Constructor that continuously monitors the Bluetooth adapter state
  BleService() {
    _startAdapterStateMonitor();
  }

  /// Listen to adapter state changes so we always have the latest state cached.
  /// On iOS the first event is typically 'unknown', then 'on' once CoreBluetooth
  /// finishes initializing.  By listening continuously the cache reflects the
  /// real state by the time the user taps Scan.
  void _startAdapterStateMonitor() {
    try {
      _adapterStateSub = FlutterBluePlus.adapterState.listen(
        (state) {
          _cachedAdapterState = state;
        },
        onError: (_) {
          // Platform not supported (e.g. tests) — ignore
        },
      );
    } catch (_) {
      // Platform not supported (e.g. tests) — ignore
    }
  }

  BleConnectionState _state = BleConnectionState.disconnected;
  BleConnectionState get state => _state;

  /// Stream controller so providers can listen to connection state changes.
  final _stateController =
      StreamController<BleConnectionState>.broadcast();
  Stream<BleConnectionState> get stateStream => _stateController.stream;

  /// The currently connected device (null if disconnected).
  BluetoothDevice? get connectedDevice => _device;

  // ---------------------------------------------------------------------------
  // Scanning
  // ---------------------------------------------------------------------------

  /// Start scanning for BLE devices. Returns a stream of scan results.
  Stream<List<ScanResult>> get scanResults => FlutterBluePlus.scanResults;

  /// Whether the adapter is currently scanning.
  bool get isScanning => FlutterBluePlus.isScanningNow;

  Future<void> startScan({Duration timeout = const Duration(seconds: 5)}) async {
    BluetoothAdapterState adapterState = _cachedAdapterState;
    
    // If the cached state is still unknown, give the adapter a short window
    // to become ready (up to 3 seconds).  The continuous listener will have
    // already resolved this in most cases, so this is just a safety net.
    if (adapterState == BluetoothAdapterState.unknown) {
      adapterState = await FlutterBluePlus.adapterState
          .firstWhere((state) => state != BluetoothAdapterState.unknown)
          .timeout(
            const Duration(seconds: 3),
            onTimeout: () => BluetoothAdapterState.unknown,
          );
    }
    
    if (adapterState == BluetoothAdapterState.unknown) {
      throw Exception(
        'Bluetooth is not ready. Please wait a moment and try again.'
      );
    }
    
    if (adapterState != BluetoothAdapterState.on) {
      throw Exception(
        'Bluetooth must be turned on. Current state: ${adapterState.name}'
      );
    }

    // Scan without a service UUID filter — the Loki TLV service UUID is no
    // longer included in advertising packets (the RainMaker provisioning scheme
    // controls advertising). Devices are identified by name prefix instead.
    await FlutterBluePlus.startScan(timeout: timeout);
  }

  Future<void> stopScan() async {
    await FlutterBluePlus.stopScan();
  }

  // ---------------------------------------------------------------------------
  // Connection
  // ---------------------------------------------------------------------------

  Future<void> connect(BluetoothDevice device) async {
    _setState(BleConnectionState.connecting);

    try {
      // Listen for disconnection events.
      _connectionSub = device.connectionState.listen((s) {
        if (s == BluetoothConnectionState.disconnected) {
          _onDisconnected();
        }
      });

      await device.connect(license: License.free, autoConnect: false);
      _device = device;

      // Request a larger MTU for telemetry bundle responses.
      // Note: MTU request is Android-only. iOS negotiates MTU automatically.
      if (Platform.isAndroid) {
        await device.requestMtu(BleConstants.requestedMtu);
      }

      // Discover services and locate characteristics.
      final services = await device.discoverServices();

      // The unified protocomm_nimble BLE stack on the ESP32 requires a
      // Security1 session to be established before the firmware will allow
      // any GATT operations (including notification subscriptions) on
      // non-provisioning characteristics.  Perform the handshake now; if the
      // prov-session characteristic is absent (older firmware) the call is a
      // no-op.
      try {
        await Security1Session.establish(services);
      } catch (e) {
        // Non-fatal: if the handshake fails the connection may still work on
        // firmware that does not enforce session-first gating.
        print('Security1 session establish hint failed (non-fatal): $e');
      }

      final lokiService = services.firstWhere(
        (s) => s.serviceUuid == BleConstants.serviceUuid,
        orElse: () =>
            throw Exception('Loki PSU service not found on device'),
      );

      _requestChar = lokiService.characteristics.firstWhere(
        (c) => c.characteristicUuid == BleConstants.requestCharUuid,
        orElse: () =>
            throw Exception('TLV Request characteristic not found'),
      );

      _responseChar = lokiService.characteristics.firstWhere(
        (c) => c.characteristicUuid == BleConstants.responseCharUuid,
        orElse: () =>
            throw Exception('TLV Response characteristic not found'),
      );

      // Subscribe to notifications on the response characteristic.
      await _responseChar!.setNotifyValue(true);
      _notifySub = _responseChar!.onValueReceived.listen(_onNotification);

      _setState(BleConnectionState.connected);
    } catch (e) {
      await _cleanup();
      _setState(BleConnectionState.disconnected);
      rethrow;
    }
  }

  Future<void> disconnect() async {
    try {
      await _device?.disconnect();
    } finally {
      await _cleanup();
      _setState(BleConnectionState.disconnected);
    }
  }

  // ---------------------------------------------------------------------------
  // TLV Request / Response
  // ---------------------------------------------------------------------------

  /// Send a raw TLV request and return the parsed [TlvResponse].
  ///
  /// Retries up to [BleConstants.maxRetries] times on timeout or CRC error.
  /// Concurrent callers are serialized so only one request is in flight at
  /// a time (the firmware and response completer are single-threaded).
  Future<TlvResponse> sendRequest(Uint8List request) async {
    if (_state != BleConnectionState.connected || _requestChar == null) {
      throw StateError('Not connected to a Loki PSU device');
    }

    // Wait for any in-flight request to finish before starting ours.
    final prev = _requestLock;
    final gate = Completer<void>();
    _requestLock = gate.future;

    if (prev != null) {
      await prev;
    }

    try {
      return await _sendRequestInternal(request);
    } finally {
      gate.complete();
    }
  }

  /// Internal send without locking — called only from [sendRequest].
  Future<TlvResponse> _sendRequestInternal(Uint8List request) async {
    for (int attempt = 0; attempt < BleConstants.maxRetries; attempt++) {
      try {
        _responseCompleter = Completer<Uint8List>();

        await _requestChar!.write(request.toList(), withoutResponse: false);

        final rawResponse = await _responseCompleter!.future
            .timeout(BleConstants.requestTimeout);

        return TlvResponseParser.parse(rawResponse);
      } on TimeoutException {
        // Retry on timeout.
        continue;
      } on FormatException catch (e) {
        // CRC mismatch or parse error — retry.
        if (attempt == BleConstants.maxRetries - 1) rethrow;
        print('TLV parse error (attempt ${attempt + 1}): $e');
        continue;
      }
    }

    throw TimeoutException(
        'No response after ${BleConstants.maxRetries} attempts');
  }

  // ---------------------------------------------------------------------------
  // Private helpers
  // ---------------------------------------------------------------------------

  void _onNotification(List<int> data) {
    if (_responseCompleter != null && !_responseCompleter!.isCompleted) {
      _responseCompleter!.complete(Uint8List.fromList(data));
    }
  }

  void _onDisconnected() {
    _cleanup();
    _setState(BleConnectionState.disconnected);
  }

  Future<void> _cleanup() async {
    await _notifySub?.cancel();
    _notifySub = null;
    await _connectionSub?.cancel();
    _connectionSub = null;
    _requestChar = null;
    _responseChar = null;
    _device = null;
    if (_responseCompleter != null && !_responseCompleter!.isCompleted) {
      _responseCompleter!.completeError(
          StateError('Disconnected while waiting for response'));
    }
    _responseCompleter = null;
  }

  void _setState(BleConnectionState newState) {
    _state = newState;
    _stateController.add(newState);
  }

  void dispose() {
    _adapterStateSub?.cancel();
    _cleanup();
    _stateController.close();
  }
}

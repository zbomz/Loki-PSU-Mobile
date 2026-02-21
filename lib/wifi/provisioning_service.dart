import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import '../ble/ble_constants.dart';
import 'rainmaker_constants.dart';

/// Provisioning progress stages shown to the user.
enum ProvisioningStep {
  idle,
  scanning,
  connecting,
  handshake,
  sendingCredentials,
  waitingForConnection,
  success,
  failed,
}

/// Result of a provisioning attempt.
class ProvisioningResult {
  final bool success;
  final String message;
  ProvisioningResult({required this.success, required this.message});
}

/// A Wi-Fi access point discovered by the ESP32 during provisioning.
class WifiAccessPoint {
  final String ssid;
  final int rssi;
  final int authMode; // 0 = open, non-zero = secured
  WifiAccessPoint({
    required this.ssid,
    required this.rssi,
    required this.authMode,
  });
}

/// Service that handles WiFi provisioning of the ESP32-C3 over BLE.
///
/// Implements the ESP Unified Provisioning protocol (Security1):
///  1. Use the already-connected "Loki PSU-XXXX" BLE device (no separate scan)
///  2. Curve25519 key exchange + PoP-derived AES key
///  3. Send WiFi SSID + password (encrypted)
///  4. Poll for WiFi connection status
///
/// Architecture note: this firmware exposes both the Loki TLV service and the
/// ESP Unified Provisioning GATT service (ff50/ff51/ff52) on a single unified
/// "Loki PSU-XXXX" BLE advertisement.  There is no separate "PROV_LOKI_…"
/// provisioning-mode advertisement.  The provisioning handler remains active
/// permanently (endProvision() is never called after credential success), so
/// WiFi provisioning is always available on the telemetry connection.
///
/// Uses [flutter_blue_plus] for BLE transport and [cryptography] for crypto.
class ProvisioningService {
  BluetoothDevice? _device;
  BluetoothCharacteristic? _sessionChar;
  BluetoothCharacteristic? _configChar;
  BluetoothCharacteristic? _scanChar;
  StreamSubscription<BluetoothConnectionState>? _connectionSub;

  /// True when [provision] connected the device itself. False when the device
  /// was already connected (e.g. by the main BleService for telemetry).
  /// Only used by [_cleanup] to decide whether to call disconnect().
  bool _weConnected = false;

  /// AES cipher key derived from Curve25519 shared secret XOR SHA256(PoP).
  Uint8List? _cipherKey;

  /// AES-CTR nonce: the 16-byte device_random from SessionResp0.
  /// ESP-IDF Security1 uses device_random as the initial nonce/counter for
  /// all AES-CTR operations in the session.
  Uint8List? _nonce;

  /// Running byte count into the AES-CTR keystream for this session.
  /// The ESP Security1 AES-CTR state is stateful across all encrypt/decrypt
  /// calls within a session; we track the position here so every call starts
  /// at the correct keystream offset.
  int _cipherByteCount = 0;

  final _stepController = StreamController<ProvisioningStep>.broadcast();
  Stream<ProvisioningStep> get stepStream => _stepController.stream;

  ProvisioningStep _currentStep = ProvisioningStep.idle;
  ProvisioningStep get currentStep => _currentStep;

  void _setStep(ProvisioningStep step) {
    _currentStep = step;
    _stepController.add(step);
  }

  // ---------------------------------------------------------------------------
  // Scanning for provisioning-capable devices
  // ---------------------------------------------------------------------------

  /// Scan for ESP32 devices advertising the Loki PSU service.
  ///
  /// Returns a stream of filtered scan results whose device name starts with
  /// [BleConstants.deviceNamePrefix] (e.g. "Loki PSU-A1B2C3"). The stream
  /// closes automatically when [timeout] elapses. Any error (BT off,
  /// permission denied, conflicting scan) is forwarded through the stream so
  /// callers can surface it in the UI.
  Stream<List<ScanResult>> scanForProvisionableDevices({
    Duration timeout = const Duration(seconds: 10),
  }) {
    _setStep(ProvisioningStep.scanning);

    final controller = StreamController<List<ScanResult>>();

    Future<void> performScan() async {
      try {
        // Stop any in-progress scan to avoid conflicts with the main BLE scan.
        await FlutterBluePlus.stopScan();

        // Guard: wait for the adapter to be ready (mirrors BleService.startScan).
        final adapterState = await FlutterBluePlus.adapterState
            .firstWhere((s) => s != BluetoothAdapterState.unknown)
            .timeout(
              const Duration(seconds: 3),
              onTimeout: () => BluetoothAdapterState.unknown,
            );

        if (adapterState != BluetoothAdapterState.on) {
          throw Exception(
            'Bluetooth is not ready. Current state: ${adapterState.name}',
          );
        }

        // Subscribe to results *before* starting the scan so no packet is missed.
        final sub = FlutterBluePlus.scanResults.listen(
          (results) {
            final filtered = results.where((r) {
              // Filter by the Loki PSU device name prefix.  The provisioning
              // service is always available on the same "Loki PSU-XXXX"
              // advertisement used for telemetry — no separate PROV_LOKI_
              // mode exists in this firmware.
              return r.device.platformName
                  .startsWith(BleConstants.deviceNamePrefix);
            }).toList();
            if (!controller.isClosed) controller.add(filtered);
          },
          onError: (Object e) {
            if (!controller.isClosed) controller.addError(e);
          },
        );

        // Await startScan so any startup error surfaces as an exception
        // rather than being silently swallowed.
        await FlutterBluePlus.startScan(timeout: timeout);

        // startScan future completes once the timeout has elapsed.
        await sub.cancel();
      } catch (e) {
        if (!controller.isClosed) controller.addError(e);
      } finally {
        if (!controller.isClosed) controller.close();
      }
    }

    performScan(); // errors travel through the StreamController
    return controller.stream;
  }

  Future<void> stopScan() async {
    await FlutterBluePlus.stopScan();
  }

  // ---------------------------------------------------------------------------
  // Wi-Fi network scan (via prov-scan GATT characteristic)
  // ---------------------------------------------------------------------------

  /// Connect to [device] (if needed), perform the Security1 handshake, then
  /// ask the ESP32 to scan for nearby Wi-Fi access points.
  ///
  /// Returns a deduplicated list sorted by signal strength (strongest first).
  /// The BLE session is kept alive (cipher key cached) so a subsequent call
  /// to [provision] can skip the handshake step.
  Future<List<WifiAccessPoint>> scanWifiNetworks(
    BluetoothDevice device, {
    String pop = RainMakerConstants.provPop,
    Duration scanTimeout = const Duration(seconds: 10),
  }) async {
    _device = device;

    // Diagnostic trace — accumulates step-by-step so any error message
    // includes a full picture of how far we got.
    final diag = StringBuffer();

    String charInfo(BluetoothCharacteristic c) {
      final p = c.properties;
      return '${c.characteristicUuid} '
          '[R=${p.read} W=${p.write} WNR=${p.writeWithoutResponse} N=${p.notify}]';
    }

    try {
      // ---- 1. Connect if not already connected ----
      _weConnected = !device.isConnected;
      diag.writeln('1. connected=${device.isConnected}, weConnect=$_weConnected');
      if (_weConnected) {
        _connectionSub = device.connectionState.listen((s) {
          if (s == BluetoothConnectionState.disconnected) {
            _cleanup();
          }
        });
        await device.connect(license: License.free, autoConnect: false);
        diag.writeln('   connect() done');
      }

      // ---- 2. Find provisioning characteristics ----
      final services = await device.discoverServices();
      diag.writeln('2. discoverServices: ${services.length} services');
      for (final svc in services) {
        diag.writeln('   svc ${svc.serviceUuid}');
        for (final c in svc.characteristics) {
          diag.writeln('     ${charInfo(c)}');
        }
      }

      _findProvisioningCharacteristics(services);
      _findScanCharacteristic(services);

      diag.writeln('   session=${_sessionChar != null ? charInfo(_sessionChar!) : "null"}');
      diag.writeln('   config=${_configChar != null ? charInfo(_configChar!) : "null"}');
      diag.writeln('   scan=${_scanChar != null ? charInfo(_scanChar!) : "null"}');

      if (_sessionChar == null || _configChar == null) {
        throw Exception(
          'ESP provisioning characteristics not found.\n\n$diag',
        );
      }

      // ---- 3. Security1 handshake (establishes _cipherKey) ----
      _setStep(ProvisioningStep.handshake);
      diag.writeln('3. handshake start');
      try {
        await _performSecurity1Handshake(pop);
      } on FlutterBluePlusException catch (e) {
        diag.writeln('   FAILED: $e');
        throw Exception(
          'BLE error during Security1 handshake.\n\n'
          'Detail: $e\n\n$diag',
        );
      }
      diag.writeln('   handshake OK, cipherKey=${_cipherKey!.length} bytes');

      // ---- 4. Start Wi-Fi scan on the ESP32 ----
      final cmdScanStart = Uint8List.fromList([
        ..._protoVarint(1, 0), // msg type = TypeCmdScanStart
        ..._protoBytes(
          10,
          Uint8List.fromList([
            ..._protoVarint(1, 0), // blocking = false
            ..._protoVarint(2, 0), // passive = false
            ..._protoVarint(3, 0), // group_channels = 0
            ..._protoVarint(4, 120), // period_ms = 120
          ]),
        ),
      ]);

      final scanChar = _scanChar ?? _configChar!;
      diag.writeln('4. scanChar=${charInfo(scanChar)} '
          '(using ${_scanChar != null ? "prov-scan" : "prov-config"})');

      try {
        final encrypted = await _aesCtrEncrypt(cmdScanStart, _cipherKey!);
        diag.writeln('   CmdScanStart encrypted: ${encrypted.length} bytes');
        await scanChar.write(encrypted.toList());
        diag.writeln('   CmdScanStart write OK');
      } on FlutterBluePlusException catch (e) {
        diag.writeln('   CmdScanStart FAILED: $e');
        throw Exception(
          'BLE write failed sending Wi-Fi scan start command.\n\n'
          'Detail: $e\n\n$diag',
        );
      }

      // Read and decrypt the RespScanStart response.
      // ESP-IDF protocomm uses a single AES-CTR keystream for both decrypt
      // (incoming requests) and encrypt (outgoing responses).  The firmware
      // advanced the counter when it encrypted RespScanStart, so the app
      // MUST decrypt it to keep its own counter in sync — otherwise every
      // subsequent encrypt/decrypt will produce garbage.
      try {
        final respStartEnc = Uint8List.fromList(await scanChar.read());
        final respStartRaw =
            await _aesCtrDecrypt(respStartEnc, _cipherKey!);
        diag.writeln('   RespScanStart: ${respStartRaw.length} bytes');
      } on Exception catch (e) {
        diag.writeln('   RespScanStart read FAILED: $e');
        // Non-fatal: if the read fails, the keystream may be desynchronised
        // but we still try polling.
      }

      // ---- 5. Poll until scan is finished ----
      diag.writeln('5. polling scan status');
      final deadline = DateTime.now().add(scanTimeout);
      int apCount = 0;
      int pollCount = 0;
      while (DateTime.now().isBefore(deadline)) {
        final cmdStatus = Uint8List.fromList([
          ..._protoVarint(1, 2), // msg type = TypeCmdScanStatus
          ..._protoBytes(12, Uint8List(0)), // empty CmdScanStatus {}
        ]);

        try {
          await scanChar.write(
            (await _aesCtrEncrypt(cmdStatus, _cipherKey!)).toList(),
          );
        } on FlutterBluePlusException catch (e) {
          diag.writeln('   poll $pollCount write FAILED: $e');
          throw Exception(
            'BLE write failed polling Wi-Fi scan status.\n\n'
            'Detail: $e\n\n$diag',
          );
        }

        final respEncrypted = Uint8List.fromList(await scanChar.read());
        final respRaw = await _aesCtrDecrypt(respEncrypted, _cipherKey!);
        final respStatus = _protoFindBytes(respRaw, 13);
        if (respStatus != null) {
          final finished = _protoFindVarint(respStatus, 1);
          final count = _protoFindVarint(respStatus, 2);
          if (finished == 1) {
            apCount = count ?? 0;
            diag.writeln('   scan done after $pollCount polls, $apCount APs');
            break;
          }
        }
        pollCount++;
        await Future<void>.delayed(const Duration(milliseconds: 500));
      }

      if (apCount == 0) {
        diag.writeln('   no APs found');
        return [];
      }

      // ---- 6. Fetch results in batches of 4 ----
      diag.writeln('6. fetching $apCount results');
      const batchSize = 4;
      final seen = <String>{};
      final results = <WifiAccessPoint>[];

      for (int startIndex = 0; startIndex < apCount; startIndex += batchSize) {
        final count =
            (startIndex + batchSize > apCount) ? apCount - startIndex : batchSize;

        final cmdResult = Uint8List.fromList([
          ..._protoVarint(1, 4), // msg type = TypeCmdScanResult
          ..._protoBytes(
            14,
            Uint8List.fromList([
              ..._protoVarint(1, startIndex),
              ..._protoVarint(2, count),
            ]),
          ),
        ]);

        try {
          await scanChar.write(
            (await _aesCtrEncrypt(cmdResult, _cipherKey!)).toList(),
          );
        } on FlutterBluePlusException catch (e) {
          diag.writeln('   fetch batch $startIndex write FAILED: $e');
          throw Exception(
            'BLE write failed fetching Wi-Fi scan results.\n\n'
            'Detail: $e\n\n$diag',
          );
        }

        final respEncrypted = Uint8List.fromList(await scanChar.read());
        final respRaw = await _aesCtrDecrypt(respEncrypted, _cipherKey!);
        final respResult = _protoFindBytes(respRaw, 15);
        if (respResult == null) continue;

        _parseWifiScanEntries(respResult, seen, results);
      }

      results.sort((a, b) => b.rssi.compareTo(a.rssi));
      diag.writeln('   returning ${results.length} unique networks');
      return results;
    } catch (e) {
      // Clean up stale state so the next attempt starts fresh.
      _sessionChar = null;
      _configChar = null;
      _scanChar = null;
      _cipherKey = null;
      _nonce = null;
      _cipherByteCount = 0;
      rethrow;
    }
  }

  /// Parse all repeated `WiFiScanResult` entries from a `RespScanResult` blob.
  void _parseWifiScanEntries(
    Uint8List data,
    Set<String> seen,
    List<WifiAccessPoint> out,
  ) {
    int offset = 0;
    while (offset < data.length) {
      final (tag, afterTag) = _decodeVarint(data, offset);
      if (afterTag < 0) break;
      offset = afterTag;

      final fieldNumber = tag >> 3;
      final wireType = tag & 0x07;

      if (wireType == 2) {
        final (length, dataOffset) = _decodeVarint(data, offset);
        if (dataOffset < 0) break;
        offset = dataOffset;

        if (fieldNumber == 1) {
          // This is one WiFiScanResult entry
          final entry = Uint8List.sublistView(data, offset, offset + length);
          // ssid = field 1 (bytes), channel = field 2, rssi = field 3 (varint, signed),
          // bssid = field 4, auth = field 5 (varint)
          final ssidBytes = _protoFindBytes(entry, 1);
          final rssiRaw = _protoFindVarint(entry, 3);
          final auth = _protoFindVarint(entry, 5) ?? 0;

          if (ssidBytes != null && ssidBytes.isNotEmpty) {
            final ssid = utf8.decode(ssidBytes, allowMalformed: true).trim();
            // rssi is encoded as a signed 32-bit varint; treat values > 127
            // as negative using two's complement for 32 bits.
            int rssi = rssiRaw ?? -100;
            if (rssi > 127) rssi = rssi - 256;

            if (ssid.isNotEmpty && !seen.contains(ssid)) {
              seen.add(ssid);
              out.add(WifiAccessPoint(ssid: ssid, rssi: rssi, authMode: auth));
            }
          }
        }
        offset += length;
      } else if (wireType == 0) {
        final (_, nextOffset) = _decodeVarint(data, offset);
        if (nextOffset < 0) break;
        offset = nextOffset;
      } else {
        break;
      }
    }
  }

  // ---------------------------------------------------------------------------
  // Full provisioning flow
  // ---------------------------------------------------------------------------

  /// Run the complete provisioning flow:
  ///  1. Connect to [device]
  ///  2. Security1 handshake (Curve25519 + PoP)
  ///  3. Send WiFi [ssid] and [password]
  ///  4. Poll until device reports WiFi connected or fails
  Future<ProvisioningResult> provision({
    required BluetoothDevice device,
    required String ssid,
    required String password,
    String pop = RainMakerConstants.provPop,
    Duration statusPollTimeout = const Duration(seconds: 30),
  }) async {
    try {
      // ---- 1. Connect (if not already connected) ----
      // The provisioning GATT service (ff50/ff51/ff52) is always present on
      // the "Loki PSU-XXXX" advertisement alongside the Loki TLV service.
      // No mode check is needed — provisioning is always available.
      _setStep(ProvisioningStep.connecting);
      _device = device;

      // The device may already be connected (e.g. for telemetry via BleService).
      // BLE devices don't appear in scan results when connected, so the
      // provisioning screen surfaces them from BleProvider directly.
      // Calling connect() on an already-connected device throws on iOS/Android,
      // so we only connect when truly disconnected.
      _weConnected = !device.isConnected;
      if (_weConnected) {
        _connectionSub = device.connectionState.listen((s) {
          if (s == BluetoothConnectionState.disconnected) {
            _cleanup();
          }
        });
        await device.connect(license: License.free, autoConnect: false);
      }

      // Discover services only if characteristics are not already cached from
      // a prior scanWifiNetworks() call.
      if (_sessionChar == null || _configChar == null) {
        // Always re-discover services for provisioning to avoid stale iOS
        // GATT cache issues.
        final services = await device.discoverServices();

        // Find the provisioning GATT characteristics.
        // ESP Unified Provisioning uses a custom service with characteristics
        // named by descriptor or by short UUID pattern.
        _findProvisioningCharacteristics(services);

        if (_sessionChar == null || _configChar == null) {
          // Build a diagnostic list of what was actually found so the developer
          // and the user can see whether the device exposed any services at all.
          final foundServices = services
              .map((s) => s.serviceUuid.toString())
              .join(', ');
          final foundChars = services
              .expand((s) => s.characteristics)
              .map((c) => c.characteristicUuid.toString())
              .join(', ');
          throw Exception(
            'ESP provisioning GATT service not found on this device.\n\n'
            'The provisioning characteristics (ff50/ff51/ff52) were not '
            'discovered. This may indicate a firmware issue or a stale iOS '
            'GATT cache — try disconnecting and reconnecting the device.\n\n'
            'Services found: ${foundServices.isEmpty ? "none" : foundServices}\n'
            'Characteristics found: ${foundChars.isEmpty ? "none" : foundChars}',
          );
        }
      }

      // ---- 2. Security1 handshake ----
      // Skipped when scanWifiNetworks() already established the session key.
      if (_cipherKey == null) {
        _setStep(ProvisioningStep.handshake);
        try {
          await _performSecurity1Handshake(pop);
        } on FlutterBluePlusException catch (e) {
          throw Exception(
            'BLE communication error during the Security1 handshake.\n\n'
            'Make sure the device is powered on and within BLE range, '
            'then try again.\n\n'
            'Detail: $e',
          );
        }
      }

      // ---- 3. Send WiFi credentials ----
      _setStep(ProvisioningStep.sendingCredentials);
      await _sendWifiCredentials(ssid, password);

      // ---- 4. Poll status ----
      _setStep(ProvisioningStep.waitingForConnection);
      final connected =
          await _pollWifiStatus(timeout: statusPollTimeout);

      if (connected) {
        _setStep(ProvisioningStep.success);
        return ProvisioningResult(
          success: true,
          message: 'WiFi provisioning successful! Device connected to $ssid.',
        );
      } else {
        _setStep(ProvisioningStep.failed);
        return ProvisioningResult(
          success: false,
          message: 'Device failed to connect to $ssid. '
              'Please check your WiFi password and try again.',
        );
      }
    } catch (e) {
      _setStep(ProvisioningStep.failed);
      return ProvisioningResult(
        success: false,
        message: 'Provisioning error: $e',
      );
    } finally {
      await _cleanup();
    }
  }

  // ---------------------------------------------------------------------------
  // GATT characteristic discovery
  // ---------------------------------------------------------------------------

  /// Locate the provisioning session and config characteristics.
  ///
  /// The ESP Unified Provisioning BLE transport exposes characteristics
  /// with well-known descriptor values:
  ///  - `prov-session` — Security handshake
  ///  - `prov-config`  — WiFi config (set SSID/password, get status)
  ///  - `proto-ver`    — Protocol version (optional)
  void _findProvisioningCharacteristics(List<BluetoothService> services) {
    // Log all discovered services/characteristics for diagnostics.
    for (final service in services) {
      print('  Service: ${service.serviceUuid}');
      for (final char in service.characteristics) {
        print('    Char: ${char.characteristicUuid}'
            ' props: R=${char.properties.read}'
            ' W=${char.properties.write}'
            ' WNR=${char.properties.writeWithoutResponse}'
            ' N=${char.properties.notify}');
      }
    }

    for (final service in services) {
      for (final char in service.characteristics) {
        // ESP provisioning uses custom 128-bit UUIDs.
        // The characteristic purpose is identified by UUID substring:
        //   prov-scan:    contains 'ff50'
        //   prov-session: contains 'ff51'
        //   prov-config:  contains 'ff52'
        //   proto-ver:    contains 'ff53'  (not used by the app)
        final uuid = char.characteristicUuid.toString().toLowerCase();
        if (uuid.contains('ff50')) {
          _scanChar = char;
        } else if (uuid.contains('ff51')) {
          _sessionChar = char;
        } else if (uuid.contains('ff52')) {
          _configChar = char;
        }
      }
    }

    // NOTE: No fallback guessing.  If the provisioning characteristics aren't
    // found by UUID, something is wrong (firmware issue or stale GATT cache).
    // Writing to randomly-picked characteristics from other services (GAP,
    // DIS, etc.) causes apple-code 4 errors and firmware disconnections.
    if (_sessionChar != null) {
      print('Found prov-session: ${_sessionChar!.characteristicUuid}');
    }
    if (_configChar != null) {
      print('Found prov-config: ${_configChar!.characteristicUuid}');
    }
    if (_scanChar != null) {
      print('Found prov-scan: ${_scanChar!.characteristicUuid}');
    }
  }

  /// Locate the prov-scan characteristic (UUID containing `ff50`) within
  /// already-discovered services.  Called after [_findProvisioningCharacteristics].
  void _findScanCharacteristic(List<BluetoothService> services) {
    if (_scanChar != null) return; // already found during primary discovery
    for (final service in services) {
      for (final char in service.characteristics) {
        final uuid = char.characteristicUuid.toString().toLowerCase();
        if (uuid.contains('ff50')) {
          _scanChar = char;
          return;
        }
      }
    }
  }

  // ---------------------------------------------------------------------------
  // Security1 handshake
  // ---------------------------------------------------------------------------

  /// Perform the Security1 Curve25519 + PoP key exchange.
  ///
  /// 1. Generate client Curve25519 keypair
  /// 2. Send client public key (SessionCmd0)
  /// 3. Receive device public key + device random (SessionResp0)
  /// 4. Compute shared secret, derive AES key with PoP
  /// 5. Send encrypted verification (SessionCmd1)
  /// 6. Receive verification response (SessionResp1)
  Future<void> _performSecurity1Handshake(String pop) async {
    final algorithm = X25519();

    // Step 1: Generate client keypair
    final clientKeyPair = await algorithm.newKeyPair();
    final clientPublicKey = await clientKeyPair.extractPublicKey();
    final clientPublicKeyBytes =
        Uint8List.fromList(clientPublicKey.bytes);

    // Step 2: Send SessionCmd0 (client public key)
    final cmd0 = _buildSessionCmd0(clientPublicKeyBytes);
    await _sessionChar!.write(cmd0.toList());

    // Step 3: Read SessionResp0 (device public key + device random)
    final resp0Raw = await _sessionChar!.read();
    final resp0 = Uint8List.fromList(resp0Raw);
    final (devicePublicKeyBytes, deviceRandom) = _parseSessionResp0(resp0);

    // Step 4: Compute shared secret
    final devicePublicKey =
        SimplePublicKey(devicePublicKeyBytes, type: KeyPairType.x25519);
    final sharedSecret =
        await algorithm.sharedSecretKey(
            keyPair: clientKeyPair, remotePublicKey: devicePublicKey);
    final sharedSecretBytes =
        Uint8List.fromList(await sharedSecret.extractBytes());

    // Derive AES key: shared_secret XOR SHA256(pop)
    // ESP-IDF Security1 XORs the raw shared secret with the SHA-256 hash of
    // the Proof-of-Possession string.  It does NOT concatenate + hash.
    final sha256 = Sha256();
    final popBytes = utf8.encode(pop);
    final popHash = await sha256.hash(popBytes);
    final popHashBytes = Uint8List.fromList(popHash.bytes);
    final symKey = Uint8List(32);
    for (int i = 0; i < 32; i++) {
      symKey[i] = sharedSecretBytes[i] ^ popHashBytes[i];
    }
    _cipherKey = symKey;

    // Set the AES-CTR nonce to device_random (16 bytes) and reset the
    // keystream byte counter.  ESP-IDF uses device_random as the initial
    // nonce/counter block for all AES-CTR operations in this session.
    _nonce = Uint8List.fromList(deviceRandom);
    _cipherByteCount = 0;

    // Step 5: Send SessionCmd1 (encrypted device public key as verification)
    // ESP-IDF decrypts this and compares it against the device's own public
    // key.  The client must encrypt the *device* public key (32 bytes), NOT
    // the device_random.
    final encryptedVerify = await _aesCtrEncrypt(
        Uint8List.fromList(devicePublicKeyBytes), _cipherKey!);
    final cmd1 = _buildSessionCmd1(encryptedVerify);
    await _sessionChar!.write(cmd1.toList());

    // Step 6: Read SessionResp1 (verification result)
    // The response contains device_verify_data: the device encrypts the
    // *client* public key.  We must decrypt it to advance the AES-CTR
    // keystream (ESP-IDF consumed 32 bytes here) and optionally verify it.
    final resp1Raw = await _sessionChar!.read();
    final resp1 = Uint8List.fromList(resp1Raw);
    if (!_parseSessionResp1Success(resp1)) {
      throw Exception('Security1 handshake failed — incorrect PoP?');
    }

    // Advance the keystream: extract and decrypt device_verify_data (32 bytes)
    // so our _cipherByteCount stays aligned with the ESP-IDF AES-CTR state.
    final deviceVerify = _parseSessionResp1DeviceVerify(resp1);
    if (deviceVerify != null && deviceVerify.isNotEmpty) {
      await _aesCtrDecrypt(deviceVerify, _cipherKey!);
    }
  }

  // ---------------------------------------------------------------------------
  // WiFi credential transfer
  // ---------------------------------------------------------------------------

  /// Send WiFi SSID and password to the device (encrypted with the session key).
  Future<void> _sendWifiCredentials(String ssid, String password) async {
    if (_cipherKey == null) {
      throw StateError('Session key not established');
    }

    // Build the inner CmdSetConfig (ssid + passphrase).
    final cmdSetConfig = _buildWifiConfigPayload(ssid, password);

    // Build the full WiFiConfigPayload (type header + inner command) BEFORE
    // encryption.  The ESP protocomm_security1 layer decrypts the entire
    // characteristic write as one unit; the type-varint header must therefore
    // be inside the encrypted blob, not left as a plaintext wrapper.
    final fullPayload = Uint8List.fromList([
      ..._protoVarint(1, 2),         // msg type = TypeCmdSetConfig
      ..._protoBytes(12, cmdSetConfig), // CmdSetConfig body
    ]);

    // Encrypt the complete payload before writing to the characteristic.
    final encrypted = await _aesCtrEncrypt(fullPayload, _cipherKey!);
    await _configChar!.write(encrypted.toList());

    // Read and decrypt the response before parsing.
    final respEncrypted = Uint8List.fromList(await _configChar!.read());
    final resp = await _aesCtrDecrypt(respEncrypted, _cipherKey!);
    if (!_parseConfigResponseSuccess(resp)) {
      throw Exception('Device rejected WiFi credentials');
    }
  }

  /// Poll the device for WiFi connection status until connected or timeout.
  Future<bool> _pollWifiStatus({required Duration timeout}) async {
    final deadline = DateTime.now().add(timeout);
    final key = _cipherKey;
    if (key == null) return false;

    while (DateTime.now().isBefore(deadline)) {
      try {
        // Build the full WiFiConfigPayload for TypeCmdGetStatus, encrypt it,
        // and write to prov-config.  The response is also encrypted and must
        // be decrypted before parsing.
        final statusReq = _buildGetStatusMessage();
        final encryptedReq = await _aesCtrEncrypt(statusReq, key);
        await _configChar!.write(encryptedReq.toList());

        final respEncrypted = Uint8List.fromList(await _configChar!.read());
        final resp = await _aesCtrDecrypt(respEncrypted, key);

        final status = _parseWifiStatus(resp);
        if (status == _WifiStatus.connected) return true;
        if (status == _WifiStatus.failed) return false;
        // Still connecting — wait and retry
      } catch (_) {
        // Read error — device may have disconnected
      }

      await Future<void>.delayed(const Duration(seconds: 2));
    }

    return false; // Timed out
  }

  // ---------------------------------------------------------------------------
  // Protocol message builders (simplified protobuf encoding)
  // ---------------------------------------------------------------------------

  /// Build SessionCmd0: send client public key.
  /// Protobuf: SessionData { sec_ver=SecScheme1, sec1 { msg=Session_Command0,
  ///   sc0 { client_pubkey=<bytes> } } }
  Uint8List _buildSessionCmd0(Uint8List clientPubKey) {
    // Simplified protobuf encoding:
    // SessionCmd0: field 1 (bytes) = client_pubkey
    final sc0 = _protoBytes(1, clientPubKey);
    // Sec1Payload: field 1 (varint) = 0 (Session_Command0), field 20 (bytes) = sc0
    final sec1 = Uint8List.fromList([
      ..._protoVarint(1, 0),
      ..._protoBytes(20, sc0),
    ]);
    // SessionData: field 2 (varint) = 1 (SecScheme1), field 11 (bytes) = sec1
    return Uint8List.fromList([
      ..._protoVarint(2, 1),
      ..._protoBytes(11, sec1),
    ]);
  }

  /// Parse SessionResp0: extract device public key and device random.
  (Uint8List, Uint8List) _parseSessionResp0(Uint8List data) {
    // Navigate: SessionData -> sec1 (field 11) -> sr0 (field 21)
    // sr0 contains: status (field 1), device_pubkey (field 2),
    //               device_random (field 16)
    final sec1 = _protoFindBytes(data, 11);
    if (sec1 == null) throw const FormatException('Missing sec1 in SessionResp0');

    final sr0 = _protoFindBytes(sec1, 21);
    if (sr0 == null) throw const FormatException('Missing sr0 in SessionResp0');

    final devicePubKey = _protoFindBytes(sr0, 2);
    final deviceRandom = _protoFindBytes(sr0, 3);

    if (devicePubKey == null || deviceRandom == null) {
      throw const FormatException('Missing keys in SessionResp0');
    }

    return (Uint8List.fromList(devicePubKey), Uint8List.fromList(deviceRandom));
  }

  /// Build SessionCmd1: send encrypted verification data.
  Uint8List _buildSessionCmd1(Uint8List encryptedVerify) {
    final sc1 = _protoBytes(2, encryptedVerify);
    final sec1 = Uint8List.fromList([
      ..._protoVarint(1, 2), // Session_Command1 (enum value 2)
      ..._protoBytes(22, sc1),
    ]);
    return Uint8List.fromList([
      ..._protoVarint(2, 1), // SecScheme1
      ..._protoBytes(11, sec1),
    ]);
  }

  /// Parse SessionResp1: check if handshake succeeded.
  bool _parseSessionResp1Success(Uint8List data) {
    final sec1 = _protoFindBytes(data, 11);
    if (sec1 == null) return false;
    final sr1 = _protoFindBytes(sec1, 23);
    if (sr1 == null) return false;
    // status field 1 = 0 means success.
    // In proto3, the default value (0) is omitted from the wire, so a
    // missing status field also means success.
    final status = _protoFindVarint(sr1, 1);
    return status == null || status == 0;
  }

  /// Extract the device_verify_data (field 3) from a SessionResp1 message.
  /// Returns null if the field is not present.
  Uint8List? _parseSessionResp1DeviceVerify(Uint8List data) {
    final sec1 = _protoFindBytes(data, 11);
    if (sec1 == null) return null;
    final sr1 = _protoFindBytes(sec1, 23);
    if (sr1 == null) return null;
    final verifyData = _protoFindBytes(sr1, 3);
    return verifyData != null ? Uint8List.fromList(verifyData) : null;
  }

  /// Build WiFi config set command (CmdSetConfig).
  Uint8List _buildWifiConfigPayload(String ssid, String password) {
    final ssidBytes = Uint8List.fromList(utf8.encode(ssid));
    final passBytes = Uint8List.fromList(utf8.encode(password));
    // CmdSetConfig: field 1 (bytes) = ssid, field 2 (bytes) = passphrase
    return Uint8List.fromList([
      ..._protoBytes(1, ssidBytes),
      ..._protoBytes(2, passBytes),
    ]);
  }


  /// Build WiFi status get request.
  Uint8List _buildGetStatusMessage() {
    // WiFiConfigPayload: field 1 (varint) = 0 (TypeCmdGetStatus),
    //                    field 10 (bytes) = empty CmdGetStatus {}
    return Uint8List.fromList([
      ..._protoVarint(1, 0),
      ..._protoBytes(10, Uint8List(0)),
    ]);
  }

  /// Parse config response success.
  bool _parseConfigResponseSuccess(Uint8List data) {
    // RespSetConfig: field 1 (varint) = status (0 = success)
    // WiFiConfigPayload: field 13 (bytes) = RespSetConfig
    final resp = _protoFindBytes(data, 13);
    if (resp == null) return false;
    // In proto3 the default value (0 = success) is omitted from the wire.
    final status = _protoFindVarint(resp, 1);
    return status == null || status == 0;
  }

  /// Parse WiFi connection status.
  _WifiStatus _parseWifiStatus(Uint8List data) {
    // WiFiConfigPayload: field 11 (bytes) = RespGetStatus
    final resp = _protoFindBytes(data, 11);
    if (resp == null) return _WifiStatus.connecting;

    // RespGetStatus: field 2 (varint) = sta_state
    //   0 = Connected, 1 = Connecting, 2 = Disconnected, 3 = ConnectionFailed
    final staState = _protoFindVarint(resp, 2);
    if (staState == null) return _WifiStatus.connecting;

    switch (staState) {
      case 0:
        return _WifiStatus.connected;
      case 1:
        return _WifiStatus.connecting;
      default:
        return _WifiStatus.failed;
    }
  }

  // ---------------------------------------------------------------------------
  // AES-CTR encryption / decryption
  // ---------------------------------------------------------------------------

  /// Core AES-256-CTR keystream application.
  ///
  /// AES-CTR encryption and decryption are the same XOR-with-keystream
  /// operation. This method processes [data] starting at the current keystream
  /// position ([_cipherByteCount]) and advances the counter by data.length.
  ///
  /// The ESP Security1 AES-CTR state is a single continuous keystream shared
  /// across all encrypt/decrypt operations in a session, so the counter MUST
  /// NOT be reset between calls.
  Future<Uint8List> _aesCtrProcess(Uint8List data, Uint8List key) async {
    final algorithm = AesCtr.with256bits(macAlgorithm: MacAlgorithm.empty);
    final secretKey = SecretKey(key.sublist(0, 32));
    // ESP-IDF Security1 uses device_random (16 bytes from SessionResp0) as
    // the initial AES-CTR nonce/counter block.  We advance into the keystream
    // via keyStreamIndex so every call continues from the correct position.
    final nonce = _nonce ?? Uint8List(16);

    final result = await algorithm.encrypt(
      data,
      secretKey: secretKey,
      nonce: nonce,
      keyStreamIndex: _cipherByteCount,
    );

    _cipherByteCount += data.length;
    return Uint8List.fromList(result.cipherText);
  }

  /// Encrypt [plaintext] at the current keystream position and advance the
  /// counter.  Used for writes to prov-session (SC1), prov-config, and
  /// prov-scan characteristics.
  Future<Uint8List> _aesCtrEncrypt(Uint8List plaintext, Uint8List key) =>
      _aesCtrProcess(plaintext, key);

  /// Decrypt [ciphertext] at the current keystream position and advance the
  /// counter.  Used for reads from prov-config and prov-scan characteristics.
  /// AES-CTR decryption is identical to encryption (XOR with keystream).
  Future<Uint8List> _aesCtrDecrypt(Uint8List ciphertext, Uint8List key) =>
      _aesCtrProcess(ciphertext, key);

  // ---------------------------------------------------------------------------
  // Minimal protobuf encoding/decoding helpers
  // ---------------------------------------------------------------------------

  /// Encode a varint field.
  Uint8List _protoVarint(int fieldNumber, int value) {
    final tag = (fieldNumber << 3) | 0; // wire type 0 = varint
    return Uint8List.fromList([..._encodeVarint(tag), ..._encodeVarint(value)]);
  }

  /// Encode a length-delimited (bytes) field.
  Uint8List _protoBytes(int fieldNumber, Uint8List value) {
    final tag = (fieldNumber << 3) | 2; // wire type 2 = length-delimited
    return Uint8List.fromList(
        [..._encodeVarint(tag), ..._encodeVarint(value.length), ...value]);
  }

  /// Encode a single varint.
  List<int> _encodeVarint(int value) {
    final bytes = <int>[];
    var v = value;
    while (v > 0x7F) {
      bytes.add((v & 0x7F) | 0x80);
      v >>= 7;
    }
    bytes.add(v & 0x7F);
    return bytes;
  }

  /// Find a length-delimited field in protobuf data by field number.
  Uint8List? _protoFindBytes(Uint8List data, int targetField) {
    int offset = 0;
    while (offset < data.length) {
      final (tag, newOffset) = _decodeVarint(data, offset);
      if (newOffset < 0) return null;
      offset = newOffset;

      final fieldNumber = tag >> 3;
      final wireType = tag & 0x07;

      if (wireType == 2) {
        // Length-delimited
        final (length, dataOffset) = _decodeVarint(data, offset);
        if (dataOffset < 0) return null;
        offset = dataOffset;

        if (fieldNumber == targetField) {
          return Uint8List.sublistView(data, offset, offset + length);
        }
        offset += length;
      } else if (wireType == 0) {
        // Varint — skip
        final (_, nextOffset) = _decodeVarint(data, offset);
        if (nextOffset < 0) return null;
        offset = nextOffset;
      } else {
        // Unsupported wire type — bail
        return null;
      }
    }
    return null;
  }

  /// Find a varint field in protobuf data by field number.
  int? _protoFindVarint(Uint8List data, int targetField) {
    int offset = 0;
    while (offset < data.length) {
      final (tag, newOffset) = _decodeVarint(data, offset);
      if (newOffset < 0) return null;
      offset = newOffset;

      final fieldNumber = tag >> 3;
      final wireType = tag & 0x07;

      if (wireType == 0) {
        final (value, nextOffset) = _decodeVarint(data, offset);
        if (nextOffset < 0) return null;
        offset = nextOffset;
        if (fieldNumber == targetField) return value;
      } else if (wireType == 2) {
        final (length, dataOffset) = _decodeVarint(data, offset);
        if (dataOffset < 0) return null;
        offset = dataOffset + length;
      } else {
        return null;
      }
    }
    return null;
  }

  /// Decode a varint at [offset] in [data].
  /// Returns (value, nextOffset). nextOffset is -1 on error.
  (int, int) _decodeVarint(Uint8List data, int offset) {
    int value = 0;
    int shift = 0;
    int pos = offset;
    while (pos < data.length) {
      final byte = data[pos];
      value |= (byte & 0x7F) << shift;
      pos++;
      if ((byte & 0x80) == 0) return (value, pos);
      shift += 7;
      if (shift > 35) return (0, -1); // Too many bytes
    }
    return (0, -1);
  }

  // ---------------------------------------------------------------------------
  // Cleanup
  // ---------------------------------------------------------------------------

  Future<void> _cleanup() async {
    await _connectionSub?.cancel();
    _connectionSub = null;
    _sessionChar = null;
    _configChar = null;
    _scanChar = null;
    _cipherKey = null;
    _nonce = null;
    _cipherByteCount = 0;
    // Only disconnect if we were the ones who established the connection.
    // If the device was already connected (e.g. for BLE telemetry) we must
    // NOT disconnect it — that would kill the active telemetry session.
    if (_weConnected) {
      try {
        await _device?.disconnect();
      } catch (_) {}
    }
    _weConnected = false;
    _device = null;
  }

  void dispose() {
    _cleanup();
    _stepController.close();
  }
}

enum _WifiStatus { connected, connecting, failed }

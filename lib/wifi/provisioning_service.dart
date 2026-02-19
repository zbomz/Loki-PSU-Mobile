import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

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

/// Service that handles WiFi provisioning of the ESP32-C3 over BLE.
///
/// Implements the ESP Unified Provisioning protocol (Security1):
///  1. Scan for provisioning GATT services (`PROV_LOKI_*`)
///  2. Curve25519 key exchange + PoP-derived AES key
///  3. Send WiFi SSID + password (encrypted)
///  4. Poll for WiFi connection status
///
/// Uses [flutter_blue_plus] for BLE transport and [cryptography] for crypto.
class ProvisioningService {
  BluetoothDevice? _device;
  BluetoothCharacteristic? _sessionChar;
  BluetoothCharacteristic? _configChar;
  StreamSubscription<BluetoothConnectionState>? _connectionSub;

  /// AES cipher key derived from Curve25519 shared secret + PoP.
  Uint8List? _cipherKey;

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

  /// Scan for ESP32 devices advertising the provisioning service.
  ///
  /// Returns a stream of filtered scan results whose device name starts with
  /// `PROV_LOKI_`. The stream closes automatically when [timeout] elapses.
  /// Any error (BT off, permission denied, conflicting scan) is forwarded
  /// through the stream so callers can surface it in the UI.
  Stream<List<ScanResult>> scanForProvisionableDevices({
    Duration timeout = const Duration(seconds: 10),
  }) {
    _setStep(ProvisioningStep.scanning);

    final controller = StreamController<List<ScanResult>>();

    Future<void> _run() async {
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
              return r.device.platformName
                  .startsWith(RainMakerConstants.provServicePrefix);
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

    _run(); // errors travel through the StreamController
    return controller.stream;
  }

  Future<void> stopScan() async {
    await FlutterBluePlus.stopScan();
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
      // ---- 1. Connect ----
      _setStep(ProvisioningStep.connecting);
      _device = device;
      _connectionSub = device.connectionState.listen((s) {
        if (s == BluetoothConnectionState.disconnected) {
          _cleanup();
        }
      });
      await device.connect(license: License.free, autoConnect: false);

      // Discover services
      final services = await device.discoverServices();

      // Find the provisioning GATT characteristics.
      // ESP Unified Provisioning uses a custom service with characteristics
      // named by descriptor or by short UUID pattern.
      _findProvisioningCharacteristics(services);

      if (_sessionChar == null || _configChar == null) {
        throw Exception(
            'Provisioning GATT characteristics not found on device');
      }

      // ---- 2. Security1 handshake ----
      _setStep(ProvisioningStep.handshake);
      await _performSecurity1Handshake(pop);

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
    for (final service in services) {
      for (final char in service.characteristics) {
        // ESP provisioning uses custom 128-bit UUIDs.
        // The characteristic purpose is typically identified by reading
        // its user-description descriptor or by UUID mapping.
        //
        // Common UUID patterns for ESP provisioning:
        // Service: 021a9004-0382-4aea-bff4-6b3f1c5adfb4
        // prov-session: 021aff51-0382-4aea-bff4-6b3f1c5adfb4
        // prov-config:  021aff52-0382-4aea-bff4-6b3f1c5adfb4
        // proto-ver:    021aff53-0382-4aea-bff4-6b3f1c5adfb4
        final uuid = char.characteristicUuid.toString().toLowerCase();
        if (uuid.contains('ff51')) {
          _sessionChar = char;
        } else if (uuid.contains('ff52')) {
          _configChar = char;
        }
      }
    }

    // Fallback: if we didn't find by UUID pattern, try by service index.
    // Some ESP-IDF versions use sequential UUIDs within a single service.
    if (_sessionChar == null || _configChar == null) {
      for (final service in services) {
        final chars = service.characteristics;
        if (chars.length >= 2) {
          // Check if this looks like a provisioning service
          // (has at least 2 writable characteristics)
          final writableChars = chars
              .where((c) =>
                  c.properties.write || c.properties.writeWithoutResponse)
              .toList();
          if (writableChars.length >= 2) {
            // Skip our own TLV service (by checking known Loki UUID)
            final serviceUuid = service.serviceUuid.toString().toLowerCase();
            if (serviceUuid.contains('4c6f6b69')) continue;

            _sessionChar ??= writableChars[0];
            _configChar ??= writableChars[1];
          }
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
    await _sessionChar!.write(cmd0.toList(), withoutResponse: false);

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

    // Derive AES key: SHA256(shared_secret + pop)
    final sha256 = Sha256();
    final popBytes = utf8.encode(pop);
    final keyMaterial = Uint8List.fromList([...sharedSecretBytes, ...popBytes]);
    final hash = await sha256.hash(keyMaterial);
    _cipherKey = Uint8List.fromList(hash.bytes);

    // Step 5: Send SessionCmd1 (encrypted device_random as verification)
    final encryptedVerify = await _aesCtrEncrypt(
        Uint8List.fromList(deviceRandom), _cipherKey!);
    final cmd1 = _buildSessionCmd1(encryptedVerify);
    await _sessionChar!.write(cmd1.toList(), withoutResponse: false);

    // Step 6: Read SessionResp1 (verification result)
    final resp1Raw = await _sessionChar!.read();
    final resp1 = Uint8List.fromList(resp1Raw);
    if (!_parseSessionResp1Success(resp1)) {
      throw Exception('Security1 handshake failed — incorrect PoP?');
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

    // Build the wifi config payload (ssid + passphrase)
    final configPayload = _buildWifiConfigPayload(ssid, password);

    // Encrypt the inner payload
    final encrypted = await _aesCtrEncrypt(configPayload, _cipherKey!);

    // Wrap in the config message envelope
    final configMsg = _buildConfigMessage(encrypted);
    await _configChar!.write(configMsg.toList(), withoutResponse: false);

    // Read response to confirm
    final respRaw = await _configChar!.read();
    final resp = Uint8List.fromList(respRaw);
    if (!_parseConfigResponseSuccess(resp)) {
      throw Exception('Device rejected WiFi credentials');
    }
  }

  /// Poll the device for WiFi connection status until connected or timeout.
  Future<bool> _pollWifiStatus({required Duration timeout}) async {
    final deadline = DateTime.now().add(timeout);

    while (DateTime.now().isBefore(deadline)) {
      try {
        // Send a get-status request
        final statusReq = _buildGetStatusMessage();
        await _configChar!.write(statusReq.toList(), withoutResponse: false);

        final respRaw = await _configChar!.read();
        final resp = Uint8List.fromList(respRaw);

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
    final deviceRandom = _protoFindBytes(sr0, 16);

    if (devicePubKey == null || deviceRandom == null) {
      throw const FormatException('Missing keys in SessionResp0');
    }

    return (Uint8List.fromList(devicePubKey), Uint8List.fromList(deviceRandom));
  }

  /// Build SessionCmd1: send encrypted verification data.
  Uint8List _buildSessionCmd1(Uint8List encryptedVerify) {
    final sc1 = _protoBytes(2, encryptedVerify);
    final sec1 = Uint8List.fromList([
      ..._protoVarint(1, 1), // Session_Command1
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
    // status field 1 = 0 means success
    final status = _protoFindVarint(sr1, 1);
    return status == 0;
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

  /// Wrap encrypted config payload into WiFiConfigPayload message.
  Uint8List _buildConfigMessage(Uint8List encryptedPayload) {
    // WiFiConfigPayload: field 1 (varint) = 2 (TypeCmdSetConfig),
    //                    field 12 (bytes) = encrypted CmdSetConfig
    return Uint8List.fromList([
      ..._protoVarint(1, 2),
      ..._protoBytes(12, encryptedPayload),
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
    final status = _protoFindVarint(resp, 1);
    return status == 0;
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
  // AES-CTR encryption
  // ---------------------------------------------------------------------------

  Future<Uint8List> _aesCtrEncrypt(Uint8List plaintext, Uint8List key) async {
    final algorithm = AesCtr.with256bits(macAlgorithm: MacAlgorithm.empty);
    final secretKey = SecretKey(key.sublist(0, 32));
    // Use zero IV for simplicity (matches ESP-IDF Security1 implementation)
    final nonce = Uint8List(16);

    final result = await algorithm.encrypt(
      plaintext,
      secretKey: secretKey,
      nonce: nonce,
    );

    return Uint8List.fromList(result.cipherText);
  }

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
    _cipherKey = null;
    try {
      await _device?.disconnect();
    } catch (_) {}
    _device = null;
  }

  void dispose() {
    _cleanup();
    _stepController.close();
  }
}

enum _WifiStatus { connected, connecting, failed }

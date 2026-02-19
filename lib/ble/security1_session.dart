import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import '../wifi/rainmaker_constants.dart';

/// Self-contained Security1 handshake for the ESP Unified Provisioning protocol.
///
/// The unified `protocomm_nimble` BLE stack on the ESP32 requires a Security1
/// session to be established before it will accept any GATT operations
/// (including notification subscriptions on non-provisioning characteristics).
///
/// Call [establish] once after connecting and discovering services.  The method
/// finds the `prov-session` characteristic (UUID containing `ff51`), performs
/// the Curve25519 + PoP key exchange, and returns normally on success.  If the
/// characteristic is not present (e.g. older firmware), it returns immediately
/// as a no-op.
class Security1Session {
  Security1Session._(); // static-only

  // ---------------------------------------------------------------------------
  // Public API
  // ---------------------------------------------------------------------------

  /// Locate the prov-session characteristic in [services] and perform the
  /// Security1 handshake using the given Proof of Possession [pop].
  ///
  /// * Returns normally on success.
  /// * Returns immediately (no-op) if no prov-session characteristic is found.
  /// * Throws on handshake failure (wrong PoP, firmware error, etc.).
  static Future<void> establish(
    List<BluetoothService> services, {
    String pop = RainMakerConstants.provPop,
  }) async {
    // ---- 1. Find the prov-session characteristic (UUID contains 'ff51') ----
    BluetoothCharacteristic? sessionChar;
    for (final service in services) {
      for (final char in service.characteristics) {
        if (char.characteristicUuid
            .toString()
            .toLowerCase()
            .contains('ff51')) {
          sessionChar = char;
          break;
        }
      }
      if (sessionChar != null) break;
    }

    if (sessionChar == null) {
      // Device does not expose a provisioning session characteristic.
      // This is expected for older firmware; skip silently.
      return;
    }

    // ---- 2. Curve25519 key pair ----
    final algorithm = X25519();
    final clientKeyPair = await algorithm.newKeyPair();
    final clientPublicKey = await clientKeyPair.extractPublicKey();
    final clientPublicKeyBytes = Uint8List.fromList(clientPublicKey.bytes);

    // ---- 3. SessionCmd0 — send client public key ----
    final cmd0 = _buildSessionCmd0(clientPublicKeyBytes);
    await sessionChar.write(cmd0.toList(), withoutResponse: false);

    // ---- 4. SessionResp0 — receive device public key + device random ----
    final resp0Raw = await sessionChar.read();
    final resp0 = Uint8List.fromList(resp0Raw);
    final (devicePubKeyBytes, deviceRandom) = _parseSessionResp0(resp0);

    // ---- 5. Shared secret → AES key ----
    final devicePubKey =
        SimplePublicKey(devicePubKeyBytes, type: KeyPairType.x25519);
    final sharedSecret = await algorithm.sharedSecretKey(
      keyPair: clientKeyPair,
      remotePublicKey: devicePubKey,
    );
    final sharedSecretBytes =
        Uint8List.fromList(await sharedSecret.extractBytes());

    final sha256 = Sha256();
    final keyMaterial = Uint8List.fromList([
      ...sharedSecretBytes,
      ...utf8.encode(pop),
    ]);
    final hash = await sha256.hash(keyMaterial);
    final cipherKey = Uint8List.fromList(hash.bytes);

    // ---- 6. SessionCmd1 — send encrypted verification (device_random) ----
    final encryptedVerify = await _aesCtrEncrypt(
      Uint8List.fromList(deviceRandom),
      cipherKey,
    );
    final cmd1 = _buildSessionCmd1(encryptedVerify);
    await sessionChar.write(cmd1.toList(), withoutResponse: false);

    // ---- 7. SessionResp1 — verify handshake succeeded ----
    final resp1Raw = await sessionChar.read();
    final resp1 = Uint8List.fromList(resp1Raw);
    if (!_parseSessionResp1Success(resp1)) {
      throw Exception('Security1 handshake failed — incorrect PoP?');
    }
  }

  // ---------------------------------------------------------------------------
  // Protobuf message builders / parsers
  // ---------------------------------------------------------------------------

  /// Build SessionCmd0: SessionData { sec_ver=SecScheme1, sec1 {
  ///   msg=Session_Command0, sc0 { client_pubkey } } }
  static Uint8List _buildSessionCmd0(Uint8List clientPubKey) {
    final sc0 = _protoBytes(1, clientPubKey);
    final sec1 = Uint8List.fromList([
      ..._protoVarint(1, 0), // msg = Session_Command0
      ..._protoBytes(20, sc0),
    ]);
    return Uint8List.fromList([
      ..._protoVarint(2, 1), // sec_ver = SecScheme1
      ..._protoBytes(11, sec1),
    ]);
  }

  /// Parse SessionResp0 → (device_pubkey, device_random).
  static (Uint8List, Uint8List) _parseSessionResp0(Uint8List data) {
    final sec1 = _protoFindBytes(data, 11);
    if (sec1 == null) {
      throw const FormatException('Missing sec1 in SessionResp0');
    }
    final sr0 = _protoFindBytes(sec1, 21);
    if (sr0 == null) {
      throw const FormatException('Missing sr0 in SessionResp0');
    }
    final devicePubKey = _protoFindBytes(sr0, 2);
    final deviceRandom = _protoFindBytes(sr0, 3); // field 3, NOT 16

    if (devicePubKey == null || deviceRandom == null) {
      throw const FormatException('Missing keys in SessionResp0');
    }
    return (Uint8List.fromList(devicePubKey), Uint8List.fromList(deviceRandom));
  }

  /// Build SessionCmd1: encrypted client_verify_data.
  static Uint8List _buildSessionCmd1(Uint8List encryptedVerify) {
    final sc1 = _protoBytes(2, encryptedVerify);
    final sec1 = Uint8List.fromList([
      ..._protoVarint(1, 1), // msg = Session_Command1
      ..._protoBytes(22, sc1),
    ]);
    return Uint8List.fromList([
      ..._protoVarint(2, 1), // sec_ver = SecScheme1
      ..._protoBytes(11, sec1),
    ]);
  }

  /// Parse SessionResp1: status == 0 means success.
  static bool _parseSessionResp1Success(Uint8List data) {
    final sec1 = _protoFindBytes(data, 11);
    if (sec1 == null) return false;
    final sr1 = _protoFindBytes(sec1, 23);
    if (sr1 == null) return false;
    final status = _protoFindVarint(sr1, 1);
    return status == 0;
  }

  // ---------------------------------------------------------------------------
  // AES-CTR (handshake verification only — counter always starts at 0)
  // ---------------------------------------------------------------------------

  static Future<Uint8List> _aesCtrEncrypt(
    Uint8List plaintext,
    Uint8List key,
  ) async {
    final algorithm = AesCtr.with256bits(macAlgorithm: MacAlgorithm.empty);
    final secretKey = SecretKey(key.sublist(0, 32));
    final nonce = Uint8List(16); // zero IV — matches ESP-IDF Security1

    final result = await algorithm.encrypt(
      plaintext,
      secretKey: secretKey,
      nonce: nonce,
    );
    return Uint8List.fromList(result.cipherText);
  }

  // ---------------------------------------------------------------------------
  // Minimal protobuf helpers (self-contained to avoid circular imports)
  // ---------------------------------------------------------------------------

  static Uint8List _protoVarint(int fieldNumber, int value) {
    final tag = (fieldNumber << 3) | 0;
    return Uint8List.fromList([..._encodeVarint(tag), ..._encodeVarint(value)]);
  }

  static Uint8List _protoBytes(int fieldNumber, Uint8List value) {
    final tag = (fieldNumber << 3) | 2;
    return Uint8List.fromList(
        [..._encodeVarint(tag), ..._encodeVarint(value.length), ...value]);
  }

  static List<int> _encodeVarint(int value) {
    final bytes = <int>[];
    var v = value;
    while (v > 0x7F) {
      bytes.add((v & 0x7F) | 0x80);
      v >>= 7;
    }
    bytes.add(v & 0x7F);
    return bytes;
  }

  static Uint8List? _protoFindBytes(Uint8List data, int targetField) {
    int offset = 0;
    while (offset < data.length) {
      final (tag, newOffset) = _decodeVarint(data, offset);
      if (newOffset < 0) return null;
      offset = newOffset;

      final fieldNumber = tag >> 3;
      final wireType = tag & 0x07;

      if (wireType == 2) {
        final (length, dataOffset) = _decodeVarint(data, offset);
        if (dataOffset < 0) return null;
        offset = dataOffset;
        if (fieldNumber == targetField) {
          return Uint8List.sublistView(data, offset, offset + length);
        }
        offset += length;
      } else if (wireType == 0) {
        final (_, nextOffset) = _decodeVarint(data, offset);
        if (nextOffset < 0) return null;
        offset = nextOffset;
      } else {
        return null;
      }
    }
    return null;
  }

  static int? _protoFindVarint(Uint8List data, int targetField) {
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

  static (int, int) _decodeVarint(Uint8List data, int offset) {
    int value = 0;
    int shift = 0;
    int pos = offset;
    while (pos < data.length) {
      final byte = data[pos];
      value |= (byte & 0x7F) << shift;
      pos++;
      if ((byte & 0x80) == 0) return (value, pos);
      shift += 7;
      if (shift > 35) return (0, -1);
    }
    return (0, -1);
  }
}

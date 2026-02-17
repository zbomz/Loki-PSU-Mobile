import 'dart:typed_data';
import 'common_protocol.dart';
import 'crc16.dart';

/// Represents a parsed TLV response from the Loki PSU.
class TlvResponse {
  final int tag;
  final Uint8List value;

  TlvResponse({required this.tag, required this.value});

  /// True if this is an OK response (tag 0xF0).
  bool get isOk => tag == ProtocolTag.responseOk;

  /// True if this is an error response (tag 0xF1).
  bool get isError => tag == ProtocolTag.responseError;

  /// For error responses, returns the error code byte.
  int get errorCode => isError && value.isNotEmpty ? value[0] : 0;

  /// Decode value as a single little-endian float32.
  double get asFloat {
    if (value.length < 4) return 0.0;
    return ByteData.sublistView(value).getFloat32(0, Endian.little);
  }

  /// Decode value as a single uint8.
  int get asUint8 => value.isNotEmpty ? value[0] : 0;

  /// Decode value as the telemetry bundle (6 floats).
  TelemetryBundle get asTelemetryBundle => TelemetryBundle.fromBytes(value);
}

/// All 6 telemetry values returned by TELEMETRY_BUNDLE (tag 0x0F).
class TelemetryBundle {
  final double voltage;
  final double current;
  final double power;
  final double inletTemperature;
  final double internalTemperature;
  final double energyWh;

  TelemetryBundle({
    required this.voltage,
    required this.current,
    required this.power,
    required this.inletTemperature,
    required this.internalTemperature,
    required this.energyWh,
  });

  factory TelemetryBundle.fromBytes(Uint8List bytes) {
    if (bytes.length < TlvConstants.telemetryBundleValueSize) {
      return TelemetryBundle(
        voltage: 0,
        current: 0,
        power: 0,
        inletTemperature: 0,
        internalTemperature: 0,
        energyWh: 0,
      );
    }
    final bd = ByteData.sublistView(bytes);
    return TelemetryBundle(
      voltage: bd.getFloat32(0, Endian.little),
      current: bd.getFloat32(4, Endian.little),
      power: bd.getFloat32(8, Endian.little),
      inletTemperature: bd.getFloat32(12, Endian.little),
      internalTemperature: bd.getFloat32(16, Endian.little),
      energyWh: bd.getFloat32(20, Endian.little),
    );
  }
}

/// Builds TLV request packets for the Loki PSU.
class TlvRequestBuilder {
  /// Create a read request (zero-length value).
  static Uint8List readRequest(int tag) {
    final data = Uint8List.fromList([ProtocolID.lokiTlv, tag, 0x00]);
    return appendCrc16(data);
  }

  /// Create a write request with a float32 value.
  static Uint8List writeFloat(int tag, double value) {
    final data = Uint8List(7);
    data[0] = ProtocolID.lokiTlv;
    data[1] = tag;
    data[2] = 0x04;
    ByteData.sublistView(data).setFloat32(3, value, Endian.little);
    return appendCrc16(data);
  }

  /// Create a write request with a uint8 value.
  static Uint8List writeUint8(int tag, int value) {
    final data =
        Uint8List.fromList([ProtocolID.lokiTlv, tag, 0x01, value & 0xFF]);
    return appendCrc16(data);
  }

  /// Create a command request (zero-length value, same as read).
  static Uint8List command(int tag) => readRequest(tag);
}

/// Parses TLV response packets from the Loki PSU.
class TlvResponseParser {
  /// Parse a raw response byte array into a [TlvResponse].
  ///
  /// Throws [FormatException] on invalid packets.
  static TlvResponse parse(Uint8List packet) {
    if (packet.length < TlvConstants.tlvMinPacketSize) {
      throw FormatException('Packet too short: ${packet.length} bytes');
    }

    if (!validateCrc16(packet)) {
      throw const FormatException('CRC mismatch');
    }

    if (packet[0] != ProtocolID.lokiTlv) {
      throw FormatException(
          'Invalid protocol ID: 0x${packet[0].toRadixString(16)}');
    }

    final tag = packet[1];
    final valueLength = packet[2];

    // Validate total length
    final expectedLength =
        TlvConstants.tlvHeaderSize + valueLength + TlvConstants.tlvCrcSize;
    if (packet.length < expectedLength) {
      throw FormatException(
          'Length mismatch: declared $valueLength, packet ${packet.length}');
    }

    final value = Uint8List.sublistView(packet, 3, 3 + valueLength);
    return TlvResponse(tag: tag, value: value);
  }
}

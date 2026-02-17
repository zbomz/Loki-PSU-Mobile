# Loki PSU BLE Interface Specification

## Overview

This document specifies the Bluetooth Low Energy (BLE) interface for the Loki PSU APW3 V1. It is the canonical reference for building BLE client applications (e.g., a Flutter mobile app) that communicate with the Loki PSU firmware.

The BLE transport carries the same TLV (Type-Length-Value) protocol used over I2C. A client writes TLV request packets to a GATT characteristic and receives TLV response packets via notification on another characteristic.

**Version:** 1.0
**Date:** 2026-02-16
**BLE Stack:** NimBLE-Arduino (ESP32-C3, BLE 5.0 LE)

---

## GATT Service Layout

### Device Information

| Property | Value |
|----------|-------|
| Device Name | `Loki PSU` |
| Appearance | Generic (default) |

### Loki PSU Service

| Element | UUID | Properties |
|---------|------|------------|
| Service | `4c6f6b69-5053-5500-0001-000000000000` | Primary |
| TLV Request Characteristic | `4c6f6b69-5053-5500-0002-000000000000` | Write |
| TLV Response Characteristic | `4c6f6b69-5053-5500-0003-000000000000` | Notify, Read |

UUIDs are derived from "LokiPSU" in ASCII hex (`4c6f6b69-5053-55`), making them memorable and unique.

### Characteristic Details

#### TLV Request (Write)

- **UUID:** `4c6f6b69-5053-5500-0002-000000000000`
- **Properties:** Write (with response)
- **Usage:** Client writes a complete TLV request packet (5-64 bytes)
- **Behavior:** The firmware processes the request synchronously and sends the response via notification on the Response characteristic

#### TLV Response (Notify + Read)

- **UUID:** `4c6f6b69-5053-5500-0003-000000000000`
- **Properties:** Notify, Read
- **Usage:** Client subscribes to notifications to receive TLV responses
- **Behavior:** After each write to the Request characteristic, the firmware sends exactly one notification containing the response packet
- **Read:** Returns the last response packet (useful for debugging)

---

## Communication Flow

```
┌──────────┐                              ┌──────────┐
│  Client   │                              │ Loki PSU │
│ (Flutter) │                              │  (ESP32) │
└────┬─────┘                              └────┬─────┘
     │                                         │
     │  1. Scan for "Loki PSU"                 │
     │────────────────────────────────────────>│
     │                                         │
     │  2. Connect                             │
     │<───────────────────────────────────────>│
     │                                         │
     │  3. Discover Service                    │
     │     4c6f6b69-5053-5500-0001-...         │
     │────────────────────────────────────────>│
     │                                         │
     │  4. Subscribe to Response notifications │
     │     4c6f6b69-5053-5500-0003-...         │
     │────────────────────────────────────────>│
     │                                         │
     │  5. Write TLV request to Request char   │
     │     4c6f6b69-5053-5500-0002-...         │
     │────────────────────────────────────────>│
     │                                         │
     │  6. Receive TLV response (notification) │
     │<────────────────────────────────────────│
     │                                         │
     │  (repeat 5-6 for each operation)        │
     │                                         │
```

### Step-by-Step for Flutter

1. **Scan** for BLE devices advertising service UUID `4c6f6b69-5053-5500-0001-000000000000`
2. **Connect** to the discovered device
3. **Discover services** and locate the Loki PSU service
4. **Subscribe** to notifications on the Response characteristic (UUID `..0003...`)
5. **Write** TLV request bytes to the Request characteristic (UUID `..0002...`)
6. **Await** notification — the response arrives as a byte array in the notification callback
7. **Parse** the response using the TLV codec

---

## MTU Considerations

- **Default BLE MTU:** 23 bytes (ATT payload = 20 bytes)
- **Firmware requested MTU:** 256 bytes
- **Negotiated MTU:** Depends on client; most modern phones support 247+ bytes
- **Largest response:** `CONFIG_BUNDLE` = 50 bytes (header 3 + value 45 + CRC 2)

If the negotiated MTU is less than 50 bytes, the `CONFIG_BUNDLE` response may fail. Individual config reads always fit within the default MTU.

**Flutter recommendation:** After connecting, call `requestMtu(256)` to negotiate a larger MTU before sending any requests.

---

## TLV Protocol Summary

The TLV protocol is fully documented in `LOKI_PSU_UNIFIED_TLV_PROTOCOL_SPECIFICATION.md`. This section provides a quick reference for BLE client implementers.

### Packet Structure

```
[Protocol ID][Tag][Length][Value...][CRC16_LSB][CRC16_MSB]
   1 byte    1 byte 1 byte  N bytes    1 byte     1 byte
```

- **Protocol ID:** Always `0x15`
- **CRC16:** CRC16-MODBUS over all bytes except CRC itself (polynomial 0xA001, init 0xFFFF)
- **Endianness:** Little-endian for all multi-byte values

### Operation Types

| Operation | Request | Response |
|-----------|---------|----------|
| Read telemetry/config | `[0x15][tag][0x00][CRC]` (5 bytes) | `[0x15][tag][len][value][CRC]` (6-29 bytes) |
| Write config (float32) | `[0x15][tag][0x04][float32][CRC]` (9 bytes) | `[0x15][0xF0][0x01][0x00][CRC]` (6 bytes) |
| Write config (uint8) | `[0x15][tag][0x01][uint8][CRC]` (6 bytes) | `[0x15][0xF0][0x01][0x00][CRC]` (6 bytes) |
| Command | `[0x15][tag][0x00][CRC]` (5 bytes) | `[0x15][0xF0][0x01][0x00][CRC]` (6 bytes) |
| Telemetry bundle | `[0x15][0x0F][0x00][CRC]` (5 bytes) | `[0x15][0x0F][0x18][24 bytes][CRC]` (29 bytes) |

### Telemetry Bundle (Tag 0x0F)

Returns all 6 read-only telemetry values in a single response. Reduces dashboard refresh from 6 BLE round trips to 1.

**Request:** `[0x15][0x0F][0x00][CRC_LSB][CRC_MSB]` = 5 bytes

**Response:** `[0x15][0x0F][0x18][...24 bytes of float32...][CRC_LSB][CRC_MSB]` = 29 bytes

Value field layout (all IEEE 754 float32, little-endian):

| Byte Offset | Field | Units |
|-------------|-------|-------|
| 0-3 | Measured PSU Output Voltage | Volts |
| 4-7 | Measured PSU Output Current | Amps |
| 8-11 | Measured PSU Output Power | Watts |
| 12-15 | Measured PSU Inlet Temperature | Celsius |
| 16-19 | Measured PSU Internal Temperature | Celsius |
| 20-23 | Total Energy Since Boot | Watt-hours |

### Configuration Bundle (Tag 0x1F)

Returns all 15 read-write configuration values in a single response. Reduces settings refresh from 15 BLE round trips to 1.

**Request:** `[0x15][0x1F][0x00][CRC_LSB][CRC_MSB]` = 5 bytes

**Response:** `[0x15][0x1F][0x2D][...45 bytes of mixed data...][CRC_LSB][CRC_MSB]` = 50 bytes

Value field layout (mixed float32 and uint8, little-endian):

| Byte Offset | Field | Type | Units |
|-------------|-------|------|-------|
| 0-3 | PSU_TARGET_OUTPUT_VOLTAGE | float32 | Volts |
| 4-7 | MAX_PSU_OUTPUT_POWER_THRESHOLD | float32 | Watts |
| 8-11 | TARGET_PSU_INLET_TEMPERATURE | float32 | Celsius |
| 12-15 | POWER_FAULT_TIMEOUT | float32 | seconds |
| 16-19 | PSU_OTP_THRESHOLD | float32 | Celsius |
| 20 | PSU_MAX_POWER_SHUTOFF_ENABLE | uint8 | 0/1 |
| 21 | PSU_THERMOSTAT_ENABLE | uint8 | 0/1 |
| 22 | PSU_SILENCE_FAN_ENABLE | uint8 | 0/1 |
| 23 | SPOOFED_PSU_HARDWARE_MODEL | uint8 | model byte |
| 24 | SPOOFED_PSU_FIRMWARE_VERSION | uint8 | version byte |
| 25 | PSU_OUTPUT_ENABLE | uint8 | 0/1 |
| 26 | PSU_VOLTAGE_REGULATION_ENABLE | uint8 | 0/1 |
| 27 | SPOOF_ABOVE_MAX_OUTPUT_VOLTAGE_ENABLE | uint8 | 0/1 |
| 28 | AUTOMATIC_RETRY_AFTER_POWER_FAULT_ENABLE | uint8 | 0/1 |
| 29 | PSU_OTP_ENABLE | uint8 | 0/1 |

### Error Responses

When an operation fails, the response contains tag `0xF1`:

```
[0x15][0xF1][0x01][error_code][CRC_LSB][CRC_MSB]
```

| Error Code | Name | Description |
|------------|------|-------------|
| 0x0D | ERROR_CRC_MISMATCH | CRC validation failed |
| 0x0E | ERROR_INVALID_TAG | Unknown tag |
| 0x0F | ERROR_INVALID_LENGTH | Packet length mismatch |
| 0x10 | ERROR_OUT_OF_RANGE | Value exceeds valid range |
| 0x11 | ERROR_READ_ONLY | Attempted write to read-only tag |
| 0x12 | ERROR_INVALID_PROTOCOL | Protocol ID is not 0x15 |

---

## Complete Tag Reference

### Read-Only Telemetry (0x01-0x07)

| Tag | Name | Type | Units |
|-----|------|------|-------|
| 0x01 | MEASURED_PSU_OUTPUT_CURRENT | float32 | Amps |
| 0x02 | MEASURED_PSU_OUTPUT_POWER | float32 | Watts |
| 0x03 | MEASURED_PSU_OUTPUT_VOLTAGE | float32 | Volts |
| 0x04 | MEASURED_PSU_INLET_TEMPERATURE | float32 | Celsius |
| 0x05 | MEASURED_PSU_INTERNAL_TEMP | float32 | Celsius |
| 0x06 | TOTAL_ENERGY_WH | float32 | Watt-hours |
| 0x0F | TELEMETRY_BUNDLE | 6x float32 | Mixed (see above) |
| 0x1F | CONFIG_BUNDLE | mixed | Mixed (see above) |

### Read-Write Configuration (0x10-0x1E)

| Tag | Name | Type | Range/Default |
|-----|------|------|---------------|
| 0x10 | PSU_TARGET_OUTPUT_VOLTAGE | float32 | 8.0-15.0 V, default 12.2 |
| 0x11 | PSU_MAX_POWER_SHUTOFF_ENABLE | uint8 | 0/1, default 1 (ON) |
| 0x12 | MAX_PSU_OUTPUT_POWER_THRESHOLD | float32 | 100.0-4000.0 W |
| 0x13 | PSU_THERMOSTAT_ENABLE | uint8 | 0/1, default 0 (OFF) |
| 0x14 | TARGET_PSU_INLET_TEMPERATURE | float32 | 10.0-40.0 C, default 21.0 |
| 0x15 | PSU_SILENCE_FAN_ENABLE | uint8 | 0/1, default 0 (OFF) |
| 0x16 | SPOOFED_PSU_HARDWARE_MODEL | uint8 | Valid model bytes, default 0x75 |
| 0x17 | SPOOFED_PSU_FIRMWARE_VERSION | uint8 | Valid FW bytes, default 0x16 |
| 0x18 | PSU_OUTPUT_ENABLE | uint8 | 0/1, default 1 (ON) |
| 0x19 | PSU_VOLTAGE_REGULATION_ENABLE | uint8 | 0/1, default 1 (ON) |
| 0x1A | SPOOF_ABOVE_MAX_OUTPUT_VOLTAGE_ENABLE | uint8 | 0/1, default 1 (ON) |
| 0x1B | POWER_FAULT_TIMEOUT | float32 | 1.0-60.0 s, default 10.0 |
| 0x1C | AUTO_RETRY_AFTER_POWER_FAULT_ENABLE | uint8 | 0/1, default 0 (OFF) |
| 0x1D | PSU_OTP_THRESHOLD | float32 | 50.0-120.0 C, default 95.0 |
| 0x1E | PSU_OTP_ENABLE | uint8 | 0/1, default 1 (ON) |

### Query Tags (0x20-0x30)

All query tags return float32 values. Send a read request (length=0) and receive the limit or default value.

| Tag | Name |
|-----|------|
| 0x20 | QUERY_PSU_TARGET_OUTPUT_VOLTAGE_MIN |
| 0x21 | QUERY_PSU_TARGET_OUTPUT_VOLTAGE_MAX |
| 0x22 | QUERY_PSU_TARGET_OUTPUT_VOLTAGE_DEFAULT |
| 0x23 | QUERY_MAX_PSU_OUTPUT_POWER_THRESHOLD_MIN |
| 0x24 | QUERY_MAX_PSU_OUTPUT_POWER_THRESHOLD_MAX |
| 0x25 | QUERY_MAX_PSU_OUTPUT_POWER_THRESHOLD_DEFAULT |
| 0x26 | QUERY_TARGET_PSU_INLET_TEMPERATURE_MIN |
| 0x27 | QUERY_TARGET_PSU_INLET_TEMPERATURE_MAX |
| 0x28 | QUERY_TARGET_PSU_INLET_TEMPERATURE_DEFAULT |
| 0x29 | QUERY_PSU_HARDWARE_MODEL_OPTIONS (multi-byte) |
| 0x2A | QUERY_PSU_FIRMWARE_VERSION_OPTIONS (multi-byte) |
| 0x2B | QUERY_POWER_FAULT_TIMEOUT_MIN |
| 0x2C | QUERY_POWER_FAULT_TIMEOUT_MAX |
| 0x2D | QUERY_POWER_FAULT_TIMEOUT_DEFAULT |
| 0x2E | QUERY_PSU_OTP_THRESHOLD_MIN |
| 0x2F | QUERY_PSU_OTP_THRESHOLD_MAX |
| 0x30 | QUERY_PSU_OTP_THRESHOLD_DEFAULT |

### Commands (0x31)

| Tag | Name | Description |
|-----|------|-------------|
| 0x31 | CMD_RESET_PSU_ENERGY_TRACKER | Reset energy counter to 0 Wh |

---

## Dart Protocol Code

### Generated File: common_protocol.dart

The protocol enums, tags, and constants are **auto-generated** from the firmware's `src/CommonProtocol.h` using the codegen script:

```bash
python tools/generate_dart_protocol.py src/CommonProtocol.h --output <flutter_project>/lib/protocol/common_protocol.dart
```

`CommonProtocol.h` is the single source of truth. After any protocol change on the firmware side, re-run this script to update the Dart definitions.

### Hand-Written File: crc16.dart

```dart
import 'dart:typed_data';

/// CRC16-MODBUS implementation matching the firmware's calculateCRC16Modbus().
///
/// Polynomial: 0xA001 (reversed 0x8005)
/// Initial value: 0xFFFF
/// Test vector: "123456789" -> 0x4B37
int crc16Modbus(Uint8List data) {
  int crc = 0xFFFF;
  for (final byte in data) {
    crc ^= byte;
    for (int j = 0; j < 8; j++) {
      if ((crc & 0x0001) != 0) {
        crc = (crc >> 1) ^ 0xA001;
      } else {
        crc >>= 1;
      }
    }
  }
  return crc & 0xFFFF;
}

/// Validate that the last 2 bytes of [packet] match the CRC of the preceding data.
bool validateCrc16(Uint8List packet) {
  if (packet.length < 3) return false;
  final calculated = crc16Modbus(Uint8List.sublistView(packet, 0, packet.length - 2));
  final received = packet[packet.length - 2] | (packet[packet.length - 1] << 8);
  return calculated == received;
}

/// Append CRC16 to [data] and return a new Uint8List with CRC appended.
Uint8List appendCrc16(Uint8List data) {
  final crc = crc16Modbus(data);
  final result = Uint8List(data.length + 2);
  result.setRange(0, data.length, data);
  result[data.length] = crc & 0xFF;        // LSB
  result[data.length + 1] = (crc >> 8) & 0xFF; // MSB
  return result;
}
```

### Hand-Written File: tlv_codec.dart

```dart
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

  /// Decode value as the config bundle (15 mixed values).
  ConfigBundle get asConfigBundle => ConfigBundle.fromBytes(value);
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
        voltage: 0, current: 0, power: 0,
        inletTemperature: 0, internalTemperature: 0, energyWh: 0,
      );
    }
    final bd = ByteData.sublistView(bytes);
    return TelemetryBundle(
      voltage:             bd.getFloat32(0, Endian.little),
      current:             bd.getFloat32(4, Endian.little),
      power:               bd.getFloat32(8, Endian.little),
      inletTemperature:    bd.getFloat32(12, Endian.little),
      internalTemperature: bd.getFloat32(16, Endian.little),
      energyWh:            bd.getFloat32(20, Endian.little),
    );
  }
}

/// All 15 configuration values returned by CONFIG_BUNDLE (tag 0x1F).
class ConfigBundle {
  final double targetVoltage;
  final double maxPowerThreshold;
  final double targetInletTemperature;
  final double powerFaultTimeout;
  final double psuOtpThreshold;
  final int psuMaxPowerShutoffEnable;
  final int psuThermostatEnable;
  final int psuSilenceFanEnable;
  final int spoofedPsuHardwareModel;
  final int spoofedPsuFirmwareVersion;
  final int psuOutputEnable;
  final int psuVoltageRegulationEnable;
  final int spoofAboveMaxOutputVoltageEnable;
  final int automaticRetryAfterPowerFaultEnable;
  final int psuOtpEnable;

  ConfigBundle({
    required this.targetVoltage,
    required this.maxPowerThreshold,
    required this.targetInletTemperature,
    required this.powerFaultTimeout,
    required this.psuOtpThreshold,
    required this.psuMaxPowerShutoffEnable,
    required this.psuThermostatEnable,
    required this.psuSilenceFanEnable,
    required this.spoofedPsuHardwareModel,
    required this.spoofedPsuFirmwareVersion,
    required this.psuOutputEnable,
    required this.psuVoltageRegulationEnable,
    required this.spoofAboveMaxOutputVoltageEnable,
    required this.automaticRetryAfterPowerFaultEnable,
    required this.psuOtpEnable,
  });

  factory ConfigBundle.fromBytes(Uint8List bytes) {
    if (bytes.length < TlvConstants.configBundleValueSize) {
      return ConfigBundle(
        targetVoltage: 0, maxPowerThreshold: 0, targetInletTemperature: 0,
        powerFaultTimeout: 0, psuOtpThreshold: 0,
        psuMaxPowerShutoffEnable: 0, psuThermostatEnable: 0, psuSilenceFanEnable: 0,
        spoofedPsuHardwareModel: 0, spoofedPsuFirmwareVersion: 0,
        psuOutputEnable: 0, psuVoltageRegulationEnable: 0,
        spoofAboveMaxOutputVoltageEnable: 0,
        automaticRetryAfterPowerFaultEnable: 0, psuOtpEnable: 0,
      );
    }
    final bd = ByteData.sublistView(bytes);
    return ConfigBundle(
      targetVoltage:                bd.getFloat32(0, Endian.little),
      maxPowerThreshold:            bd.getFloat32(4, Endian.little),
      targetInletTemperature:       bd.getFloat32(8, Endian.little),
      powerFaultTimeout:            bd.getFloat32(12, Endian.little),
      psuOtpThreshold:              bd.getFloat32(16, Endian.little),
      psuMaxPowerShutoffEnable:     bytes[20],
      psuThermostatEnable:          bytes[21],
      psuSilenceFanEnable:          bytes[22],
      spoofedPsuHardwareModel:      bytes[23],
      spoofedPsuFirmwareVersion:    bytes[24],
      psuOutputEnable:              bytes[25],
      psuVoltageRegulationEnable:   bytes[26],
      spoofAboveMaxOutputVoltageEnable: bytes[27],
      automaticRetryAfterPowerFaultEnable: bytes[28],
      psuOtpEnable:                 bytes[29],
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
    final data = Uint8List.fromList([ProtocolID.lokiTlv, tag, 0x01, value & 0xFF]);
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
      throw FormatException('CRC mismatch');
    }

    if (packet[0] != ProtocolID.lokiTlv) {
      throw FormatException('Invalid protocol ID: 0x${packet[0].toRadixString(16)}');
    }

    final tag = packet[1];
    final valueLength = packet[2];

    // Validate total length
    final expectedLength = TlvConstants.tlvHeaderSize + valueLength + TlvConstants.tlvCrcSize;
    if (packet.length < expectedLength) {
      throw FormatException('Length mismatch: declared $valueLength, packet ${packet.length}');
    }

    final value = Uint8List.sublistView(packet, 3, 3 + valueLength);
    return TlvResponse(tag: tag, value: value);
  }
}
```

---

## Recommended Flutter Packages

| Package | Purpose |
|---------|---------|
| `flutter_blue_plus` | BLE scanning, connecting, reading/writing characteristics |
| `provider` or `riverpod` | State management for telemetry data and connection state |

---

## Suggested Flutter App Architecture

```
lib/
  protocol/
    common_protocol.dart    <-- AUTO-GENERATED (run codegen script)
    crc16.dart              <-- Hand-written (from this spec)
    tlv_codec.dart          <-- Hand-written (from this spec)
  ble/
    ble_service.dart        <-- BLE scan/connect/disconnect logic
    ble_constants.dart      <-- Service and characteristic UUIDs
  models/
    psu_state.dart          <-- Data model for PSU telemetry + config
  screens/
    scan_screen.dart        <-- BLE device scanner
    dashboard_screen.dart   <-- Live telemetry display
    settings_screen.dart    <-- Configuration controls
  main.dart
```

### BLE Constants

```dart
class BleConstants {
  static const serviceUuid = '4c6f6b69-5053-5500-0001-000000000000';
  static const requestCharUuid = '4c6f6b69-5053-5500-0002-000000000000';
  static const responseCharUuid = '4c6f6b69-5053-5500-0003-000000000000';
  static const deviceName = 'Loki PSU';
}
```

---

## Example Byte Sequences

### Read Voltage

```
Request:  [0x15, 0x03, 0x00, 0x60, 0xF4]
Response: [0x15, 0x03, 0x04, 0xA8, 0x45, 0x43, 0x41, 0x6E, 0x87]
                                    ^--- 12.205V as float32 LE
```

### Read Telemetry Bundle

```
Request:  [0x15, 0x0F, 0x00, 0xE1, 0x94]
Response: [0x15, 0x0F, 0x18,
           V3, V2, V1, V0,          // voltage (float32 LE)
           C3, C2, C1, C0,          // current
           P3, P2, P1, P0,          // power
           IT3, IT2, IT1, IT0,      // inlet temp
           PT3, PT2, PT1, PT0,      // internal temp
           E3, E2, E1, E0,          // energy
           CRC_LSB, CRC_MSB]
```

### Read Configuration Bundle

```
Request:  [0x15, 0x1F, 0x00, CRC_LSB, CRC_MSB]
Response: [0x15, 0x1F, 0x2D,
           TV3, TV2, TV1, TV0,       // target voltage (float32 LE)
           MP3, MP2, MP1, MP0,       // max power threshold
           IT3, IT2, IT1, IT0,       // target inlet temp
           FT3, FT2, FT1, FT0,       // power fault timeout
           OT3, OT2, OT1, OT0,       // PSU OTP threshold
           MS, TS, FS, HM, FV,       // uint8 enables and spoof values
           OE, VE, SA, AR, OE,       // more uint8 enables
           CRC_LSB, CRC_MSB]
```

### Set Target Voltage to 12.15V

```
Request:  [0x15, 0x10, 0x04, 0x66, 0x66, 0x42, 0x41, 0xA2, 0x96]
Response: [0x15, 0xF0, 0x01, 0x00, 0x05, 0x8B]
                  ^--- RESPONSE_OK
```

### Enable PSU Output

```
Request:  [0x15, 0x18, 0x01, 0x01, CRC_LSB, CRC_MSB]
Response: [0x15, 0xF0, 0x01, 0x00, CRC_LSB, CRC_MSB]
```

### Reset Energy Counter

```
Request:  [0x15, 0x31, 0x00, CRC_LSB, CRC_MSB]
Response: [0x15, 0xF0, 0x01, 0x00, CRC_LSB, CRC_MSB]
```

---

## Error Handling and Reconnection

### BLE Connection Loss

- NimBLE automatically restarts advertising on disconnect
- The Flutter app should implement auto-reconnection with exponential backoff
- On reconnect, re-subscribe to the Response characteristic notifications

### Request Timeout

- If no notification is received within 2 seconds of writing a request, assume the request was lost
- Retry up to 3 times before reporting an error to the user

### CRC Errors

- If the response fails CRC validation, discard it and retry the request
- If repeated CRC errors occur, disconnect and reconnect

### Invalid Responses

- Check that `packet[0] == 0x15` (protocol ID)
- Check that the response tag matches the request tag (or is `0xF0`/`0xF1`)
- If the response is an error (`0xF1`), display the error code to the user

---

## Version History

| Version | Date | Changes |
|---------|------|---------|
| 1.1 | 2026-02-17 | Added CONFIG_BUNDLE support for reading all configuration values in a single request |

---

## Related Documentation

- `LOKI_PSU_UNIFIED_TLV_PROTOCOL_SPECIFICATION.md` — Full TLV protocol reference
- `src/CommonProtocol.h` — Protocol source of truth (C++)
- `tools/generate_dart_protocol.py` — Dart codegen script
- `src/BLETransport.h` / `src/BLETransport.cpp` — Firmware BLE implementation

// AUTO-GENERATED from CommonProtocol.h — DO NOT EDIT
// Generated on 2026-02-17 08:59:19
// Re-generate: python tools/generate_dart_protocol.py src/CommonProtocol.h --output <path>/common_protocol.dart

/// C++ enum class ProtocolID
class ProtocolID {
  ProtocolID._();  // prevent instantiation

  /// Legacy Bitmain I2C protocol (backward compatible, no CRC)
  static const int bitmain = 0x11;
  /// Alternative Bitmain protocol start byte
  static const int bitmainAlt = 0x55;
  /// Loki TLV protocol for telemetry (transport-agnostic, CRC16)
  static const int lokiTlv = 0x15;
  /// Future: Protobuf for WiFi/BLE (with CRC16)
  static const int protobuf = 0x20;
}

/// C++ enum class ProtocolTag
class ProtocolTag {
  ProtocolTag._();  // prevent instantiation

  // ===== Read-only telemetry (0x01-0x0F) =====
  /// float32, Amps - Current draw from PSU
  static const int measuredPsuOutputCurrent = 0x01;
  /// float32, Watts - Power output
  static const int measuredPsuOutputPower = 0x02;
  /// float32, Volts - Output voltage (measured)
  static const int measuredPsuOutputVoltage = 0x03;
  /// float32, Celsius - Inlet air temperature
  static const int measuredPsuInletTemperature = 0x04;
  /// float32, Celsius - PSU internal temperature
  static const int measuredPsuInternalTemp = 0x05;
  /// float32, Watt-hours - Energy since boot
  static const int totalEnergyWh = 0x06;
  /// Multi-float32 (24 bytes) - All telemetry in one response
  static const int telemetryBundle = 0x0F;
  // ===== Read-write configuration (0x10-0x1F) =====
  /// float32, Volts - Target voltage setpoint
  static const int psuTargetOutputVoltage = 0x10;
  /// uint8, 0/1 - Enable max power shutoff (default ON)
  static const int psuMaxPowerShutoffEnable = 0x11;
  /// float32, Watts - Maximum power threshold
  static const int maxPsuOutputPowerThreshold = 0x12;
  /// uint8, 0/1 - Enable thermostat control (default OFF)
  static const int psuThermostatEnable = 0x13;
  /// float32, Celsius - Target inlet temperature (default 21.0)
  static const int targetPsuInletTemperature = 0x14;
  /// uint8, 0/1 - Enable fan silence mode (default OFF)
  static const int psuSilenceFanEnable = 0x15;
  /// uint8 - Hardware version byte (default 0x75)
  static const int spoofedPsuHardwareModel = 0x16;
  /// uint8 - Firmware version byte (default 0x16)
  static const int spoofedPsuFirmwareVersion = 0x17;
  /// uint8, 0/1 - Enable PSU output (default ON)
  static const int psuOutputEnable = 0x18;
  /// uint8, 0/1 - Enable voltage regulation (default ON)
  static const int psuVoltageRegulationEnable = 0x19;
  /// uint8, 0/1 - Enable spoofing above max voltage (default ON)
  static const int spoofAboveMaxOutputVoltageEnable = 0x1A;
  /// float32, seconds - Power fault timeout (default 10.0s)
  static const int powerFaultTimeout = 0x1B;
  /// uint8, 0/1 - Enable automatic retry after power fault (default OFF)
  static const int automaticRetryAfterPowerFaultEnable = 0x1C;
  /// float32, Celsius - PSU over-temperature threshold (default 95.0°C)
  static const int psuOtpThreshold = 0x1D;
  /// uint8, 0/1 - Enable PSU over-temperature protection (default ON)
  static const int psuOtpEnable = 0x1E;
  /// Multi-mixed (30 bytes) - All configuration in one response
  static const int configBundle = 0x1F;
  // ===== Query (0x20-0x2F) =====
  // PSU_TARGET_OUTPUT_VOLTAGE queries
  /// float32, Volts - Minimum allowed target voltage
  static const int queryPsuTargetOutputVoltageMin = 0x20;
  /// float32, Volts - Maximum allowed target voltage
  static const int queryPsuTargetOutputVoltageMax = 0x21;
  /// float32, Volts - Default target voltage
  static const int queryPsuTargetOutputVoltageDefault = 0x22;
  // MAX_PSU_OUTPUT_POWER_THRESHOLD queries
  /// float32, Watts - Minimum allowed power threshold
  static const int queryMaxPsuOutputPowerThresholdMin = 0x23;
  /// float32, Watts - Maximum allowed power threshold
  static const int queryMaxPsuOutputPowerThresholdMax = 0x24;
  /// float32, Watts - Default power threshold
  static const int queryMaxPsuOutputPowerThresholdDefault = 0x25;
  // TARGET_PSU_INLET_TEMPERATURE queries
  /// float32, Celsius - Minimum allowed inlet temperature
  static const int queryTargetPsuInletTemperatureMin = 0x26;
  /// float32, Celsius - Maximum allowed inlet temperature
  static const int queryTargetPsuInletTemperatureMax = 0x27;
  /// float32, Celsius - Default inlet temperature
  static const int queryTargetPsuInletTemperatureDefault = 0x28;
  // PSU Model Options queries
  /// Multi-byte - All valid hardware versions (10 bytes)
  static const int queryPsuHardwareModelOptions = 0x29;
  /// Multi-byte - All valid firmware versions (3 bytes)
  static const int queryPsuFirmwareVersionOptions = 0x2A;
  // POWER_FAULT_TIMEOUT queries
  /// float32, seconds - Minimum power fault timeout
  static const int queryPowerFaultTimeoutMin = 0x2B;
  /// float32, seconds - Maximum power fault timeout
  static const int queryPowerFaultTimeoutMax = 0x2C;
  /// float32, seconds - Default power fault timeout
  static const int queryPowerFaultTimeoutDefault = 0x2D;
  // PSU_OTP_THRESHOLD queries
  /// float32, Celsius - Minimum PSU OTP threshold
  static const int queryPsuOtpThresholdMin = 0x2E;
  /// float32, Celsius - Maximum PSU OTP threshold
  static const int queryPsuOtpThresholdMax = 0x2F;
  /// float32, Celsius - Default PSU OTP threshold
  static const int queryPsuOtpThresholdDefault = 0x30;
  // ===== Commands (0x31-0x3F) =====
  /// No value (length=0) - Reset energy counter to 0
  static const int cmdResetPsuEnergyTracker = 0x31;
  // ===== Response codes (0xF0-0xFF) =====
  /// uint8_t, 0x00 - Operation successful
  static const int responseOk = 0xF0;
  /// uint8_t, error code - Operation failed (contains StatusCode)
  static const int responseError = 0xF1;
}

/// C++ enum class TelemetryDataType
class TelemetryDataType {
  TelemetryDataType._();  // prevent instantiation

  /// IEEE 754 single precision, little-endian (4 bytes)
  static const int float32 = 0x01;
  /// 32-bit unsigned integer, little-endian (4 bytes)
  static const int uint32 = 0x02;
  /// 16-bit unsigned integer, little-endian (2 bytes)
  static const int uint16 = 0x03;
  /// 8-bit unsigned integer (1 byte)
  static const int uint8 = 0x04;
}

/// Protocol constants from #define directives
class TlvConstants {
  TlvConstants._();

  /// Maximum TLV packet size (bytes)
  static const int tlvMaxPacketSize = 64;
  /// Protocol ID + Tag + Length
  static const int tlvHeaderSize = 3;
  /// CRC16 is 2 bytes
  static const int tlvCrcSize = 2;
  /// Header + CRC (no value)
  static const int tlvMinPacketSize = 5;
  static const int tlvMaxValueSize = 59;
  /// Number of float32 values in telemetry bundle
  static const int telemetryBundleFloatCount = 6;
  /// 24 bytes
  static const int telemetryBundleValueSize = 24;
  /// 30 bytes (5 floats × 4 + 10 uint8s × 1)
  static const int configBundleValueSize = 30;
  /// Number of float32 values in config bundle
  static const int configBundleFloatCount = 5;
  /// Number of uint8 values in config bundle
  static const int configBundleUint8Count = 10;
}

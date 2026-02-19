/// Data model holding the full state of the Loki PSU as seen by the app.
class PsuState {
  // ---------------------------------------------------------------------------
  // Read-only telemetry
  // ---------------------------------------------------------------------------
  final double? outputVoltage; // Volts
  final double? outputCurrent; // Amps
  final double? outputPower; // Watts
  final double? inletTemperature; // Celsius
  final double? internalTemperature; // Celsius
  final double? energyWh; // Watt-hours

  // ---------------------------------------------------------------------------
  // Read-write configuration
  // ---------------------------------------------------------------------------
  final double? targetOutputVoltage; // Volts
  final bool? maxPowerShutoffEnable;
  final double? maxPowerThreshold; // Watts
  final bool? thermostatEnable;
  final double? targetInletTemperature; // Celsius
  final bool? silenceFanEnable;
  final int? spoofedHardwareModel; // uint8
  final int? spoofedFirmwareVersion; // uint8
  final bool? outputEnable;
  final bool? voltageRegulationEnable;
  final bool? spoofAboveMaxVoltageEnable;
  final double? powerFaultTimeout; // seconds
  final bool? autoRetryAfterFaultEnable;
  final double? otpThreshold; // Celsius
  final bool? otpEnable;

  // ---------------------------------------------------------------------------
  // Remote configuration gate
  // ---------------------------------------------------------------------------
  final bool? allowRemoteConfig;

  const PsuState({
    this.outputVoltage,
    this.outputCurrent,
    this.outputPower,
    this.inletTemperature,
    this.internalTemperature,
    this.energyWh,
    this.targetOutputVoltage,
    this.maxPowerShutoffEnable,
    this.maxPowerThreshold,
    this.thermostatEnable,
    this.targetInletTemperature,
    this.silenceFanEnable,
    this.spoofedHardwareModel,
    this.spoofedFirmwareVersion,
    this.outputEnable,
    this.voltageRegulationEnable,
    this.spoofAboveMaxVoltageEnable,
    this.powerFaultTimeout,
    this.autoRetryAfterFaultEnable,
    this.otpThreshold,
    this.otpEnable,
    this.allowRemoteConfig,
  });

  /// Create a copy with selected fields replaced.
  PsuState copyWith({
    double? outputVoltage,
    double? outputCurrent,
    double? outputPower,
    double? inletTemperature,
    double? internalTemperature,
    double? energyWh,
    double? targetOutputVoltage,
    bool? maxPowerShutoffEnable,
    double? maxPowerThreshold,
    bool? thermostatEnable,
    double? targetInletTemperature,
    bool? silenceFanEnable,
    int? spoofedHardwareModel,
    int? spoofedFirmwareVersion,
    bool? outputEnable,
    bool? voltageRegulationEnable,
    bool? spoofAboveMaxVoltageEnable,
    double? powerFaultTimeout,
    bool? autoRetryAfterFaultEnable,
    double? otpThreshold,
    bool? otpEnable,
    bool? allowRemoteConfig,
  }) {
    return PsuState(
      outputVoltage: outputVoltage ?? this.outputVoltage,
      outputCurrent: outputCurrent ?? this.outputCurrent,
      outputPower: outputPower ?? this.outputPower,
      inletTemperature: inletTemperature ?? this.inletTemperature,
      internalTemperature: internalTemperature ?? this.internalTemperature,
      energyWh: energyWh ?? this.energyWh,
      targetOutputVoltage: targetOutputVoltage ?? this.targetOutputVoltage,
      maxPowerShutoffEnable:
          maxPowerShutoffEnable ?? this.maxPowerShutoffEnable,
      maxPowerThreshold: maxPowerThreshold ?? this.maxPowerThreshold,
      thermostatEnable: thermostatEnable ?? this.thermostatEnable,
      targetInletTemperature:
          targetInletTemperature ?? this.targetInletTemperature,
      silenceFanEnable: silenceFanEnable ?? this.silenceFanEnable,
      spoofedHardwareModel:
          spoofedHardwareModel ?? this.spoofedHardwareModel,
      spoofedFirmwareVersion:
          spoofedFirmwareVersion ?? this.spoofedFirmwareVersion,
      outputEnable: outputEnable ?? this.outputEnable,
      voltageRegulationEnable:
          voltageRegulationEnable ?? this.voltageRegulationEnable,
      spoofAboveMaxVoltageEnable:
          spoofAboveMaxVoltageEnable ?? this.spoofAboveMaxVoltageEnable,
      powerFaultTimeout: powerFaultTimeout ?? this.powerFaultTimeout,
      autoRetryAfterFaultEnable:
          autoRetryAfterFaultEnable ?? this.autoRetryAfterFaultEnable,
      otpThreshold: otpThreshold ?? this.otpThreshold,
      otpEnable: otpEnable ?? this.otpEnable,
      allowRemoteConfig: allowRemoteConfig ?? this.allowRemoteConfig,
    );
  }

  /// Empty state used before connecting to a PSU.
  static const PsuState empty = PsuState();
}

import 'dart:async';

import 'package:flutter/foundation.dart';

import '../ble/ble_service.dart';
import '../models/psu_state.dart';
import '../protocol/common_protocol.dart';
import '../protocol/tlv_codec.dart';

/// ChangeNotifier that holds the full [PsuState], polls telemetry,
/// reads configuration on connect, and exposes write methods for configs.
class PsuStateProvider extends ChangeNotifier {
  final BleService _bleService;
  Timer? _pollTimer;
  StreamSubscription<BleConnectionState>? _stateSub;

  PsuState _state = PsuState.empty;
  PsuState get state => _state;

  bool _loading = false;
  bool get loading => _loading;

  String? _error;
  String? get error => _error;

  PsuStateProvider(this._bleService) {
    _stateSub = _bleService.stateStream.listen(_onConnectionStateChanged);
  }

  // ---------------------------------------------------------------------------
  // Connection state handling
  // ---------------------------------------------------------------------------

  void _onConnectionStateChanged(BleConnectionState connState) {
    if (connState == BleConnectionState.connected) {
      _onConnected();
    } else if (connState == BleConnectionState.disconnected) {
      _onDisconnected();
    }
  }

  Future<void> _onConnected() async {
    // Start polling telemetry immediately every 1 second.
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(
      const Duration(seconds: 1),
      (_) => refreshTelemetry(),
    );
    
    // Fetch telemetry and configs in parallel for faster dashboard load.
    // Telemetry will be visible in ~1s, configs will follow.
    unawaited(refreshTelemetry());
    unawaited(refreshAllConfigs());
  }

  void _onDisconnected() {
    _pollTimer?.cancel();
    _pollTimer = null;
    _state = PsuState.empty;
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // Telemetry
  // ---------------------------------------------------------------------------

  Future<void> refreshTelemetry() async {
    if (_bleService.state != BleConnectionState.connected) return;
    try {
      final response = await _bleService.sendRequest(
        TlvRequestBuilder.readRequest(ProtocolTag.telemetryBundle),
      );
      if (response.tag == ProtocolTag.telemetryBundle) {
        final bundle = response.asTelemetryBundle;
        _state = _state.copyWith(
          outputVoltage: bundle.voltage,
          outputCurrent: bundle.current,
          outputPower: bundle.power,
          inletTemperature: bundle.inletTemperature,
          internalTemperature: bundle.internalTemperature,
          energyWh: bundle.energyWh,
        );
        _error = null;
        notifyListeners();
      }
    } catch (e) {
      _error = 'Telemetry error: $e';
      notifyListeners();
    }
  }

  // ---------------------------------------------------------------------------
  // Configuration reads
  // ---------------------------------------------------------------------------

  Future<void> refreshAllConfigs() async {
    _loading = true;
    notifyListeners();

    try {
      // Try CONFIG_BUNDLE first (single request, ~500ms).
      // Falls back to individual reads if firmware doesn't support it yet.
      if (await _tryConfigBundle()) {
        _error = null;
      } else {
        await _readConfigsIndividually();
        _error = null;
      }
    } catch (e) {
      _error = 'Config read error: $e';
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  /// Attempt to load all configs via CONFIG_BUNDLE.
  /// Returns true on success, false if the firmware doesn't support it.
  Future<bool> _tryConfigBundle() async {
    try {
      final response = await _bleService.sendRequest(
        TlvRequestBuilder.readRequest(ProtocolTag.configBundle),
      );

      if (response.tag == ProtocolTag.configBundle) {
        final bundle = response.asConfigBundle;
        _state = _state.copyWith(
          targetOutputVoltage: bundle.targetOutputVoltage,
          maxPowerThreshold: bundle.maxPowerThreshold,
          targetInletTemperature: bundle.targetInletTemperature,
          powerFaultTimeout: bundle.powerFaultTimeout,
          otpThreshold: bundle.otpThreshold,
          maxPowerShutoffEnable: bundle.maxPowerShutoffEnable,
          thermostatEnable: bundle.thermostatEnable,
          silenceFanEnable: bundle.silenceFanEnable,
          outputEnable: bundle.outputEnable,
          voltageRegulationEnable: bundle.voltageRegulationEnable,
          spoofAboveMaxVoltageEnable: bundle.spoofAboveMaxVoltageEnable,
          autoRetryAfterFaultEnable: bundle.autoRetryAfterFaultEnable,
          otpEnable: bundle.otpEnable,
          spoofedHardwareModel: bundle.spoofedHardwareModel,
          spoofedFirmwareVersion: bundle.spoofedFirmwareVersion,
        );
        return true;
      }

      // Got an error response (e.g. ERROR_INVALID_TAG) — not supported
      return false;
    } catch (_) {
      // Timeout or other error — not supported
      return false;
    }
  }

  /// Fallback: read each config value individually (15 sequential requests).
  Future<void> _readConfigsIndividually() async {
    // Float32 configs
    _state = _state.copyWith(
      targetOutputVoltage: await _readFloat(ProtocolTag.psuTargetOutputVoltage),
      maxPowerThreshold: await _readFloat(ProtocolTag.maxPsuOutputPowerThreshold),
      targetInletTemperature: await _readFloat(ProtocolTag.targetPsuInletTemperature),
      powerFaultTimeout: await _readFloat(ProtocolTag.powerFaultTimeout),
      otpThreshold: await _readFloat(ProtocolTag.psuOtpThreshold),
    );

    // Uint8 / boolean configs
    _state = _state.copyWith(
      maxPowerShutoffEnable: await _readBool(ProtocolTag.psuMaxPowerShutoffEnable),
      thermostatEnable: await _readBool(ProtocolTag.psuThermostatEnable),
      silenceFanEnable: await _readBool(ProtocolTag.psuSilenceFanEnable),
      outputEnable: await _readBool(ProtocolTag.psuOutputEnable),
      voltageRegulationEnable: await _readBool(ProtocolTag.psuVoltageRegulationEnable),
      spoofAboveMaxVoltageEnable: await _readBool(ProtocolTag.spoofAboveMaxOutputVoltageEnable),
      autoRetryAfterFaultEnable: await _readBool(ProtocolTag.automaticRetryAfterPowerFaultEnable),
      otpEnable: await _readBool(ProtocolTag.psuOtpEnable),
    );

    // Uint8 non-boolean configs
    _state = _state.copyWith(
      spoofedHardwareModel: await _readUint8(ProtocolTag.spoofedPsuHardwareModel),
      spoofedFirmwareVersion: await _readUint8(ProtocolTag.spoofedPsuFirmwareVersion),
    );
  }

  Future<double> _readFloat(int tag) async {
    final resp = await _bleService.sendRequest(TlvRequestBuilder.readRequest(tag));
    return resp.asFloat;
  }

  Future<bool> _readBool(int tag) async {
    final resp = await _bleService.sendRequest(TlvRequestBuilder.readRequest(tag));
    return resp.asUint8 != 0;
  }

  Future<int> _readUint8(int tag) async {
    final resp = await _bleService.sendRequest(TlvRequestBuilder.readRequest(tag));
    return resp.asUint8;
  }

  // ---------------------------------------------------------------------------
  // Configuration writes
  // ---------------------------------------------------------------------------

  /// Write a float32 config and refresh its local value on success.
  Future<void> writeFloat(int tag, double value) async {
    try {
      final resp = await _bleService.sendRequest(
        TlvRequestBuilder.writeFloat(tag, value),
      );
      if (resp.isOk) {
        // Re-read the config to confirm.
        final updated = await _readFloat(tag);
        _updateConfigFloat(tag, updated);
      } else if (resp.isError) {
        _error = 'Write failed: error 0x${resp.errorCode.toRadixString(16)}';
      }
    } catch (e) {
      _error = 'Write error: $e';
    }
    notifyListeners();
  }

  /// Write a uint8 boolean config (0 or 1) and refresh on success.
  Future<void> writeBool(int tag, bool value) async {
    try {
      final resp = await _bleService.sendRequest(
        TlvRequestBuilder.writeUint8(tag, value ? 1 : 0),
      );
      if (resp.isOk) {
        final updated = await _readBool(tag);
        _updateConfigBool(tag, updated);
      } else if (resp.isError) {
        _error = 'Write failed: error 0x${resp.errorCode.toRadixString(16)}';
      }
    } catch (e) {
      _error = 'Write error: $e';
    }
    notifyListeners();
  }

  /// Write a uint8 config (non-boolean) and refresh on success.
  Future<void> writeUint8(int tag, int value) async {
    try {
      final resp = await _bleService.sendRequest(
        TlvRequestBuilder.writeUint8(tag, value),
      );
      if (resp.isOk) {
        final updated = await _readUint8(tag);
        _updateConfigUint8(tag, updated);
      } else if (resp.isError) {
        _error = 'Write failed: error 0x${resp.errorCode.toRadixString(16)}';
      }
    } catch (e) {
      _error = 'Write error: $e';
    }
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // Commands
  // ---------------------------------------------------------------------------

  Future<void> resetEnergyCounter() async {
    try {
      final resp = await _bleService.sendRequest(
        TlvRequestBuilder.command(ProtocolTag.cmdResetPsuEnergyTracker),
      );
      if (resp.isOk) {
        _state = _state.copyWith(energyWh: 0.0);
        _error = null;
      } else if (resp.isError) {
        _error = 'Reset failed: error 0x${resp.errorCode.toRadixString(16)}';
      }
    } catch (e) {
      _error = 'Reset error: $e';
    }
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // Private helpers
  // ---------------------------------------------------------------------------

  void _updateConfigFloat(int tag, double value) {
    switch (tag) {
      case ProtocolTag.psuTargetOutputVoltage:
        _state = _state.copyWith(targetOutputVoltage: value);
      case ProtocolTag.maxPsuOutputPowerThreshold:
        _state = _state.copyWith(maxPowerThreshold: value);
      case ProtocolTag.targetPsuInletTemperature:
        _state = _state.copyWith(targetInletTemperature: value);
      case ProtocolTag.powerFaultTimeout:
        _state = _state.copyWith(powerFaultTimeout: value);
      case ProtocolTag.psuOtpThreshold:
        _state = _state.copyWith(otpThreshold: value);
    }
  }

  void _updateConfigBool(int tag, bool value) {
    switch (tag) {
      case ProtocolTag.psuMaxPowerShutoffEnable:
        _state = _state.copyWith(maxPowerShutoffEnable: value);
      case ProtocolTag.psuThermostatEnable:
        _state = _state.copyWith(thermostatEnable: value);
      case ProtocolTag.psuSilenceFanEnable:
        _state = _state.copyWith(silenceFanEnable: value);
      case ProtocolTag.psuOutputEnable:
        _state = _state.copyWith(outputEnable: value);
      case ProtocolTag.psuVoltageRegulationEnable:
        _state = _state.copyWith(voltageRegulationEnable: value);
      case ProtocolTag.spoofAboveMaxOutputVoltageEnable:
        _state = _state.copyWith(spoofAboveMaxVoltageEnable: value);
      case ProtocolTag.automaticRetryAfterPowerFaultEnable:
        _state = _state.copyWith(autoRetryAfterFaultEnable: value);
      case ProtocolTag.psuOtpEnable:
        _state = _state.copyWith(otpEnable: value);
    }
  }

  void _updateConfigUint8(int tag, int value) {
    switch (tag) {
      case ProtocolTag.spoofedPsuHardwareModel:
        _state = _state.copyWith(spoofedHardwareModel: value);
      case ProtocolTag.spoofedPsuFirmwareVersion:
        _state = _state.copyWith(spoofedFirmwareVersion: value);
    }
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _stateSub?.cancel();
    super.dispose();
  }
}

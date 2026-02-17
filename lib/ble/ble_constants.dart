import 'package:flutter_blue_plus/flutter_blue_plus.dart';

/// BLE GATT UUIDs and constants for the Loki PSU service.
class BleConstants {
  BleConstants._();

  /// Loki PSU primary service UUID.
  static const String serviceUuidString =
      '4c6f6b69-5053-5500-0001-000000000000';

  /// TLV Request characteristic UUID (Write).
  static const String requestCharUuidString =
      '4c6f6b69-5053-5500-0002-000000000000';

  /// TLV Response characteristic UUID (Notify, Read).
  static const String responseCharUuidString =
      '4c6f6b69-5053-5500-0003-000000000000';

  /// Typed GUID objects for flutter_blue_plus.
  static final Guid serviceUuid = Guid(serviceUuidString);
  static final Guid requestCharUuid = Guid(requestCharUuidString);
  static final Guid responseCharUuid = Guid(responseCharUuidString);

  /// Expected BLE advertised device name.
  static const String deviceName = 'Loki PSU';

  /// MTU to request after connection.
  static const int requestedMtu = 256;

  /// Timeout for a single TLV request-response round trip.
  static const Duration requestTimeout = Duration(seconds: 2);

  /// Maximum retries for a failed request.
  static const int maxRetries = 3;
}

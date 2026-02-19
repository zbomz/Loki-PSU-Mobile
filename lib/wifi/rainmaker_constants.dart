/// RainMaker REST API constants and firmware parameter name mappings.
///
/// The base URL points to Espressif's RainMaker cloud.  All endpoints
/// are documented at https://swaggerapis.rainmaker.espressif.com/
class RainMakerConstants {
  RainMakerConstants._();

  /// RainMaker cloud API base URL.
  static const String baseUrl = 'https://rainmaker.espressif.com/v1';

  // ---- Auth endpoints ----
  static const String loginEndpoint = '/login';
  static const String logoutEndpoint = '/logout';
  static const String createUserEndpoint = '/user';
  static const String tokenEndpoint = '/login'; // refresh via same endpoint
  static const String forgotPasswordEndpoint = '/forgotpassword';

  // ---- Node endpoints ----
  static const String nodesEndpoint = '/user/nodes';
  static const String nodeConfigEndpoint = '/user/nodes/config';
  static const String nodeParamsEndpoint = '/user/nodes/params';

  // ---- Provisioning ----
  /// Proof of Possession expected by the firmware.
  static const String provPop = 'loki1234';

  /// BLE provisioning service name prefix.
  static const String provServicePrefix = 'PROV_LOKI_';

  // ---- OAuth / Cognito constants ----
  /// Cognito App Client ID for the public Espressif-hosted RainMaker cloud.
  /// Source: espressif/esp-rainmaker-ios → Configuration.plist (AWS Configuration)
  static const String cognitoClientId = '1h7ujqjs8140n17v0ahb4n51m2';

  /// Cognito Hosted UI base URL for the public RainMaker cloud (no trailing slash).
  /// Source: espressif/esp-rainmaker-ios → Configuration.plist (Authentication URL)
  static const String cognitoDomain = 'https://3pauth.rainmaker.espressif.com';

  /// Redirect URI registered with the Cognito app client.
  /// Must exactly match what is registered in the Cognito app client's Allowed
  /// Callback URLs.  The official ESP RainMaker app client uses this URI.
  static const String oauthRedirectUri =
      'com.espressif.rainmaker.softap://success';

  /// URL scheme portion of [oauthRedirectUri], used by flutter_web_auth_2
  /// and platform intent/URL-scheme registrations.
  static const String oauthCallbackScheme = 'com.espressif.rainmaker.softap';

  /// OAuth scopes requested from Cognito.
  static const String oauthScopes = 'openid email profile';

  // ---- Secure storage keys ----
  static const String accessTokenKey = 'rm_access_token';
  static const String refreshTokenKey = 'rm_refresh_token';
  static const String idTokenKey = 'rm_id_token';
  static const String userEmailKey = 'rm_user_email';

  // ---- Firmware RainMaker param names → PsuState field map ----
  // Telemetry (read-only)
  static const String paramVoltage = 'voltage';
  static const String paramCurrent = 'current';
  static const String paramPower = 'power';
  static const String paramInletTemp = 'inlet_temp';
  static const String paramInternalTemp = 'internal_temp';
  static const String paramEnergyWh = 'energy_wh';

  // Configuration (read-write)
  static const String paramTargetVoltage = 'target_voltage';
  static const String paramMaxPowerThreshold = 'max_power_threshold';
  static const String paramTargetInletTemp = 'target_inlet_temp';
  static const String paramPowerFaultTimeout = 'power_fault_timeout';
  static const String paramOtpThreshold = 'otp_threshold';
  static const String paramMaxPowerShutoffEn = 'max_power_shutoff_en';
  static const String paramThermostatEn = 'thermostat_en';
  static const String paramSilenceFanEn = 'silence_fan_en';
  static const String paramOutputEn = 'output_en';
  static const String paramVoltageRegEn = 'voltage_reg_en';
  static const String paramAutoRetryEn = 'auto_retry_en';
  static const String paramOtpEn = 'otp_en';
  static const String paramAllowRemoteConfig = 'allow_remote_config';

  /// RainMaker device name used in firmware.
  static const String deviceName = 'Loki PSU';
}

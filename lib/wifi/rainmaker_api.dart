import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_web_auth_2/flutter_web_auth_2.dart';
import 'package:http/http.dart' as http;

import '../models/psu_state.dart';
import 'rainmaker_constants.dart';

/// Lightweight wrapper around the ESP RainMaker REST API.
///
/// Provides:
///  - User authentication (login / signup / token refresh / logout)
///  - Node discovery (list user's claimed nodes)
///  - Param reads (telemetry + config)
///  - Param writes (config updates, gated by allow_remote_config on firmware)
class RainMakerApiClient {
  final FlutterSecureStorage _storage;
  final http.Client _http;

  String? _accessToken;
  String? _refreshToken;
  String? _idToken; // ignore: unused_field
  String? _userEmail;

  RainMakerApiClient({
    FlutterSecureStorage? storage,
    http.Client? httpClient,
  })  : _storage = storage ?? const FlutterSecureStorage(),
        _http = httpClient ?? http.Client();

  // ---------------------------------------------------------------------------
  // Token helpers
  // ---------------------------------------------------------------------------

  bool get isLoggedIn => _accessToken != null;
  String? get userEmail => _userEmail;

  /// Load persisted tokens from secure storage on app startup.
  Future<void> loadTokens() async {
    _accessToken =
        await _storage.read(key: RainMakerConstants.accessTokenKey);
    _refreshToken =
        await _storage.read(key: RainMakerConstants.refreshTokenKey);
    _idToken = await _storage.read(key: RainMakerConstants.idTokenKey);
    _userEmail = await _storage.read(key: RainMakerConstants.userEmailKey);
  }

  Future<void> _saveTokens({
    required String accessToken,
    required String refreshToken,
    required String idToken,
  }) async {
    _accessToken = accessToken;
    _refreshToken = refreshToken;
    _idToken = idToken;
    await _storage.write(
        key: RainMakerConstants.accessTokenKey, value: accessToken);
    await _storage.write(
        key: RainMakerConstants.refreshTokenKey, value: refreshToken);
    await _storage.write(
        key: RainMakerConstants.idTokenKey, value: idToken);
  }

  Future<void> _clearTokens() async {
    _accessToken = null;
    _refreshToken = null;
    _idToken = null;
    _userEmail = null;
    await _storage.delete(key: RainMakerConstants.accessTokenKey);
    await _storage.delete(key: RainMakerConstants.refreshTokenKey);
    await _storage.delete(key: RainMakerConstants.idTokenKey);
    await _storage.delete(key: RainMakerConstants.userEmailKey);
    await _storage.delete(key: RainMakerConstants.socialLoginKey);
  }

  Map<String, String> get _authHeaders => {
        'Content-Type': 'application/json',
        if (_accessToken != null) 'Authorization': _accessToken!,
      };

  // ---------------------------------------------------------------------------
  // Auth
  // ---------------------------------------------------------------------------

  /// Create a new RainMaker account.
  ///
  /// Returns the verification status message.
  /// The user must verify their email before logging in.
  Future<String> createUser(String email, String password) async {
    final url =
        Uri.parse('${RainMakerConstants.baseUrl}${RainMakerConstants.createUserEndpoint}');
    final body = jsonEncode({
      'user_name': email,
      'password': password,
    });

    final response = await _http.post(url,
        headers: {'Content-Type': 'application/json'}, body: body);

    if (response.statusCode == 200 || response.statusCode == 201) {
      return 'Account created. Please verify your email before signing in.';
    }

    final data = jsonDecode(response.body);
    throw RainMakerApiException(
        data['description'] ?? 'Failed to create account',
        response.statusCode);
  }

  /// Confirm a new account with the verification code sent to email.
  Future<void> confirmUser(String email, String verificationCode) async {
    final url =
        Uri.parse('${RainMakerConstants.baseUrl}${RainMakerConstants.createUserEndpoint}');
    final body = jsonEncode({
      'user_name': email,
      'verification_code': verificationCode,
    });

    final response = await _http.put(url,
        headers: {'Content-Type': 'application/json'}, body: body);

    if (response.statusCode != 200) {
      final data = jsonDecode(response.body);
      throw RainMakerApiException(
          data['description'] ?? 'Verification failed', response.statusCode);
    }
  }

  /// Log in with email + password and store the tokens.
  Future<void> login(String email, String password) async {
    final url =
        Uri.parse('${RainMakerConstants.baseUrl}${RainMakerConstants.loginEndpoint}');
    final body = jsonEncode({
      'user_name': email,
      'password': password,
    });

    final response = await _http.post(url,
        headers: {'Content-Type': 'application/json'}, body: body);

    if (response.statusCode != 200) {
      final data = jsonDecode(response.body);
      throw RainMakerApiException(
          data['description'] ?? 'Login failed', response.statusCode);
    }

    final data = jsonDecode(response.body);
    await _saveTokens(
      accessToken: data['accesstoken'],
      refreshToken: data['refreshtoken'],
      idToken: data['idtoken'],
    );
    _userEmail = email;
    await _storage.write(
        key: RainMakerConstants.userEmailKey, value: email);
  }

  /// Sign in via a social identity provider through the Cognito Hosted UI.
  ///
  /// [identityProvider] must be one of: `'Google'`, `'GitHub'`,
  /// `'SignInWithApple'` — these are the Cognito identity provider names.
  ///
  /// Opens a system browser to the Cognito Hosted UI, waits for the OAuth
  /// redirect, exchanges the authorization code for Cognito tokens, and
  /// persists them exactly as the password-based [login] does.
  ///
  /// Throws [RainMakerApiException] on any failure.
  Future<void> loginWithSocialProvider(String identityProvider) async {
    // 1. Build the Cognito Hosted UI authorization URL.
    final authUri = Uri.parse(
      '${RainMakerConstants.cognitoDomain}/oauth2/authorize'
      '?response_type=code'
      '&client_id=${RainMakerConstants.cognitoClientId}'
      '&redirect_uri=${Uri.encodeComponent(RainMakerConstants.oauthRedirectUri)}'
      '&identity_provider=$identityProvider'
      '&scope=${Uri.encodeComponent(RainMakerConstants.oauthScopes)}',
    );

    // 2. Open the browser and wait for the OAuth redirect.
    final String redirectResult;
    try {
      redirectResult = await FlutterWebAuth2.authenticate(
        url: authUri.toString(),
        callbackUrlScheme: RainMakerConstants.oauthCallbackScheme,
      );
    } catch (e) {
      throw RainMakerApiException('Social sign-in was cancelled or failed: $e', 0);
    }

    // 3. Extract the authorization code from the redirect URI.
    final redirectUri = Uri.parse(redirectResult);
    final code = redirectUri.queryParameters['code'];
    if (code == null || code.isEmpty) {
      final error = redirectUri.queryParameters['error_description'] ??
          redirectUri.queryParameters['error'] ??
          'No authorization code received';
      throw RainMakerApiException(error, 0);
    }

    // 4. Exchange the authorization code for Cognito tokens.
    final tokenUri =
        Uri.parse('${RainMakerConstants.cognitoDomain}/oauth2/token');
    final tokenResponse = await _http.post(
      tokenUri,
      headers: {'Content-Type': 'application/x-www-form-urlencoded'},
      body: {
        'grant_type': 'authorization_code',
        'client_id': RainMakerConstants.cognitoClientId,
        'redirect_uri': RainMakerConstants.oauthRedirectUri,
        'code': code,
      },
    );

    if (tokenResponse.statusCode != 200) {
      final data = jsonDecode(tokenResponse.body);
      throw RainMakerApiException(
        data['error_description'] ?? data['error'] ?? 'Token exchange failed',
        tokenResponse.statusCode,
      );
    }

    final tokenData = jsonDecode(tokenResponse.body);
    // The RainMaker REST API validates the Cognito ID token (a signed JWT
    // containing user-identity claims) in the Authorization header — not the
    // opaque Cognito access token.  Store id_token as the credential used
    // for every authenticated API call.
    await _saveTokens(
      accessToken: tokenData['id_token'] as String,
      refreshToken: tokenData['refresh_token'] as String,
      idToken: tokenData['id_token'] as String,
    );
    // Mark this session as a social login so refreshAccessToken() routes
    // to the Cognito /oauth2/token endpoint instead of RainMaker's /login.
    await _storage.write(
        key: RainMakerConstants.socialLoginKey, value: 'true');

    // 5. Attempt to extract user email from the ID token (JWT middle segment).
    try {
      final parts = (tokenData['id_token'] as String).split('.');
      if (parts.length == 3) {
        final payload = String.fromCharCodes(
          base64Url.decode(base64Url.normalize(parts[1])),
        );
        final claims = jsonDecode(payload) as Map<String, dynamic>;
        final email =
            claims['email'] as String? ?? claims['cognito:username'] as String?;
        if (email != null) {
          _userEmail = email;
          await _storage.write(
              key: RainMakerConstants.userEmailKey, value: email);
        }
      }
    } catch (_) {
      // Email extraction is best-effort; login still succeeds without it.
    }
  }

  /// Refresh the access token using the stored refresh token.
  ///
  /// Social-login sessions (Google / GitHub / Apple) use the Cognito Hosted UI
  /// OAuth endpoint; password-based sessions use the RainMaker `/login` endpoint.
  Future<void> refreshAccessToken() async {
    if (_refreshToken == null) {
      throw RainMakerApiException('No refresh token available', 401);
    }

    final isSocial =
        await _storage.read(key: RainMakerConstants.socialLoginKey) == 'true';

    if (isSocial) {
      // ---- Social login: refresh via Cognito Hosted UI ----
      final tokenUri =
          Uri.parse('${RainMakerConstants.cognitoDomain}/oauth2/token');
      final response = await _http.post(
        tokenUri,
        headers: {'Content-Type': 'application/x-www-form-urlencoded'},
        body: {
          'grant_type': 'refresh_token',
          'client_id': RainMakerConstants.cognitoClientId,
          'refresh_token': _refreshToken!,
        },
      );

      if (response.statusCode != 200) {
        await _clearTokens();
        throw RainMakerApiException(
            'Session expired. Please log in again.', response.statusCode);
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      // Cognito refresh does NOT return a new refresh_token — keep the old one.
      // Use the new id_token as the API credential (same logic as initial login).
      await _saveTokens(
        accessToken: data['id_token'] as String,
        refreshToken: _refreshToken!,
        idToken: data['id_token'] as String,
      );
    } else {
      // ---- Password login: refresh via RainMaker endpoint ----
      final url = Uri.parse(
          '${RainMakerConstants.baseUrl}${RainMakerConstants.tokenEndpoint}');
      final body = jsonEncode({'refreshtoken': _refreshToken});

      final response = await _http.post(url,
          headers: {'Content-Type': 'application/json'}, body: body);

      if (response.statusCode != 200) {
        // Refresh failed — force re-login
        await _clearTokens();
        throw RainMakerApiException(
            'Session expired. Please log in again.', response.statusCode);
      }

      final data = jsonDecode(response.body);
      await _saveTokens(
        accessToken: data['accesstoken'],
        refreshToken: data['refreshtoken'],
        idToken: data['idtoken'],
      );
    }
  }

  /// Log out and clear stored tokens.
  Future<void> logout() async {
    await _clearTokens();
  }

  // ---------------------------------------------------------------------------
  // Nodes
  // ---------------------------------------------------------------------------

  /// Get the list of node IDs associated with this user.
  Future<List<String>> getNodeIds() async {
    final url = Uri.parse(
        '${RainMakerConstants.baseUrl}${RainMakerConstants.nodesEndpoint}');
    final response = await _authenticatedGet(url);
    final data = jsonDecode(response.body);

    if (data['nodes'] != null) {
      return List<String>.from(data['nodes']);
    }
    return [];
  }

  /// Get the configuration (device list, param definitions) for a node.
  Future<Map<String, dynamic>> getNodeConfig(String nodeId) async {
    final url = Uri.parse(
        '${RainMakerConstants.baseUrl}${RainMakerConstants.nodeConfigEndpoint}?node_id=$nodeId');
    final response = await _authenticatedGet(url);
    return jsonDecode(response.body);
  }

  /// Get current parameter values for a node.
  ///
  /// Returns the raw JSON map:
  /// ```json
  /// { "Loki PSU": { "voltage": 12.5, "current": 3.2, ... } }
  /// ```
  Future<Map<String, dynamic>> getNodeParams(String nodeId) async {
    final url = Uri.parse(
        '${RainMakerConstants.baseUrl}${RainMakerConstants.nodeParamsEndpoint}?node_id=$nodeId');
    final response = await _authenticatedGet(url);
    return jsonDecode(response.body);
  }

  /// Write parameter values to a node.
  ///
  /// [params] should be a map like:
  /// ```dart
  /// { "Loki PSU": { "target_voltage": 13.0 } }
  /// ```
  Future<void> setNodeParams(
      String nodeId, Map<String, dynamic> params) async {
    final url = Uri.parse(
        '${RainMakerConstants.baseUrl}${RainMakerConstants.nodeParamsEndpoint}?node_id=$nodeId');
    final response = await _authenticatedPut(url, params);

    if (response.statusCode != 200) {
      throw RainMakerApiException(
          _safeErrorMessage(response), response.statusCode);
    }
  }

  // ---------------------------------------------------------------------------
  // Higher-level helpers
  // ---------------------------------------------------------------------------

  /// Parse node params JSON into a [PsuState] update.
  ///
  /// The RainMaker response nests params under the device name:
  /// `{ "Loki PSU": { "voltage": 12.5, ... } }`
  PsuState parseNodeParamsToState(Map<String, dynamic> raw) {
    // Find the device params (may be nested under device name)
    Map<String, dynamic> params;
    if (raw.containsKey(RainMakerConstants.deviceName)) {
      params = Map<String, dynamic>.from(raw[RainMakerConstants.deviceName]);
    } else {
      // Flat structure or unknown device name — try using raw directly
      params = raw;
    }

    return PsuState(
      // Telemetry
      outputVoltage: _toDouble(params[RainMakerConstants.paramVoltage]),
      outputCurrent: _toDouble(params[RainMakerConstants.paramCurrent]),
      outputPower: _toDouble(params[RainMakerConstants.paramPower]),
      inletTemperature: _toDouble(params[RainMakerConstants.paramInletTemp]),
      internalTemperature:
          _toDouble(params[RainMakerConstants.paramInternalTemp]),
      energyWh: _toDouble(params[RainMakerConstants.paramEnergyWh]),
      // Config
      targetOutputVoltage:
          _toDouble(params[RainMakerConstants.paramTargetVoltage]),
      maxPowerThreshold:
          _toDouble(params[RainMakerConstants.paramMaxPowerThreshold]),
      targetInletTemperature:
          _toDouble(params[RainMakerConstants.paramTargetInletTemp]),
      powerFaultTimeout:
          _toDouble(params[RainMakerConstants.paramPowerFaultTimeout]),
      otpThreshold: _toDouble(params[RainMakerConstants.paramOtpThreshold]),
      maxPowerShutoffEnable:
          _toBool(params[RainMakerConstants.paramMaxPowerShutoffEn]),
      thermostatEnable:
          _toBool(params[RainMakerConstants.paramThermostatEn]),
      silenceFanEnable:
          _toBool(params[RainMakerConstants.paramSilenceFanEn]),
      outputEnable: _toBool(params[RainMakerConstants.paramOutputEn]),
      voltageRegulationEnable:
          _toBool(params[RainMakerConstants.paramVoltageRegEn]),
      autoRetryAfterFaultEnable:
          _toBool(params[RainMakerConstants.paramAutoRetryEn]),
      otpEnable: _toBool(params[RainMakerConstants.paramOtpEn]),
      allowRemoteConfig:
          _toBool(params[RainMakerConstants.paramAllowRemoteConfig]),
    );
  }

  /// Build a param-write payload map for a single config key.
  Map<String, dynamic> buildParamPayload(
      String paramName, dynamic value) {
    return {
      RainMakerConstants.deviceName: {paramName: value},
    };
  }

  // ---------------------------------------------------------------------------
  // Private helpers
  // ---------------------------------------------------------------------------

  Future<http.Response> _authenticatedGet(Uri url) async {
    var response = await _http.get(url, headers: _authHeaders);

    // Retry once with refreshed token on 401
    if (response.statusCode == 401) {
      await refreshAccessToken();
      response = await _http.get(url, headers: _authHeaders);
    }

    if (response.statusCode != 200) {
      throw RainMakerApiException(
          _safeErrorMessage(response), response.statusCode);
    }

    return response;
  }

  Future<http.Response> _authenticatedPut(
      Uri url, Map<String, dynamic> body) async {
    var response = await _http.put(url,
        headers: _authHeaders, body: jsonEncode(body));

    if (response.statusCode == 401) {
      await refreshAccessToken();
      response = await _http.put(url,
          headers: _authHeaders, body: jsonEncode(body));
    }

    return response;
  }

  /// Safely extract an error description from [response].
  ///
  /// Falls back to a generic message when the body is not valid JSON
  /// (e.g. the server returned an HTML error page).
  static String _safeErrorMessage(http.Response response) {
    try {
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      return data['description'] as String? ?? 'API error ${response.statusCode}';
    } catch (_) {
      return 'API error ${response.statusCode} (unexpected server response)';
    }
  }

  static double? _toDouble(dynamic v) {
    if (v == null) return null;
    if (v is double) return v;
    if (v is int) return v.toDouble();
    if (v is String) return double.tryParse(v);
    return null;
  }

  static bool? _toBool(dynamic v) {
    if (v == null) return null;
    if (v is bool) return v;
    if (v is int) return v != 0;
    if (v is String) return v.toLowerCase() == 'true' || v == '1';
    return null;
  }

  void dispose() {
    _http.close();
  }
}

/// Exception thrown by [RainMakerApiClient] on HTTP errors.
class RainMakerApiException implements Exception {
  final String message;
  final int statusCode;
  RainMakerApiException(this.message, this.statusCode);

  @override
  String toString() => 'RainMakerApiException($statusCode): $message';
}

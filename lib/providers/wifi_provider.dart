import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/psu_state.dart';
import '../wifi/provisioning_service.dart';
import '../wifi/rainmaker_api.dart';

/// The active transport layer being used to communicate with the PSU.
enum ActiveTransport { none, ble, cloud }

/// ChangeNotifier that manages:
///  - RainMaker cloud authentication state
///  - List of provisioned / claimed nodes
///  - Cloud-based telemetry polling
///  - Active transport indicator
class WiFiProvider extends ChangeNotifier {
  final RainMakerApiClient _api;
  final ProvisioningService _provisioning;

  Timer? _cloudPollTimer;

  // ---- Auth state ----
  bool _loggedIn = false;
  bool get isLoggedIn => _loggedIn;

  String? _userEmail;
  String? get userEmail => _userEmail;

  bool _authLoading = false;
  bool get authLoading => _authLoading;

  String? _authError;
  String? get authError => _authError;

  // ---- Node state ----
  List<String> _nodeIds = [];
  List<String> get nodeIds => _nodeIds;

  String? _selectedNodeId;
  String? get selectedNodeId => _selectedNodeId;

  // ---- Cloud telemetry ----
  PsuState _cloudState = PsuState.empty;
  PsuState get cloudState => _cloudState;

  bool _cloudAvailable = false;
  bool get isCloudAvailable => _cloudAvailable;

  String? _cloudError;
  String? get cloudError => _cloudError;

  // ---- Transport ----
  ActiveTransport _activeTransport = ActiveTransport.none;
  ActiveTransport get activeTransport => _activeTransport;

  // ---- Provisioning ----
  ProvisioningStep get provisioningStep => _provisioning.currentStep;
  Stream<ProvisioningStep> get provisioningStepStream =>
      _provisioning.stepStream;

  WiFiProvider({
    RainMakerApiClient? api,
    ProvisioningService? provisioning,
  })  : _api = api ?? RainMakerApiClient(),
        _provisioning = provisioning ?? ProvisioningService();

  // ---------------------------------------------------------------------------
  // Initialization
  // ---------------------------------------------------------------------------

  /// Call on app startup to restore persisted auth tokens.
  Future<void> initialize() async {
    await _api.loadTokens();
    _loggedIn = _api.isLoggedIn;
    _userEmail = _api.userEmail;
    if (_loggedIn) {
      await _refreshNodeList();
    }
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // Auth actions
  // ---------------------------------------------------------------------------

  Future<String> createAccount(String email, String password) async {
    _authLoading = true;
    _authError = null;
    notifyListeners();

    try {
      final msg = await _api.createUser(email, password);
      return msg;
    } on RainMakerApiException catch (e) {
      _authError = e.message;
      rethrow;
    } finally {
      _authLoading = false;
      notifyListeners();
    }
  }

  Future<void> confirmAccount(String email, String code) async {
    _authLoading = true;
    _authError = null;
    notifyListeners();

    try {
      await _api.confirmUser(email, code);
    } on RainMakerApiException catch (e) {
      _authError = e.message;
      rethrow;
    } finally {
      _authLoading = false;
      notifyListeners();
    }
  }

  Future<void> login(String email, String password) async {
    _authLoading = true;
    _authError = null;
    notifyListeners();

    try {
      await _api.login(email, password);
      _loggedIn = true;
      _userEmail = email;
      await _refreshNodeList();
    } on RainMakerApiException catch (e) {
      _authError = e.message;
    } finally {
      _authLoading = false;
      notifyListeners();
    }
  }

  Future<void> logout() async {
    stopCloudPolling();
    await _api.logout();
    _loggedIn = false;
    _userEmail = null;
    _nodeIds = [];
    _selectedNodeId = null;
    _cloudState = PsuState.empty;
    _cloudAvailable = false;
    notifyListeners();
  }

  void clearAuthError() {
    _authError = null;
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // Node management
  // ---------------------------------------------------------------------------

  Future<void> _refreshNodeList() async {
    try {
      _nodeIds = await _api.getNodeIds();
      if (_nodeIds.isNotEmpty && _selectedNodeId == null) {
        _selectedNodeId = _nodeIds.first;
      }
      _cloudAvailable = _nodeIds.isNotEmpty;
    } catch (e) {
      _cloudError = 'Failed to load nodes: $e';
      _cloudAvailable = false;
    }
  }

  Future<void> refreshNodes() async {
    await _refreshNodeList();
    notifyListeners();
  }

  void selectNode(String nodeId) {
    _selectedNodeId = nodeId;
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // Transport selection
  // ---------------------------------------------------------------------------

  void setActiveTransport(ActiveTransport transport) {
    _activeTransport = transport;
    if (transport == ActiveTransport.cloud) {
      startCloudPolling();
    } else {
      stopCloudPolling();
    }
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // Cloud telemetry polling
  // ---------------------------------------------------------------------------

  void startCloudPolling() {
    _cloudPollTimer?.cancel();
    _cloudPollTimer = Timer.periodic(
      const Duration(seconds: 5),
      (_) => _pollCloudTelemetry(),
    );
    // Immediate first poll
    _pollCloudTelemetry();
  }

  void stopCloudPolling() {
    _cloudPollTimer?.cancel();
    _cloudPollTimer = null;
  }

  Future<void> _pollCloudTelemetry() async {
    if (!_loggedIn || _selectedNodeId == null) return;

    try {
      final params = await _api.getNodeParams(_selectedNodeId!);
      _cloudState = _api.parseNodeParamsToState(params);
      _cloudError = null;
      notifyListeners();
    } on RainMakerApiException catch (e) {
      _cloudError = 'Cloud poll error: ${e.message}';
      notifyListeners();
    } catch (e) {
      _cloudError = 'Cloud poll error: $e';
      notifyListeners();
    }
  }

  /// Write a config parameter to the cloud.
  Future<void> writeCloudParam(String paramName, dynamic value) async {
    if (!_loggedIn || _selectedNodeId == null) return;

    try {
      final payload = _api.buildParamPayload(paramName, value);
      await _api.setNodeParams(_selectedNodeId!, payload);
      _cloudError = null;
      // Re-poll to get the updated state
      await _pollCloudTelemetry();
    } on RainMakerApiException catch (e) {
      _cloudError = 'Cloud write error: ${e.message}';
      notifyListeners();
    } catch (e) {
      _cloudError = 'Cloud write error: $e';
      notifyListeners();
    }
  }

  // ---------------------------------------------------------------------------
  // Provisioning
  // ---------------------------------------------------------------------------

  ProvisioningService get provisioningService => _provisioning;

  // ---------------------------------------------------------------------------
  // Cleanup
  // ---------------------------------------------------------------------------

  @override
  void dispose() {
    _cloudPollTimer?.cancel();
    _provisioning.dispose();
    _api.dispose();
    super.dispose();
  }
}

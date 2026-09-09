import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:kohera/core/services/client_manager.dart';
import 'package:kohera/core/services/matrix_service.dart';
import 'package:kohera/core/utils/matrix_username.dart';
import 'package:kohera/core/utils/network_error.dart';
import 'package:kohera/core/utils/password_strength.dart';
import 'package:kohera/data/repositories/auth_repository.dart';
import 'package:kohera/features/auth/services/recaptcha_server.dart';
import 'package:kohera/features/e2ee/services/bootstrap_controller.dart' show BootstrapController;
import 'package:matrix/matrix.dart';

/// States for the registration flow state machine.
enum RegistrationState {
  checkingServer,
  registrationDisabled,
  formReady,
  enterEmail,
  awaitingEmailVerification,
  recaptcha,
  acceptTerms,
  registering,
  done,
  error,
}

/// Result of the live `/register/available` lookup for the typed username.
enum UsernameAvailability { unknown, checking, available, taken, invalid }

/// Business logic for the registration flow.
///
/// Follows the same ChangeNotifier state-machine pattern as
/// [BootstrapController]. The screen listens to [notifyListeners]
/// and reads the public getters.
class RegistrationController extends ChangeNotifier {
  RegistrationController({
    required this.matrixService,
    required this.authRepository,
    required this.clientManager,
    required String homeserver,
    Duration usernameCheckDebounce = const Duration(milliseconds: 600),
  })  : _homeserver = homeserver,
        _usernameCheckDebounce = usernameCheckDebounce;

  final MatrixService matrixService;
  final AuthRepository authRepository;
  final ClientManager clientManager;

  final Duration _usernameCheckDebounce;

  String _homeserver;
  String get homeserver => _homeserver;

  // ── State fields ──────────────────────────────────────────────

  RegistrationState _state = RegistrationState.checkingServer;
  RegistrationState get state => _state;

  String? _error;
  String? get error => _error;

  String? _usernameError;
  String? get usernameError => _usernameError;

  String? _passwordError;
  String? get passwordError => _passwordError;

  String? _tokenError;
  String? get tokenError => _tokenError;

  String? _emailError;
  String? get emailError => _emailError;

  String _username = '';
  String _password = '';
  String _token = '';

  List<String> _registrationStages = [];

  /// Whether the server requires a registration token.
  bool get requiresToken =>
      _registrationStages.contains('m.login.registration_token');

  /// Whether the server will ask for an email address during registration.
  bool get requiresEmail =>
      _registrationStages.contains(AuthenticationTypes.emailIdentity);

  // UIA tracking
  String? _session;
  List<List<String>> _flows = [];
  List<String> _completedStages = [];
  Map<String, dynamic> _uiaParams = {};

  // ── Live username availability ────────────────────────────────

  Timer? _usernameCheckDebounceTimer;
  int _usernameCheckGeneration = 0;

  UsernameAvailability _usernameAvailability = UsernameAvailability.unknown;
  UsernameAvailability get usernameAvailability => _usernameAvailability;

  String _candidateUsername = '';

  /// The full Matrix ID the typed username would claim, e.g. `@ada:matrix.org`.
  String? get matrixIdPreview {
    if (_candidateUsername.isEmpty) return null;
    return formatMatrixId(
      localpart: _candidateUsername,
      homeserver: _homeserver,
    );
  }

  /// Grades the password currently being typed, for the strength meter.
  PasswordAssessment _passwordAssessment = assessPassword('');
  PasswordAssessment get passwordAssessment => _passwordAssessment;

  // ── Email identity stage ──────────────────────────────────────

  String? _emailClientSecret;
  String? _emailSid;
  int _emailSendAttempt = 0;
  String _emailAddress = '';

  /// The address a verification link was sent to, once requested.
  String? get pendingEmailAddress =>
      _emailAddress.isEmpty ? null : _emailAddress;

  bool _emailSending = false;

  /// True while the verification email request is in flight.
  bool get emailSending => _emailSending;

  // ── Terms of Service stage ────────────────────────────────────

  final Set<String> _acceptedPolicyUrls = {};

  /// Whether the policy at [url] has been ticked by the user.
  bool isPolicyAccepted(String url) => _acceptedPolicyUrls.contains(url);

  /// Whether every advertised policy has been ticked.
  bool get allPoliciesAccepted {
    final policies = termsOfServicePolicies;
    if (policies.isEmpty) return true;
    return policies.every((p) => _acceptedPolicyUrls.contains(p.url));
  }

  /// Ticks or unticks the policy at [url].
  void togglePolicyAccepted(String url) {
    if (!_acceptedPolicyUrls.remove(url)) _acceptedPolicyUrls.add(url);
    _notify();
  }

  // ── reCAPTCHA ───────────────────────────────────────────────
  RecaptchaServer? _recaptchaServer;
  bool _recaptchaWaiting = false;

  /// True while the system browser is open waiting for the user.
  bool get recaptchaWaiting => _recaptchaWaiting;

  /// Public key for the reCAPTCHA widget, from UIA params.
  String? get recaptchaPublicKey {
    final p = _uiaParams['m.login.recaptcha'];
    return p is Map ? p['public_key'] as String? : null;
  }

  /// Policy list from UIA params for the Terms of Service stage.
  List<({String name, String url})> get termsOfServicePolicies {
    final termsParams = _uiaParams['m.login.terms'];
    if (termsParams is! Map) return const [];
    final policies = termsParams['policies'];
    if (policies is! Map) return const [];

    final result = <({String name, String url})>[];
    for (final entry in policies.entries) {
      final policy = entry.value;
      if (policy is! Map) continue;
      // Each policy has locale keys (e.g. 'en') mapping to {name, url},
      // plus a 'version' key (String). Find the first locale entry.
      for (final localeEntry in policy.entries) {
        if (localeEntry.value is! Map) continue;
        final localised = localeEntry.value as Map;
        final name = localised['name'] as String?;
        final url = localised['url'] as String?;
        if (name != null && url != null) {
          result.add((name: name, url: url));
          break;
        }
      }
    }
    return result;
  }

  /// Stages of the chosen flow, in order, for the progress indicator.
  List<String> get plannedStages => _findBestFlow();

  /// Stages the server has already accepted.
  List<String> get completedStages => List.unmodifiable(_completedStages);

  bool _isDisposed = false;

  /// Whether the server has been checked and supports registration.
  bool get serverReady => _state == RegistrationState.formReady;

  // ── Server check ──────────────────────────────────────────────

  int _checkGeneration = 0;

  Future<void> updateHomeserver(String newHomeserver) async {
    _homeserver = newHomeserver;
    _usernameError = null;
    _passwordError = null;
    _tokenError = null;
    _emailError = null;
    _error = null;
    _resetUsernameAvailability();
    await checkServer();
  }

  Future<void> checkServer() async {
    _state = RegistrationState.checkingServer;
    _notify();

    final generation = ++_checkGeneration;

    try {
      final caps =
          await authRepository.getServerAuthCapabilities(_homeserver);
      if (_isDisposed || generation != _checkGeneration) return;

      if (!caps.supportsRegistration) {
        _state = RegistrationState.registrationDisabled;
        _registrationStages = const [];
      } else {
        _registrationStages = caps.registrationStages;
        _state = RegistrationState.formReady;
      }
      _notify();
      if (_state == RegistrationState.formReady &&
          _candidateUsername.isNotEmpty) {
        await _runUsernameCheck(_candidateUsername);
      }
    } catch (e) {
      if (_isDisposed || generation != _checkGeneration) return;
      _state = RegistrationState.error;
      _error = e.toString();
      _notify();
    }
  }

  // ── Live field feedback ─────────────────────────────────────────

  /// Records the username being typed and schedules an availability lookup.
  void onUsernameChanged(String username) {
    final trimmed = username.trim();
    if (trimmed == _candidateUsername) return;

    _candidateUsername = trimmed;
    _usernameError = null;
    _usernameCheckDebounceTimer?.cancel();
    _usernameCheckGeneration++;

    if (trimmed.isEmpty) {
      _usernameAvailability = UsernameAvailability.unknown;
      _notify();
      return;
    }

    final validationError = validateLocalpart(trimmed);
    if (validationError != null) {
      _usernameAvailability = UsernameAvailability.invalid;
      _usernameError = validationError;
      _notify();
      return;
    }

    _usernameAvailability = UsernameAvailability.checking;
    _notify();

    _usernameCheckDebounceTimer = Timer(
      _usernameCheckDebounce,
      () => unawaited(_runUsernameCheck(trimmed)),
    );
  }

  Future<void> _runUsernameCheck(String username) async {
    if (_isDisposed) return;
    if (!serverReady && _state != RegistrationState.checkingServer) return;

    final generation = ++_usernameCheckGeneration;
    _usernameAvailability = UsernameAvailability.checking;
    _notify();

    try {
      final available =
          await authRepository.checkUsernameAvailability(username);
      if (_isDisposed || generation != _usernameCheckGeneration) return;
      _usernameAvailability = (available ?? false)
          ? UsernameAvailability.available
          : UsernameAvailability.taken;
      _usernameError = _usernameAvailability == UsernameAvailability.taken
          ? 'This username is already taken'
          : null;
    } on MatrixException catch (e) {
      if (_isDisposed || generation != _usernameCheckGeneration) return;
      if (_usernameErrcodes.contains(e.errcode)) {
        _usernameAvailability = UsernameAvailability.taken;
        _usernameError = _humanReadableError(e);
      } else {
        // The endpoint is optional and rate limited; stay quiet and let
        // the register call be the authority.
        _usernameAvailability = UsernameAvailability.unknown;
      }
    } catch (_) {
      if (_isDisposed || generation != _usernameCheckGeneration) return;
      _usernameAvailability = UsernameAvailability.unknown;
    }
    _notify();
  }

  /// Records the password being typed and refreshes [passwordAssessment].
  void onPasswordChanged(String password) {
    final assessment = assessPassword(password);
    if (assessment.strength == _passwordAssessment.strength &&
        assessment.suggestions.length == _passwordAssessment.suggestions.length &&
        _passwordError == null) {
      _passwordAssessment = assessment;
      return;
    }
    _passwordAssessment = assessment;
    _passwordError = null;
    _notify();
  }

  void _resetUsernameAvailability() {
    _usernameCheckDebounceTimer?.cancel();
    _usernameCheckGeneration++;
    _usernameAvailability = UsernameAvailability.unknown;
  }

  // ── Form submission ─────────────────────────────────────────────

  Future<void> submitForm({
    required String username,
    required String password,
    String token = '',
  }) async {
    if (_state != RegistrationState.formReady) return;

    _usernameError = null;
    _passwordError = null;
    _tokenError = null;
    _emailError = null;
    _error = null;

    final trimmedUsername = username.trim();
    final usernameProblem = validateLocalpart(trimmedUsername);
    if (usernameProblem != null) {
      _usernameError = usernameProblem;
      _usernameAvailability = UsernameAvailability.invalid;
      _notify();
      return;
    }
    if (password.isEmpty) {
      _passwordError = 'Please enter a password';
      _notify();
      return;
    }
    if (password.length < kMinimumPasswordLength) {
      _passwordError =
          'Password must be at least $kMinimumPasswordLength characters';
      _notify();
      return;
    }
    _passwordAssessment = assessPassword(password);
    if (_passwordAssessment.suggestions.contains('Avoid common passwords')) {
      _passwordError = 'This password is too common — pick another';
      _notify();
      return;
    }
    if (requiresToken && token.trim().isEmpty) {
      _tokenError = 'Please enter a registration token';
      _notify();
      return;
    }

    _username = trimmedUsername;
    _password = password;
    _token = token.trim();

    _state = RegistrationState.registering;
    _notify();

    // Ensure the client homeserver is set before making API calls.
    var hs = _homeserver.trim();
    if (!hs.startsWith('http')) hs = 'https://$hs';
    try {
      await authRepository.checkHomeserver(Uri.parse(hs));
    } catch (e) {
      _state = RegistrationState.error;
      _error = e.toString();
      _notify();
      return;
    }

    if (_isDisposed) return;
    await _attemptRegister();
  }

  Future<void> _attemptRegister({AuthenticationData? auth}) async {
    _state = RegistrationState.registering;
    _notify();

    try {
      final response = await authRepository.register(
        username: _username,
        password: _password,
        initialDeviceDisplayName: 'Kohera Flutter',
        auth: auth,
      );

      if (_isDisposed) return;

      await authRepository.completeRegistration(response, password: _password);
      if (!clientManager.services.contains(matrixService)) {
        await clientManager.commitPendingService();
      }
      _clearCredentials();
      _state = RegistrationState.done;
      _notify();
    } on MatrixException catch (e) {
      if (_isDisposed) return;

      // UIA challenge — parse flows and advance to next stage.
      if (e.raw.containsKey('flows')) {
        _session = e.raw['session'] as String?;
        _completedStages =
            List<String>.from(e.raw['completed'] as List? ?? []);
        _flows = (e.raw['flows'] as List?)
                ?.map((f) =>
                    List<String>.from((f as Map)['stages'] as List? ?? []),)
                .toList() ??
            [];
        _uiaParams = Map<String, dynamic>.from(
          e.raw['params'] as Map? ?? {},
        );
        await _advanceToNextStage();
        return;
      }

      // Route field-specific errors to their own inputs so they display
      // inline rather than as a generic error.
      if (_isUsernameError(e.errcode)) {
        _usernameError = _humanReadableError(e);
        _usernameAvailability = UsernameAvailability.taken;
        _state = RegistrationState.formReady;
      } else if (_isEmailError(e.errcode)) {
        _emailError = _humanReadableError(e);
        _emailSid = null;
        _state = RegistrationState.enterEmail;
      } else if (_isTokenError(e.errcode)) {
        _tokenError = _humanReadableError(e);
        _state = RegistrationState.formReady;
      } else {
        _state = RegistrationState.error;
        _error = _humanReadableError(e);
      }
      _notify();
    } catch (e) {
      if (_isDisposed) return;
      _state = RegistrationState.error;
      _error = _friendlyError(e);
      _notify();
    }
  }

  Future<void> _advanceToNextStage() async {
    final bestFlow = _findBestFlow();
    final nextStage = bestFlow.firstWhere(
      (s) => !_completedStages.contains(s),
      orElse: () => '',
    );

    switch (nextStage) {
      case AuthenticationTypes.dummy:
        // Auto-complete dummy stage.
        await _attemptRegister(
          auth: AuthenticationData(
            type: AuthenticationTypes.dummy,
            session: _session,
          ),
        );
        return;
      case 'm.login.registration_token':
        // Auto-complete with the token collected from the form.
        await _attemptRegister(
          auth: _RegistrationTokenAuth(
            session: _session,
            token: _token,
          ),
        );
        return;
      case AuthenticationTypes.emailIdentity:
        if (_emailSid != null) {
          // The link has not been followed yet — the server still rejects
          // the threepid, so keep waiting rather than asking again.
          _state = RegistrationState.awaitingEmailVerification;
          _emailError =
              'We could not confirm that address yet. Open the link in the '
              'email, then try again.';
        } else {
          _state = RegistrationState.enterEmail;
        }
      case AuthenticationTypes.recaptcha:
        _state = RegistrationState.recaptcha;
      case 'm.login.terms':
        _state = RegistrationState.acceptTerms;
      case '':
        // All stages completed but no success response — shouldn't happen.
        _state = RegistrationState.error;
        _error = 'Registration failed unexpectedly';
      default:
        _state = RegistrationState.error;
        _error = 'Unsupported registration step: $nextStage';
    }
    _notify();
  }

  static const Set<String> _supportedStages = {
    AuthenticationTypes.dummy,
    AuthenticationTypes.emailIdentity,
    AuthenticationTypes.recaptcha,
    'm.login.terms',
    'm.login.registration_token',
  };

  List<String> _findBestFlow() {
    if (_flows.isEmpty) return [];
    // Prefer flows where all remaining stages are supported, then fewest remaining.
    return _flows.reduce((a, b) {
      final aRemaining = a.where((s) => !_completedStages.contains(s));
      final bRemaining = b.where((s) => !_completedStages.contains(s));
      final aSupported = aRemaining.every((s) => _supportedStages.contains(s));
      final bSupported = bRemaining.every((s) => _supportedStages.contains(s));
      if (aSupported != bSupported) return aSupported ? a : b;
      return aRemaining.length <= bRemaining.length ? a : b;
    });
  }

  // ── Email identity submission ─────────────────────────────────

  static final RegExp _emailPattern =
      RegExp(r'^[^@\s]+@[^@\s.]+(\.[^@\s.]+)+$');

  /// Requests a verification email for [email] and waits for the user to
  /// follow the link it contains.
  Future<void> submitEmail(String email) async {
    if (_state != RegistrationState.enterEmail) return;

    final trimmed = email.trim();
    _emailError = null;

    if (trimmed.isEmpty) {
      _emailError = 'Please enter an email address';
      _notify();
      return;
    }
    if (!_emailPattern.hasMatch(trimmed)) {
      _emailError = 'Please enter a valid email address';
      _notify();
      return;
    }

    _emailAddress = trimmed;
    _emailClientSecret = _generateClientSecret();
    _emailSid = null;
    _emailSendAttempt = 0;

    await _requestEmailToken();
  }

  /// Asks the homeserver to send the verification email again.
  Future<void> resendVerificationEmail() async {
    if (_state != RegistrationState.awaitingEmailVerification) return;
    if (_emailAddress.isEmpty || _emailClientSecret == null) return;
    await _requestEmailToken();
  }

  Future<void> _requestEmailToken() async {
    final clientSecret = _emailClientSecret;
    if (clientSecret == null) return;

    _emailSending = true;
    _emailError = null;
    _notify();

    try {
      final response = await authRepository.requestTokenToRegisterEmail(
        clientSecret: clientSecret,
        email: _emailAddress,
        sendAttempt: ++_emailSendAttempt,
      );
      if (_isDisposed) return;
      _emailSid = response.sid;
      _emailSending = false;
      _state = RegistrationState.awaitingEmailVerification;
      debugPrint('[Kohera] Verification email requested for registration');
      _notify();
    } on MatrixException catch (e) {
      if (_isDisposed) return;
      _emailSending = false;
      _emailError = _humanReadableError(e);
      _state = RegistrationState.enterEmail;
      _notify();
    } catch (e) {
      if (_isDisposed) return;
      _emailSending = false;
      _emailError = _friendlyError(e);
      _state = RegistrationState.enterEmail;
      _notify();
    }
  }

  /// Tells the homeserver the email link has been followed, completing the
  /// `m.login.email_identity` stage.
  Future<void> confirmEmailVerified() async {
    if (_state != RegistrationState.awaitingEmailVerification) return;

    final sid = _emailSid;
    final clientSecret = _emailClientSecret;
    if (sid == null || clientSecret == null) {
      _state = RegistrationState.enterEmail;
      _emailError = 'Please request a verification email first';
      _notify();
      return;
    }

    _emailError = null;
    await _attemptRegister(
      auth: _EmailIdentityAuth(
        session: _session,
        sid: sid,
        clientSecret: clientSecret,
      ),
    );
  }

  /// Discards the pending address so a different one can be entered.
  void changeEmailAddress() {
    if (_state != RegistrationState.awaitingEmailVerification) return;
    _emailSid = null;
    _emailClientSecret = null;
    _emailSendAttempt = 0;
    _emailAddress = '';
    _emailError = null;
    _state = RegistrationState.enterEmail;
    _notify();
  }

  static const String _clientSecretAlphabet =
      'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';

  static String _generateClientSecret() {
    final random = Random.secure();
    return String.fromCharCodes(
      List.generate(
        32,
        (_) => _clientSecretAlphabet
            .codeUnitAt(random.nextInt(_clientSecretAlphabet.length)),
      ),
    );
  }

  // ── reCAPTCHA submission ──────────────────────────────────────

  Future<void> submitRecaptcha() async {
    if (_state != RegistrationState.recaptcha) return;

    final publicKey = recaptchaPublicKey;
    if (publicKey == null || publicKey.isEmpty) {
      _state = RegistrationState.error;
      _error = 'Server did not provide a reCAPTCHA site key';
      _notify();
      return;
    }

    _recaptchaServer?.dispose();

    final server = RecaptchaServer(siteKey: publicKey);
    _recaptchaServer = server;

    try {
      final url = await server.start();
      debugPrint('[Kohera] Opening reCAPTCHA page: $url');

      await server.launch(Uri.parse(url));

      _recaptchaWaiting = true;
      _notify();

      final token = await server.tokenFuture;
      _recaptchaWaiting = false;
      _recaptchaServer = null;

      if (_isDisposed) return;

      await _attemptRegister(
        auth: _RecaptchaAuth(session: _session, response: token),
      );
    } on RecaptchaException catch (e) {
      if (_isDisposed) return;
      _recaptchaWaiting = false;
      _recaptchaServer = null;
      _state = RegistrationState.error;
      _error = e.message;
      _notify();
    } catch (e) {
      if (_isDisposed) return;
      _recaptchaWaiting = false;
      _recaptchaServer = null;
      _state = RegistrationState.error;
      _error = _friendlyError(e);
      _notify();
    }
  }

  // ── Terms submission ────────────────────────────────────────

  Future<void> submitTerms() async {
    if (_state != RegistrationState.acceptTerms) return;
    if (!allPoliciesAccepted) return;

    await _attemptRegister(
      auth: AuthenticationData(
        type: 'm.login.terms',
        session: _session,
      ),
    );
  }

  // ── Error mapping ──────────────────────────────────────────────

  static const _usernameErrcodes = {
    'M_USER_IN_USE',
    'M_INVALID_USERNAME',
    'M_EXCLUSIVE',
  };

  static const _emailErrcodes = {
    'M_THREEPID_IN_USE',
    'M_THREEPID_DENIED',
    'M_THREEPID_NOT_FOUND',
    'M_THREEPID_AUTH_FAILED',
  };

  bool _isUsernameError(String? errcode) =>
      _usernameErrcodes.contains(errcode);

  bool _isEmailError(String? errcode) => _emailErrcodes.contains(errcode);

  bool _isTokenError(String? errcode) =>
      errcode == 'M_UNAUTHORIZED' && requiresToken;

  String _humanReadableError(MatrixException e) {
    switch (e.errcode) {
      case 'M_USER_IN_USE':
        return 'This username is already taken';
      case 'M_INVALID_USERNAME':
        return 'Username contains invalid characters';
      case 'M_EXCLUSIVE':
        return 'This username is reserved';
      case 'M_FORBIDDEN':
        return 'Registration is not allowed on this server';
      case 'M_THREEPID_IN_USE':
        return 'This email is already registered';
      case 'M_THREEPID_DENIED':
        return 'This email domain is not allowed';
      case 'M_THREEPID_NOT_FOUND':
        return 'That email address could not be verified';
      case 'M_THREEPID_AUTH_FAILED':
        return 'Open the link in the email, then try again';
      case 'M_UNAUTHORIZED':
        return requiresToken
            ? 'This registration token was not accepted'
            : e.errorMessage;
      case 'M_LIMIT_EXCEEDED':
        final retryMs = e.retryAfterMs;
        return retryMs == null
            ? 'Too many attempts — please wait and try again'
            : 'Too many attempts — please wait '
                '${(retryMs / 1000).ceil()}s and try again';
      case 'M_WEAK_PASSWORD':
        return 'This server rejected the password as too weak';
      default:
        return e.errorMessage;
    }
  }

  /// Converts common non-Matrix exceptions to user-friendly messages.
  static String _friendlyError(Object e) {
    if (isNetworkError(e)) return 'Could not reach server';
    if (e is TimeoutException) return 'Connection timed out';
    if (e is FormatException) return 'Invalid server response';
    return e.toString();
  }

  // ── Cancel ──────────────────────────────────────────────────────

  /// Resets the controller from a UIA dead-end back to [RegistrationState.formReady].
  void cancelRegistration() {
    _recaptchaServer?.dispose();
    _recaptchaServer = null;
    _recaptchaWaiting = false;
    _session = null;
    _flows = [];
    _completedStages = [];
    _uiaParams = {};
    _acceptedPolicyUrls.clear();
    _emailSid = null;
    _emailClientSecret = null;
    _emailSendAttempt = 0;
    _emailAddress = '';
    _emailError = null;
    _emailSending = false;
    _error = null;
    _state = RegistrationState.formReady;
    _notify();
  }

  // ── Internals ──────────────────────────────────────────────────

  void _clearCredentials() {
    _username = '';
    _password = '';
    _token = '';
    _emailClientSecret = null;
  }

  void _notify() {
    if (!_isDisposed) {
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _isDisposed = true;
    _usernameCheckDebounceTimer?.cancel();
    _usernameCheckDebounceTimer = null;
    _recaptchaServer?.dispose();
    _recaptchaServer = null;
    _clearCredentials();
    super.dispose();
  }
}

/// [AuthenticationData] subclass for the `m.login.recaptcha` UIA stage.
class _RecaptchaAuth extends AuthenticationData {
  final String _response;

  _RecaptchaAuth({required String response, super.session})
      : _response = response,
        super(type: AuthenticationTypes.recaptcha);

  @override
  Map<String, Object?> toJson() {
    final data = super.toJson();
    data['response'] = _response;
    return data;
  }
}

/// [AuthenticationData] subclass for the `m.login.registration_token` UIA stage.
class _RegistrationTokenAuth extends AuthenticationData {
  final String _token;

  _RegistrationTokenAuth({required String token, super.session})
      : _token = token,
        super(type: 'm.login.registration_token');

  @override
  Map<String, Object?> toJson() {
    final data = super.toJson();
    data['token'] = _token;
    return data;
  }
}

/// [AuthenticationData] subclass for the `m.login.email_identity` UIA stage.
class _EmailIdentityAuth extends AuthenticationData {
  final String _sid;
  final String _clientSecret;

  _EmailIdentityAuth({
    required String sid,
    required String clientSecret,
    super.session,
  })  : _sid = sid,
        _clientSecret = clientSecret,
        super(type: AuthenticationTypes.emailIdentity);

  @override
  Map<String, Object?> toJson() {
    final data = super.toJson();
    data['threepid_creds'] = {
      'sid': _sid,
      'client_secret': _clientSecret,
    };
    return data;
  }
}

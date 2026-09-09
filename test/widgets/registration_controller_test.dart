import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kohera/core/models/server_auth_capabilities.dart';
import 'package:kohera/core/services/auth_service.dart';
import 'package:kohera/core/services/client_manager.dart';
import 'package:kohera/core/services/matrix_service.dart';
import 'package:kohera/data/repositories/auth_repository.dart';
import 'package:kohera/data/services/matrix_client_service.dart';
import 'package:kohera/features/auth/services/registration_controller.dart';
import 'package:matrix/matrix.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';

@GenerateNiceMocks([
  MockSpec<Client>(),
  MockSpec<AuthService>(),
])
import '../mocks/matrix_service_mock.mocks.dart';
import 'registration_controller_test.mocks.dart';

/// Minimal [ClientManager] double. Hand-written rather than a generated mock
/// so the controller test compiles without regenerating mocks.
class _FakeClientManager extends ClientManager {
  _FakeClientManager(this._registered);

  final List<MatrixService> _registered;
  bool committed = false;

  @override
  List<MatrixService> get services => _registered;

  @override
  Future<void> commitPendingService() async => committed = true;
}

void main() {
  late MockClient mockClient;
  late MockMatrixService mockMatrixService;
  late MockAuthService mockAuthService;
  late _FakeClientManager fakeClientManager;
  late AuthRepository authRepository;

  setUp(() {
    mockClient = MockClient();
    mockMatrixService = MockMatrixService();
    mockAuthService = MockAuthService();
    fakeClientManager = _FakeClientManager([mockMatrixService]);
    when(mockMatrixService.matrixClientService).thenReturn(MatrixClientService(mockClient));
    when(mockMatrixService.auth).thenReturn(mockAuthService);
    when(mockMatrixService.isLoggedIn).thenReturn(false);
    authRepository = AuthRepository(clientService: mockMatrixService.matrixClientService, auth: mockMatrixService.auth, setupState: mockMatrixService.keyBackupSetupState);
  });

  RegistrationController createController({
    String homeserver = 'example.com',
    Duration usernameCheckDebounce = Duration.zero,
  }) {
    return RegistrationController(
      matrixService: mockMatrixService,
      authRepository: authRepository,
      clientManager: fakeClientManager,
      homeserver: homeserver,
      usernameCheckDebounce: usernameCheckDebounce,
    );
  }

  group('RegistrationController', () {
    group('checkServer', () {
      test('starts in checkingServer state', () {
        final controller = createController();
        expect(controller.state, RegistrationState.checkingServer);
        controller.dispose();
      });

      test('transitions to formReady when registration is supported',
          () async {
        when(mockAuthService.getServerAuthCapabilities(any, isLoggedIn: anyNamed('isLoggedIn')))
            .thenAnswer((_) async => const ServerAuthCapabilities(
                  supportsRegistration: true,
                  registrationStages: ['m.login.dummy'],
                ),);

        final controller = createController();
        await controller.checkServer();

        expect(controller.state, RegistrationState.formReady);
        expect(controller.serverReady, isTrue);
        controller.dispose();
      });

      test('transitions to registrationDisabled when server does not support it',
          () async {
        when(mockAuthService.getServerAuthCapabilities(any, isLoggedIn: anyNamed('isLoggedIn')))
            .thenAnswer((_) async => const ServerAuthCapabilities(
                  
                ),);

        final controller = createController();
        await controller.checkServer();

        expect(controller.state, RegistrationState.registrationDisabled);
        expect(controller.serverReady, isFalse);
        controller.dispose();
      });

      test('transitions to error on network failure', () async {
        when(mockAuthService.getServerAuthCapabilities(any, isLoggedIn: anyNamed('isLoggedIn')))
            .thenThrow(Exception('Connection refused'));

        final controller = createController();
        await controller.checkServer();

        expect(controller.state, RegistrationState.error);
        expect(controller.error, contains('Connection refused'));
        controller.dispose();
      });

      test('notifies listeners on state change', () async {
        when(mockAuthService.getServerAuthCapabilities(any, isLoggedIn: anyNamed('isLoggedIn')))
            .thenAnswer((_) async => const ServerAuthCapabilities(
                  supportsRegistration: true,
                ),);

        final controller = createController();
        var notifyCount = 0;
        controller.addListener(() => notifyCount++);

        await controller.checkServer();

        expect(notifyCount, greaterThan(0));
        controller.dispose();
      });
    });

    group('updateHomeserver', () {
      test('re-checks server capabilities with new homeserver', () async {
        when(mockAuthService.getServerAuthCapabilities('example.com', isLoggedIn: anyNamed('isLoggedIn')))
            .thenAnswer((_) async => const ServerAuthCapabilities(
                  supportsRegistration: true,
                ),);
        when(mockAuthService.getServerAuthCapabilities('other.com', isLoggedIn: anyNamed('isLoggedIn')))
            .thenAnswer((_) async => const ServerAuthCapabilities(
                  
                ),);

        final controller = createController();
        await controller.checkServer();
        expect(controller.serverReady, isTrue);

        await controller.updateHomeserver('other.com');
        expect(controller.homeserver, 'other.com');
        expect(controller.state, RegistrationState.registrationDisabled);
        controller.dispose();
      });

      test('clears errors when homeserver changes', () async {
        when(mockAuthService.getServerAuthCapabilities(any, isLoggedIn: anyNamed('isLoggedIn')))
            .thenAnswer((_) async => const ServerAuthCapabilities(
                  supportsRegistration: true,
                ),);

        final controller = createController();
        await controller.checkServer();

        // Trigger a username error
        await controller.submitForm(username: '', password: 'Sunflower42!');
        expect(controller.usernameError, isNotNull);

        await controller.updateHomeserver('new.com');
        expect(controller.usernameError, isNull);
        expect(controller.passwordError, isNull);
        expect(controller.error, isNull);
        controller.dispose();
      });
    });

    group('submitForm', () {
      setUp(() {
        when(mockAuthService.getServerAuthCapabilities(any, isLoggedIn: anyNamed('isLoggedIn')))
            .thenAnswer((_) async => const ServerAuthCapabilities(
                  supportsRegistration: true,
                  registrationStages: ['m.login.dummy'],
                ),);
      });

      test('rejects empty username', () async {
        final controller = createController();
        await controller.checkServer();
        await controller.submitForm(username: '', password: 'Sunflower42!');

        expect(controller.state, RegistrationState.formReady);
        expect(controller.usernameError, isNotNull);
        controller.dispose();
      });

      test('rejects empty password', () async {
        final controller = createController();
        await controller.checkServer();
        await controller.submitForm(username: 'user', password: '');

        expect(controller.state, RegistrationState.formReady);
        expect(controller.passwordError, isNotNull);
        controller.dispose();
      });

      test('rejects password shorter than 8 characters', () async {
        final controller = createController();
        await controller.checkServer();
        await controller.submitForm(username: 'user', password: 'short');

        expect(controller.state, RegistrationState.formReady);
        expect(controller.passwordError, contains('8 characters'));
        controller.dispose();
      });

      test('sets usernameError when username is taken', () async {
        when(mockClient.register(
          username: anyNamed('username'),
          password: anyNamed('password'),
          initialDeviceDisplayName: anyNamed('initialDeviceDisplayName'),
          auth: anyNamed('auth'),
        ),).thenThrow(
          MatrixException.fromJson({
            'errcode': 'M_USER_IN_USE',
            'error': 'Desired user ID is already taken.',
          }),
        );

        final controller = createController();
        await controller.checkServer();
        await controller.submitForm(
            username: 'takenuser', password: 'Sunflower42!',);

        expect(controller.state, RegistrationState.formReady);
        expect(controller.usernameError, contains('already taken'));
        controller.dispose();
      });

      test('sets usernameError when username is invalid', () async {
        when(mockClient.register(
          username: anyNamed('username'),
          password: anyNamed('password'),
          initialDeviceDisplayName: anyNamed('initialDeviceDisplayName'),
          auth: anyNamed('auth'),
        ),).thenThrow(
          MatrixException.fromJson({
            'errcode': 'M_INVALID_USERNAME',
            'error': 'User ID contains invalid characters.',
          }),
        );

        final controller = createController();
        await controller.checkServer();
        await controller.submitForm(
            username: 'servername', password: 'Sunflower42!',);

        expect(controller.state, RegistrationState.formReady);
        expect(controller.usernameError, contains('invalid'));
        controller.dispose();
      });

      test('rejects a malformed localpart without calling the server',
          () async {
        final controller = createController();
        await controller.checkServer();
        await controller.submitForm(
            username: 'bad@user', password: 'Sunflower42!',);

        expect(controller.state, RegistrationState.formReady);
        expect(controller.usernameError, isNotNull);
        expect(controller.usernameAvailability, UsernameAvailability.invalid);
        verifyNever(mockClient.register(
          username: anyNamed('username'),
          password: anyNamed('password'),
          initialDeviceDisplayName: anyNamed('initialDeviceDisplayName'),
          auth: anyNamed('auth'),
        ),);
        controller.dispose();
      });

      test('rejects a common password without calling the server', () async {
        final controller = createController();
        await controller.checkServer();
        await controller.submitForm(
            username: 'ada', password: 'password123',);

        expect(controller.state, RegistrationState.formReady);
        expect(controller.passwordError, contains('too common'));
        verifyNever(mockClient.register(
          username: anyNamed('username'),
          password: anyNamed('password'),
          initialDeviceDisplayName: anyNamed('initialDeviceDisplayName'),
          auth: anyNamed('auth'),
        ),);
        controller.dispose();
      });

      test('transitions to done on successful registration with dummy stage',
          () async {
        // First register call returns 401 with dummy flow
        when(mockClient.register(
          username: anyNamed('username'),
          password: anyNamed('password'),
          initialDeviceDisplayName: anyNamed('initialDeviceDisplayName'),
          auth: anyNamed('auth'),
        ),).thenThrow(
          MatrixException.fromJson({
            'flows': [
              {
                'stages': ['m.login.dummy'],
              },
            ],
            'session': 'sess1',
          }),
        );

        final controller = createController();
        await controller.checkServer();

        // Now mock the second register call (with dummy auth) to succeed
        when(mockClient.register(
          username: anyNamed('username'),
          password: anyNamed('password'),
          initialDeviceDisplayName: anyNamed('initialDeviceDisplayName'),
          auth: anyNamed('auth'),
        ),).thenAnswer((_) async => RegisterResponse(
              userId: '@newuser:example.com',
              accessToken: 'token',
              deviceId: 'DEV1',
            ),);
        when(mockAuthService.completeRegistration(any))
            .thenAnswer((_) async {});

        await controller.submitForm(
            username: 'newuser', password: 'goodpass1',);

        expect(controller.state, RegistrationState.done);
        controller.dispose();
      });

      test('sets error on M_FORBIDDEN', () async {
        when(mockClient.register(
          username: anyNamed('username'),
          password: anyNamed('password'),
          initialDeviceDisplayName: anyNamed('initialDeviceDisplayName'),
          auth: anyNamed('auth'),
        ),).thenThrow(
          MatrixException.fromJson({
            'errcode': 'M_FORBIDDEN',
            'error': 'Registration is not allowed on this server',
          }),
        );

        final controller = createController();
        await controller.checkServer();
        await controller.submitForm(
            username: 'user', password: 'Sunflower42!',);

        expect(controller.state, RegistrationState.error);
        expect(controller.error, contains('not allowed'));
        controller.dispose();
      });

      test('transitions to enterEmail when email stage is required', () async {
        when(mockClient.register(
          username: anyNamed('username'),
          password: anyNamed('password'),
          initialDeviceDisplayName: anyNamed('initialDeviceDisplayName'),
          auth: anyNamed('auth'),
        ),).thenThrow(
          MatrixException.fromJson({
            'flows': [
              {
                'stages': ['m.login.email.identity'],
              },
            ],
            'session': 'sess2',
          }),
        );

        final controller = createController();
        await controller.checkServer();
        await controller.submitForm(
            username: 'user', password: 'Sunflower42!',);

        expect(controller.state, RegistrationState.enterEmail);
        controller.dispose();
      });

      test('transitions to recaptcha when recaptcha stage is required',
          () async {
        when(mockClient.register(
          username: anyNamed('username'),
          password: anyNamed('password'),
          initialDeviceDisplayName: anyNamed('initialDeviceDisplayName'),
          auth: anyNamed('auth'),
        ),).thenThrow(
          MatrixException.fromJson({
            'flows': [
              {
                'stages': ['m.login.recaptcha'],
              },
            ],
            'session': 'sess3',
          }),
        );

        final controller = createController();
        await controller.checkServer();
        await controller.submitForm(
            username: 'user', password: 'Sunflower42!',);

        expect(controller.state, RegistrationState.recaptcha);
        controller.dispose();
      });

      test('transitions to acceptTerms when terms stage is required', () async {
        when(mockClient.register(
          username: anyNamed('username'),
          password: anyNamed('password'),
          initialDeviceDisplayName: anyNamed('initialDeviceDisplayName'),
          auth: anyNamed('auth'),
        ),).thenThrow(
          MatrixException.fromJson({
            'flows': [
              {
                'stages': ['m.login.terms'],
              },
            ],
            'session': 'sess4',
          }),
        );

        final controller = createController();
        await controller.checkServer();
        await controller.submitForm(
            username: 'user', password: 'Sunflower42!',);

        expect(controller.state, RegistrationState.acceptTerms);
        controller.dispose();
      });

      test('sets error for unsupported UIA stage', () async {
        when(mockClient.register(
          username: anyNamed('username'),
          password: anyNamed('password'),
          initialDeviceDisplayName: anyNamed('initialDeviceDisplayName'),
          auth: anyNamed('auth'),
        ),).thenThrow(
          MatrixException.fromJson({
            'flows': [
              {
                'stages': ['m.login.unknown_stage'],
              },
            ],
            'session': 'sess5',
          }),
        );

        final controller = createController();
        await controller.checkServer();
        await controller.submitForm(
            username: 'user', password: 'Sunflower42!',);

        expect(controller.state, RegistrationState.error);
        expect(controller.error, contains('Unsupported'));
        controller.dispose();
      });

      test('calls completeRegistration on success', () async {
        when(mockClient.register(
          username: anyNamed('username'),
          password: anyNamed('password'),
          initialDeviceDisplayName: anyNamed('initialDeviceDisplayName'),
          auth: anyNamed('auth'),
        ),).thenAnswer((_) async => RegisterResponse(
              userId: '@user:example.com',
              accessToken: 'tok',
              deviceId: 'D1',
            ),);
        when(mockAuthService.completeRegistration(any))
            .thenAnswer((_) async {});

        final controller = createController();
        await controller.checkServer();
        await controller.submitForm(
            username: 'user', password: 'Sunflower42!',);

        verify(mockAuthService.completeRegistration(
          any,
          password: anyNamed('password'),
        ),).called(1);
        controller.dispose();
      });

      test('commits pending service when registering an additional account',
          () async {
        // The registering service is not yet in the account list (pending),
        // mirroring the add-account flow.
        fakeClientManager = _FakeClientManager([]);

        when(mockClient.register(
          username: anyNamed('username'),
          password: anyNamed('password'),
          initialDeviceDisplayName: anyNamed('initialDeviceDisplayName'),
          auth: anyNamed('auth'),
        ),).thenAnswer((_) async => RegisterResponse(
              userId: '@user:example.com',
              accessToken: 'tok',
              deviceId: 'D1',
            ),);
        when(mockAuthService.completeRegistration(any))
            .thenAnswer((_) async {});

        final controller = createController();
        await controller.checkServer();
        await controller.submitForm(
            username: 'user', password: 'Sunflower42!',);

        expect(controller.state, RegistrationState.done);
        expect(fakeClientManager.committed, isTrue);
        controller.dispose();
      });

      test('does not commit when registering the first account', () async {
        when(mockClient.register(
          username: anyNamed('username'),
          password: anyNamed('password'),
          initialDeviceDisplayName: anyNamed('initialDeviceDisplayName'),
          auth: anyNamed('auth'),
        ),).thenAnswer((_) async => RegisterResponse(
              userId: '@user:example.com',
              accessToken: 'tok',
              deviceId: 'D1',
            ),);
        when(mockAuthService.completeRegistration(any))
            .thenAnswer((_) async {});

        final controller = createController();
        await controller.checkServer();
        await controller.submitForm(
            username: 'user', password: 'Sunflower42!',);

        expect(controller.state, RegistrationState.done);
        expect(fakeClientManager.committed, isFalse);
        controller.dispose();
      });

      test('passes password to completeRegistration', () async {
        when(mockClient.register(
          username: anyNamed('username'),
          password: anyNamed('password'),
          initialDeviceDisplayName: anyNamed('initialDeviceDisplayName'),
          auth: anyNamed('auth'),
        ),).thenAnswer((_) async => RegisterResponse(
              userId: '@user:example.com',
              accessToken: 'tok',
              deviceId: 'D1',
            ),);
        when(mockAuthService.completeRegistration(any))
            .thenAnswer((_) async {});

        final controller = createController();
        await controller.checkServer();
        await controller.submitForm(
            username: 'user', password: 'mypassword123',);

        final captured = verify(mockAuthService.completeRegistration(
          any,
          password: captureAnyNamed('password'),
        ),).captured;
        expect(captured.single, 'mypassword123');
        controller.dispose();
      });

      test('guards against concurrent submit calls', () async {
        when(mockClient.register(
          username: anyNamed('username'),
          password: anyNamed('password'),
          initialDeviceDisplayName: anyNamed('initialDeviceDisplayName'),
          auth: anyNamed('auth'),
        ),).thenAnswer((_) async => RegisterResponse(
              userId: '@user:example.com',
              accessToken: 'tok',
              deviceId: 'D1',
            ),);
        when(mockAuthService.completeRegistration(any))
            .thenAnswer((_) async {});

        final controller = createController();
        await controller.checkServer();

        // Fire two submits — second should be blocked by guard.
        final f1 = controller.submitForm(
            username: 'user', password: 'Sunflower42!',);
        final f2 = controller.submitForm(
            username: 'user', password: 'Sunflower42!',);
        await f1;
        await f2;

        // register should only be called once.
        verify(mockClient.register(
          username: anyNamed('username'),
          password: anyNamed('password'),
          initialDeviceDisplayName: anyNamed('initialDeviceDisplayName'),
          auth: anyNamed('auth'),
        ),).called(1);
        controller.dispose();
      });

      test('shows friendly message for SocketException', () async {
        when(mockClient.register(
          username: anyNamed('username'),
          password: anyNamed('password'),
          initialDeviceDisplayName: anyNamed('initialDeviceDisplayName'),
          auth: anyNamed('auth'),
        ),).thenThrow(const SocketException('Connection refused'));

        final controller = createController();
        await controller.checkServer();
        await controller.submitForm(
            username: 'user', password: 'Sunflower42!',);

        expect(controller.state, RegistrationState.error);
        expect(controller.error, 'Could not reach server');
        controller.dispose();
      });

      test('shows friendly message for TimeoutException', () async {
        when(mockClient.register(
          username: anyNamed('username'),
          password: anyNamed('password'),
          initialDeviceDisplayName: anyNamed('initialDeviceDisplayName'),
          auth: anyNamed('auth'),
        ),).thenThrow(TimeoutException('timed out'));

        final controller = createController();
        await controller.checkServer();
        await controller.submitForm(
            username: 'user', password: 'Sunflower42!',);

        expect(controller.state, RegistrationState.error);
        expect(controller.error, 'Connection timed out');
        controller.dispose();
      });
    });

    group('cancelRegistration', () {
      setUp(() {
        when(mockAuthService.getServerAuthCapabilities(any, isLoggedIn: anyNamed('isLoggedIn')))
            .thenAnswer((_) async => const ServerAuthCapabilities(
                  supportsRegistration: true,
                  registrationStages: ['m.login.dummy'],
                ),);
      });

      test('resets from UIA stage to formReady', () async {
        when(mockClient.register(
          username: anyNamed('username'),
          password: anyNamed('password'),
          initialDeviceDisplayName: anyNamed('initialDeviceDisplayName'),
          auth: anyNamed('auth'),
        ),).thenThrow(
          MatrixException.fromJson({
            'flows': [
              {
                'stages': ['m.login.email.identity'],
              },
            ],
            'session': 'sess1',
          }),
        );

        final controller = createController();
        await controller.checkServer();
        await controller.submitForm(
            username: 'user', password: 'Sunflower42!',);

        expect(controller.state, RegistrationState.enterEmail);

        controller.cancelRegistration();

        expect(controller.state, RegistrationState.formReady);
        expect(controller.error, isNull);
        controller.dispose();
      });
    });

    group('requiresToken', () {
      test('returns true when registration stages include registration_token',
          () async {
        when(mockAuthService.getServerAuthCapabilities(any, isLoggedIn: anyNamed('isLoggedIn')))
            .thenAnswer((_) async => const ServerAuthCapabilities(
                  supportsRegistration: true,
                  registrationStages: ['m.login.registration_token'],
                ),);

        final controller = createController();
        await controller.checkServer();

        expect(controller.requiresToken, isTrue);
        controller.dispose();
      });

      test('returns false when registration stages do not include token',
          () async {
        when(mockAuthService.getServerAuthCapabilities(any, isLoggedIn: anyNamed('isLoggedIn')))
            .thenAnswer((_) async => const ServerAuthCapabilities(
                  supportsRegistration: true,
                  registrationStages: ['m.login.dummy'],
                ),);

        final controller = createController();
        await controller.checkServer();

        expect(controller.requiresToken, isFalse);
        controller.dispose();
      });

      test('rejects empty token when requiresToken is true', () async {
        when(mockAuthService.getServerAuthCapabilities(any, isLoggedIn: anyNamed('isLoggedIn')))
            .thenAnswer((_) async => const ServerAuthCapabilities(
                  supportsRegistration: true,
                  registrationStages: ['m.login.registration_token'],
                ),);

        final controller = createController();
        await controller.checkServer();
        await controller.submitForm(
            username: 'user', password: 'Sunflower42!',);

        expect(controller.tokenError, isNotNull);
        expect(controller.state, RegistrationState.formReady);
        controller.dispose();
      });

      test('auto-completes registration_token UIA stage with provided token',
          () async {
        when(mockAuthService.getServerAuthCapabilities(any, isLoggedIn: anyNamed('isLoggedIn')))
            .thenAnswer((_) async => const ServerAuthCapabilities(
                  supportsRegistration: true,
                  registrationStages: ['m.login.registration_token'],
                ),);

        final controller = createController();
        await controller.checkServer();

        when(mockAuthService.completeRegistration(any))
            .thenAnswer((_) async {});

        // First call throws UIA challenge, second call succeeds.
        var callCount = 0;
        when(mockClient.register(
          username: anyNamed('username'),
          password: anyNamed('password'),
          initialDeviceDisplayName: anyNamed('initialDeviceDisplayName'),
          auth: anyNamed('auth'),
        ),).thenAnswer((invocation) {
          callCount++;
          if (callCount == 1) {
            throw MatrixException.fromJson({
              'flows': [
                {
                  'stages': ['m.login.registration_token'],
                },
              ],
              'session': 'token_sess',
            });
          }
          return Future.value(RegisterResponse(
            userId: '@user:example.com',
            accessToken: 'tok',
            deviceId: 'D1',
          ),);
        });

        await controller.submitForm(
            username: 'user', password: 'Sunflower42!', token: 'mytoken',);

        // _advanceToNextStage fires _attemptRegister without await,
        // so pump the event loop to let the recursive call complete.
        await Future<void>.delayed(Duration.zero);
        await Future<void>.delayed(Duration.zero);

        expect(controller.state, RegistrationState.done);

        // Verify register was called with auth containing the token.
        final captured = verify(mockClient.register(
          username: anyNamed('username'),
          password: anyNamed('password'),
          initialDeviceDisplayName: anyNamed('initialDeviceDisplayName'),
          auth: captureAnyNamed('auth'),
        ),).captured;
        // Find the non-null auth argument (second call with token auth).
        final tokenAuth = captured.whereType<AuthenticationData>().last;
        final json = tokenAuth.toJson();
        expect(json['type'], 'm.login.registration_token');
        expect(json['token'], 'mytoken');
        controller.dispose();
      });
    });

    group('UIA params', () {
      setUp(() {
        when(mockAuthService.getServerAuthCapabilities(any, isLoggedIn: anyNamed('isLoggedIn')))
            .thenAnswer((_) async => const ServerAuthCapabilities(
                  supportsRegistration: true,
                  registrationStages: ['m.login.dummy'],
                ),);
      });

      test('extracts recaptchaPublicKey from UIA params', () async {
        when(mockClient.register(
          username: anyNamed('username'),
          password: anyNamed('password'),
          initialDeviceDisplayName: anyNamed('initialDeviceDisplayName'),
          auth: anyNamed('auth'),
        ),).thenThrow(
          MatrixException.fromJson({
            'flows': [
              {
                'stages': ['m.login.recaptcha'],
              },
            ],
            'session': 'sess_captcha',
            'params': {
              'm.login.recaptcha': {'public_key': 'test_site_key_123'},
            },
          }),
        );

        final controller = createController();
        await controller.checkServer();
        await controller.submitForm(
            username: 'user', password: 'Sunflower42!',);

        expect(controller.state, RegistrationState.recaptcha);
        expect(controller.recaptchaPublicKey, 'test_site_key_123');
        controller.dispose();
      });

      test('recaptchaPublicKey is null when no params', () async {
        when(mockClient.register(
          username: anyNamed('username'),
          password: anyNamed('password'),
          initialDeviceDisplayName: anyNamed('initialDeviceDisplayName'),
          auth: anyNamed('auth'),
        ),).thenThrow(
          MatrixException.fromJson({
            'flows': [
              {
                'stages': ['m.login.recaptcha'],
              },
            ],
            'session': 'sess_captcha',
          }),
        );

        final controller = createController();
        await controller.checkServer();
        await controller.submitForm(
            username: 'user', password: 'Sunflower42!',);

        expect(controller.state, RegistrationState.recaptcha);
        expect(controller.recaptchaPublicKey, isNull);
        controller.dispose();
      });

      test('extracts termsOfServicePolicies from UIA params', () async {
        when(mockClient.register(
          username: anyNamed('username'),
          password: anyNamed('password'),
          initialDeviceDisplayName: anyNamed('initialDeviceDisplayName'),
          auth: anyNamed('auth'),
        ),).thenThrow(
          MatrixException.fromJson({
            'flows': [
              {
                'stages': ['m.login.terms'],
              },
            ],
            'session': 'sess_terms',
            'params': {
              'm.login.terms': {
                'policies': {
                  'privacy_policy': {
                    'version': '1.0',
                    'en': {
                      'name': 'Privacy Policy',
                      'url': 'https://example.com/privacy',
                    },
                  },
                  'tos': {
                    'version': '2.0',
                    'en': {
                      'name': 'Terms of Service',
                      'url': 'https://example.com/tos',
                    },
                  },
                },
              },
            },
          }),
        );

        final controller = createController();
        await controller.checkServer();
        await controller.submitForm(
            username: 'user', password: 'Sunflower42!',);

        expect(controller.state, RegistrationState.acceptTerms);
        final policies = controller.termsOfServicePolicies;
        expect(policies, hasLength(2));
        expect(policies.any((p) => p.name == 'Privacy Policy'), isTrue);
        expect(policies.any((p) => p.name == 'Terms of Service'), isTrue);
        controller.dispose();
      });

      test('termsOfServicePolicies is empty when no params', () async {
        when(mockClient.register(
          username: anyNamed('username'),
          password: anyNamed('password'),
          initialDeviceDisplayName: anyNamed('initialDeviceDisplayName'),
          auth: anyNamed('auth'),
        ),).thenThrow(
          MatrixException.fromJson({
            'flows': [
              {
                'stages': ['m.login.terms'],
              },
            ],
            'session': 'sess_terms',
          }),
        );

        final controller = createController();
        await controller.checkServer();
        await controller.submitForm(
            username: 'user', password: 'Sunflower42!',);

        expect(controller.termsOfServicePolicies, isEmpty);
        controller.dispose();
      });
    });

    group('submitTerms', () {
      setUp(() {
        when(mockAuthService.getServerAuthCapabilities(any, isLoggedIn: anyNamed('isLoggedIn')))
            .thenAnswer((_) async => const ServerAuthCapabilities(
                  supportsRegistration: true,
                  registrationStages: ['m.login.dummy'],
                ),);
      });

      test('submits m.login.terms auth and advances', () async {
        var callCount = 0;
        when(mockClient.register(
          username: anyNamed('username'),
          password: anyNamed('password'),
          initialDeviceDisplayName: anyNamed('initialDeviceDisplayName'),
          auth: anyNamed('auth'),
        ),).thenAnswer((invocation) {
          callCount++;
          if (callCount == 1) {
            throw MatrixException.fromJson({
              'flows': [
                {
                  'stages': ['m.login.terms'],
                },
              ],
              'session': 'sess_terms',
              'params': {
                'm.login.terms': {
                  'policies': {
                    'tos': {
                      'version': '1.0',
                      'en': {
                        'name': 'Terms',
                        'url': 'https://example.com/tos',
                      },
                    },
                  },
                },
              },
            });
          }
          return Future.value(RegisterResponse(
            userId: '@user:example.com',
            accessToken: 'tok',
            deviceId: 'D1',
          ),);
        });
        when(mockAuthService.completeRegistration(any))
            .thenAnswer((_) async {});

        final controller = createController();
        await controller.checkServer();
        await controller.submitForm(
            username: 'user', password: 'Sunflower42!',);

        expect(controller.state, RegistrationState.acceptTerms);

        await controller.submitTerms();
        await Future<void>.delayed(Duration.zero);

        expect(controller.state, RegistrationState.acceptTerms,
            reason: 'unticked policies must block submission',);

        controller.togglePolicyAccepted('https://example.com/tos');
        expect(controller.allPoliciesAccepted, isTrue);

        await controller.submitTerms();
        await Future<void>.delayed(Duration.zero);

        expect(controller.state, RegistrationState.done);

        final captured = verify(mockClient.register(
          username: anyNamed('username'),
          password: anyNamed('password'),
          initialDeviceDisplayName: anyNamed('initialDeviceDisplayName'),
          auth: captureAnyNamed('auth'),
        ),).captured;
        final termsAuth = captured.whereType<AuthenticationData>().last;
        expect(termsAuth.toJson()['type'], 'm.login.terms');
        controller.dispose();
      });

      test('ignores submitTerms when not in acceptTerms state', () async {
        final controller = createController();
        await controller.checkServer();

        // Should be a no-op.
        await controller.submitTerms();
        expect(controller.state, RegistrationState.formReady);
        controller.dispose();
      });
    });

    group('cancelRegistration clears UIA state', () {
      setUp(() {
        when(mockAuthService.getServerAuthCapabilities(any, isLoggedIn: anyNamed('isLoggedIn')))
            .thenAnswer((_) async => const ServerAuthCapabilities(
                  supportsRegistration: true,
                  registrationStages: ['m.login.dummy'],
                ),);
      });

      test('clears uiaParams and recaptcha state on cancel', () async {
        when(mockClient.register(
          username: anyNamed('username'),
          password: anyNamed('password'),
          initialDeviceDisplayName: anyNamed('initialDeviceDisplayName'),
          auth: anyNamed('auth'),
        ),).thenThrow(
          MatrixException.fromJson({
            'flows': [
              {
                'stages': ['m.login.recaptcha'],
              },
            ],
            'session': 'sess_captcha',
            'params': {
              'm.login.recaptcha': {'public_key': 'key123'},
            },
          }),
        );

        final controller = createController();
        await controller.checkServer();
        await controller.submitForm(
            username: 'user', password: 'Sunflower42!',);

        expect(controller.state, RegistrationState.recaptcha);
        expect(controller.recaptchaPublicKey, 'key123');

        controller.cancelRegistration();

        expect(controller.state, RegistrationState.formReady);
        expect(controller.recaptchaPublicKey, isNull);
        expect(controller.recaptchaWaiting, isFalse);
        controller.dispose();
      });
    });

    group('submitForm state guard', () {
      test('ignores submit when not in formReady state', () async {
        when(mockAuthService.getServerAuthCapabilities(any, isLoggedIn: anyNamed('isLoggedIn')))
            .thenThrow(Exception('Connection refused'));

        final controller = createController();
        await controller.checkServer();
        expect(controller.state, RegistrationState.error);

        // Submit should be a no-op in error state.
        await controller.submitForm(
            username: 'user', password: 'Sunflower42!',);
        expect(controller.state, RegistrationState.error);
        controller.dispose();
      });
    });

    group('dispose', () {
      test('does not notify after dispose', () async {
        when(mockAuthService.getServerAuthCapabilities(any, isLoggedIn: anyNamed('isLoggedIn')))
            .thenAnswer((_) async => const ServerAuthCapabilities(
                  supportsRegistration: true,
                ),);

        final controller = createController();
        await controller.checkServer();

        var notifiedAfterDispose = false;
        controller.addListener(() => notifiedAfterDispose = true);
        controller.dispose();

        // Calling checkServer after dispose should not throw or notify.
        await controller.checkServer();
        expect(notifiedAfterDispose, isFalse);
      });
    });

    // ── live username availability ──────────────────────────────

    group('onUsernameChanged', () {
      setUp(() {
        when(mockAuthService.getServerAuthCapabilities(any,
                isLoggedIn: anyNamed('isLoggedIn'),),)
            .thenAnswer((_) async => const ServerAuthCapabilities(
                  supportsRegistration: true,
                  registrationStages: ['m.login.dummy'],
                ),);
      });

      test('reports available when the server says so', () async {
        when(mockClient.checkUsernameAvailability(any))
            .thenAnswer((_) async => true);

        final controller = createController();
        await controller.checkServer();

        controller.onUsernameChanged('ada');
        await Future<void>.delayed(Duration.zero);
        await Future<void>.delayed(Duration.zero);

        expect(controller.usernameAvailability, UsernameAvailability.available);
        expect(controller.usernameError, isNull);
        controller.dispose();
      });

      test('reports taken when the server says so', () async {
        when(mockClient.checkUsernameAvailability(any))
            .thenAnswer((_) async => false);

        final controller = createController();
        await controller.checkServer();

        controller.onUsernameChanged('ada');
        await Future<void>.delayed(Duration.zero);
        await Future<void>.delayed(Duration.zero);

        expect(controller.usernameAvailability, UsernameAvailability.taken);
        expect(controller.usernameError, 'This username is already taken');
        controller.dispose();
      });

      test('reports taken when the server raises M_USER_IN_USE', () async {
        when(mockClient.checkUsernameAvailability(any)).thenThrow(
          MatrixException.fromJson({
            'errcode': 'M_USER_IN_USE',
            'error': 'Taken',
          }),
        );

        final controller = createController();
        await controller.checkServer();

        controller.onUsernameChanged('ada');
        await Future<void>.delayed(Duration.zero);
        await Future<void>.delayed(Duration.zero);

        expect(controller.usernameAvailability, UsernameAvailability.taken);
        controller.dispose();
      });

      test('stays unknown when the endpoint is rate limited', () async {
        when(mockClient.checkUsernameAvailability(any)).thenThrow(
          MatrixException.fromJson({
            'errcode': 'M_LIMIT_EXCEEDED',
            'error': 'Slow down',
          }),
        );

        final controller = createController();
        await controller.checkServer();

        controller.onUsernameChanged('ada');
        await Future<void>.delayed(Duration.zero);
        await Future<void>.delayed(Duration.zero);

        expect(controller.usernameAvailability, UsernameAvailability.unknown);
        expect(controller.usernameError, isNull);
        controller.dispose();
      });

      test('rejects a malformed localpart without asking the server',
          () async {
        final controller = createController();
        await controller.checkServer();

        controller.onUsernameChanged('Bad User');
        await Future<void>.delayed(Duration.zero);

        expect(controller.usernameAvailability, UsernameAvailability.invalid);
        expect(controller.usernameError, isNotNull);
        verifyNever(mockClient.checkUsernameAvailability(any));
        controller.dispose();
      });

      test('clears availability when the field is emptied', () async {
        when(mockClient.checkUsernameAvailability(any))
            .thenAnswer((_) async => true);

        final controller = createController();
        await controller.checkServer();

        controller.onUsernameChanged('ada');
        await Future<void>.delayed(Duration.zero);
        await Future<void>.delayed(Duration.zero);
        expect(controller.usernameAvailability, UsernameAvailability.available);

        controller.onUsernameChanged('');
        expect(controller.usernameAvailability, UsernameAvailability.unknown);
        controller.dispose();
      });

      test('a stale in-flight check cannot overwrite a newer one', () async {
        final slow = Completer<bool?>();
        when(mockClient.checkUsernameAvailability('ada'))
            .thenAnswer((_) => slow.future);
        when(mockClient.checkUsernameAvailability('grace'))
            .thenAnswer((_) async => true);

        final controller = createController();
        await controller.checkServer();

        controller.onUsernameChanged('ada');
        await Future<void>.delayed(Duration.zero);

        controller.onUsernameChanged('grace');
        await Future<void>.delayed(Duration.zero);
        await Future<void>.delayed(Duration.zero);
        expect(controller.usernameAvailability, UsernameAvailability.available);

        // The abandoned 'ada' lookup resolves as taken, but must be ignored.
        slow.complete(false);
        await Future<void>.delayed(Duration.zero);

        expect(controller.usernameAvailability, UsernameAvailability.available);
        controller.dispose();
      });

      test('exposes the full Matrix ID preview', () async {
        final controller = createController(homeserver: 'https://matrix.org');
        await controller.checkServer();

        expect(controller.matrixIdPreview, isNull);

        controller.onUsernameChanged('ada');
        expect(controller.matrixIdPreview, '@ada:matrix.org');
        controller.dispose();
      });
    });

    // ── email identity stage ────────────────────────────────────

    group('email identity stage', () {
      void stubEmailStage() {
        when(mockAuthService.getServerAuthCapabilities(any,
                isLoggedIn: anyNamed('isLoggedIn'),),)
            .thenAnswer((_) async => const ServerAuthCapabilities(
                  supportsRegistration: true,
                  registrationStages: ['m.login.email.identity'],
                ),);
        when(mockClient.register(
          username: anyNamed('username'),
          password: anyNamed('password'),
          initialDeviceDisplayName: anyNamed('initialDeviceDisplayName'),
          auth: anyNamed('auth'),
        ),).thenThrow(
          MatrixException.fromJson({
            'flows': [
              {
                'stages': ['m.login.email.identity'],
              },
            ],
            'session': 'sess_email',
          }),
        );
      }

      Future<RegistrationController> reachEmailStage() async {
        stubEmailStage();
        final controller = createController();
        await controller.checkServer();
        await controller.submitForm(
            username: 'ada', password: 'Sunflower42!',);
        expect(controller.state, RegistrationState.enterEmail);
        return controller;
      }

      test('advertises that the server wants an email', () async {
        final controller = await reachEmailStage();

        expect(controller.requiresEmail, isTrue);
        controller.dispose();
      });

      test('rejects an empty address', () async {
        final controller = await reachEmailStage();

        await controller.submitEmail('   ');

        expect(controller.state, RegistrationState.enterEmail);
        expect(controller.emailError, 'Please enter an email address');
        controller.dispose();
      });

      test('rejects a malformed address', () async {
        final controller = await reachEmailStage();

        await controller.submitEmail('not-an-email');

        expect(controller.state, RegistrationState.enterEmail);
        expect(controller.emailError, 'Please enter a valid email address');
        verifyNever(mockClient.requestTokenToRegisterEmail(any, any, any));
        controller.dispose();
      });

      test('requests a token and waits for verification', () async {
        final controller = await reachEmailStage();
        when(mockClient.requestTokenToRegisterEmail(any, any, any))
            .thenAnswer((_) async => RequestTokenResponse(sid: 'sid_1'));

        await controller.submitEmail('ada@example.com');

        expect(controller.state, RegistrationState.awaitingEmailVerification);
        expect(controller.pendingEmailAddress, 'ada@example.com');
        expect(controller.emailSending, isFalse);
        expect(controller.emailError, isNull);

        final captured =
            verify(mockClient.requestTokenToRegisterEmail(
          captureAny,
          captureAny,
          captureAny,
        ),).captured;
        expect(captured[0], isA<String>().having((s) => s.length, 'length', 32));
        expect(captured[1], 'ada@example.com');
        expect(captured[2], 1);
        controller.dispose();
      });

      test('surfaces a rejected address on the email field', () async {
        final controller = await reachEmailStage();
        when(mockClient.requestTokenToRegisterEmail(any, any, any)).thenThrow(
          MatrixException.fromJson({
            'errcode': 'M_THREEPID_IN_USE',
            'error': 'Already bound',
          }),
        );

        await controller.submitEmail('ada@example.com');

        expect(controller.state, RegistrationState.enterEmail);
        expect(controller.emailError, 'This email is already registered');
        controller.dispose();
      });

      test('resend increments send_attempt and reuses the client secret',
          () async {
        final controller = await reachEmailStage();
        when(mockClient.requestTokenToRegisterEmail(any, any, any))
            .thenAnswer((_) async => RequestTokenResponse(sid: 'sid_1'));

        await controller.submitEmail('ada@example.com');
        await controller.resendVerificationEmail();

        final captured =
            verify(mockClient.requestTokenToRegisterEmail(
          captureAny,
          any,
          captureAny,
        ),).captured;
        expect(captured[0], captured[2], reason: 'client secret must be reused');
        expect(captured[1], 1);
        expect(captured[3], 2);
        controller.dispose();
      });

      test('submits threepid_creds once the link is followed', () async {
        stubEmailStage();
        final controller = createController();
        await controller.checkServer();
        await controller.submitForm(
            username: 'ada', password: 'Sunflower42!',);

        when(mockClient.requestTokenToRegisterEmail(any, any, any))
            .thenAnswer((_) async => RequestTokenResponse(sid: 'sid_1'));
        await controller.submitEmail('ada@example.com');

        when(mockClient.register(
          username: anyNamed('username'),
          password: anyNamed('password'),
          initialDeviceDisplayName: anyNamed('initialDeviceDisplayName'),
          auth: anyNamed('auth'),
        ),).thenAnswer((_) async => RegisterResponse(
              userId: '@ada:example.com',
              accessToken: 'tok',
              deviceId: 'D1',
            ),);
        when(mockAuthService.completeRegistration(any))
            .thenAnswer((_) async {});

        await controller.confirmEmailVerified();

        expect(controller.state, RegistrationState.done);

        final auth = verify(mockClient.register(
          username: anyNamed('username'),
          password: anyNamed('password'),
          initialDeviceDisplayName: anyNamed('initialDeviceDisplayName'),
          auth: captureAnyNamed('auth'),
        ),).captured.last as AuthenticationData;
        final json = auth.toJson();
        expect(json['type'], 'm.login.email.identity');
        expect(json['session'], 'sess_email');
        expect(
          json['threepid_creds'],
          isA<Map<String, dynamic>>()
              .having((m) => m['sid'], 'sid', 'sid_1')
              .having((m) => m['client_secret'], 'client_secret', isNotEmpty),
        );
        controller.dispose();
      });

      test('holds on the waiting screen when the link is not yet followed',
          () async {
        stubEmailStage();
        final controller = createController();
        await controller.checkServer();
        await controller.submitForm(
            username: 'ada', password: 'Sunflower42!',);

        when(mockClient.requestTokenToRegisterEmail(any, any, any))
            .thenAnswer((_) async => RequestTokenResponse(sid: 'sid_1'));
        await controller.submitEmail('ada@example.com');

        // The server re-challenges because the threepid is still unverified.
        await controller.confirmEmailVerified();

        expect(controller.state, RegistrationState.awaitingEmailVerification);
        expect(controller.emailError, contains('could not confirm'));
        controller.dispose();
      });

      test('changeEmailAddress returns to the entry step', () async {
        final controller = await reachEmailStage();
        when(mockClient.requestTokenToRegisterEmail(any, any, any))
            .thenAnswer((_) async => RequestTokenResponse(sid: 'sid_1'));
        await controller.submitEmail('ada@example.com');

        controller.changeEmailAddress();

        expect(controller.state, RegistrationState.enterEmail);
        expect(controller.pendingEmailAddress, isNull);
        controller.dispose();
      });

      test('confirmEmailVerified is a no-op outside the waiting state',
          () async {
        final controller = await reachEmailStage();

        await controller.confirmEmailVerified();

        expect(controller.state, RegistrationState.enterEmail);
        controller.dispose();
      });
    });
  });
}

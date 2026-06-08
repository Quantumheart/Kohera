import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kohera/core/services/matrix_service.dart';
import 'package:matrix/matrix.dart';
import 'package:matrix/src/utils/cached_stream_controller.dart';
import 'package:mockito/mockito.dart';

import 'matrix_service_test.mocks.dart';

class _FakeDatabase extends Fake implements DatabaseApi {
  _FakeDatabase(this._stored);
  final Map<String, dynamic>? _stored;

  @override
  Future<Map<String, dynamic>?> getClient(String name) async => _stored;
}

MatrixException _permanent() => MatrixException.fromJson({
      'errcode': 'M_UNKNOWN_TOKEN',
      'error': 'Token revoked',
    });

void main() {
  // Restore activates the session, which touches WidgetsBinding. The default
  // (non-resumed) test lifecycle keeps foreground sync deferred, so no timers
  // are scheduled.
  TestWidgetsFlutterBinding.ensureInitialized();

  late MockClient mockClient;
  late MockFlutterSecureStorage mockStorage;
  late MatrixService service;

  MatrixService buildService({Map<String, dynamic>? stored}) {
    when(mockClient.rooms).thenReturn([]);
    when(mockClient.onSync).thenReturn(CachedStreamController<SyncUpdate>());
    when(mockClient.onPresenceChanged)
        .thenReturn(CachedStreamController<CachedPresence>());
    when(mockClient.onLoginStateChanged)
        .thenReturn(CachedStreamController<LoginState>());
    when(mockClient.onUiaRequest).thenReturn(CachedStreamController());
    when(mockClient.database).thenReturn(_FakeDatabase(stored));
    final s = MatrixService(
      client: mockClient,
      storage: mockStorage,
      clientName: 'test',
      backoff: (_) async {},
    );
    addTearDown(s.dispose);
    return s;
  }

  setUp(() {
    mockClient = MockClient();
    mockStorage = MockFlutterSecureStorage();
  });

  group('handleSoftLogout (token refresh)', () {
    setUp(() {
      service = buildService(stored: {'token': 't'});
      service.auth.isLoggedIn = true;
      when(mockClient.accessToken).thenReturn('tok');
      when(mockClient.userID).thenReturn('@u:e.com');
      when(mockClient.homeserver).thenReturn(Uri.parse('https://e.com'));
      when(mockClient.deviceID).thenReturn('D1');
      when(mockClient.encryption).thenReturn(null);
    });

    test('retries transient failures then recovers', () async {
      var calls = 0;
      when(mockClient.refreshAccessToken()).thenAnswer((_) async {
        calls++;
        if (calls <= 2) throw const SocketException('down');
      });

      await service.handleSoftLogout();

      expect(calls, 3);
      expect(service.isLoggedIn, isTrue);
      expect(service.isReconnecting, isFalse);
    });

    test('keeps session reconnecting after exhausting retries', () async {
      var calls = 0;
      when(mockClient.refreshAccessToken()).thenAnswer((_) async {
        calls++;
        throw const SocketException('down');
      });

      await service.handleSoftLogout();

      // 4 retries -> 5 total attempts.
      expect(calls, 5);
      expect(service.isLoggedIn, isTrue);
      expect(service.isReconnecting, isTrue);
    });

    test('logs out promptly on permanent failure', () async {
      var calls = 0;
      when(mockClient.refreshAccessToken()).thenAnswer((_) async {
        calls++;
        throw _permanent();
      });

      await service.handleSoftLogout();

      expect(calls, 1);
      expect(service.isLoggedIn, isFalse);
      expect(service.isReconnecting, isFalse);
    });
  });

  group('session restore', () {
    test('retries transient failures then recovers', () async {
      service = buildService(stored: {'token': 't'});
      var initCalls = 0;
      when(mockClient.init()).thenAnswer((_) async {
        initCalls++;
        if (initCalls <= 2) throw const SocketException('down');
      });
      when(mockClient.isLogged()).thenAnswer((_) => initCalls >= 3);

      await service.init();

      expect(initCalls, 3);
      expect(service.isLoggedIn, isTrue);
      expect(service.isReconnecting, isFalse);
    });

    test('stays reconnecting when session data loads but sync keeps failing',
        () async {
      service = buildService(stored: {'token': 't'});
      var initCalls = 0;
      var logged = false;
      when(mockClient.init()).thenAnswer((_) async {
        initCalls++;
        // The final retry loads the session before the connectivity step fails.
        if (initCalls >= 5) logged = true;
        throw const SocketException('down');
      });
      when(mockClient.isLogged()).thenAnswer((_) => logged);

      await service.init();

      expect(initCalls, 5);
      expect(service.isLoggedIn, isTrue);
      expect(service.isReconnecting, isTrue);
    });

    test('logs out and clears session on permanent failure', () async {
      service = buildService(stored: {'token': 't'});
      var initCalls = 0;
      when(mockClient.init()).thenAnswer((_) async {
        initCalls++;
        throw _permanent();
      });
      when(mockClient.isLogged()).thenReturn(false);

      await service.init();

      expect(initCalls, 1);
      expect(service.isLoggedIn, isFalse);
      expect(service.isReconnecting, isFalse);
      verify(mockStorage.delete(key: 'kohera_test_access_token')).called(1);
    });
  });
}

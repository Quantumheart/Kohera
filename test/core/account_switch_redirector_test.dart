import 'package:flutter_test/flutter_test.dart';
import 'package:kohera/core/routing/app_router.dart';
import 'package:kohera/core/services/matrix_service.dart';
import 'package:matrix/matrix.dart';
import 'package:matrix/src/utils/cached_stream_controller.dart';
import 'package:mockito/mockito.dart';

import '../services/matrix_service_test.mocks.dart';

MatrixService _makeService(String name) {
  final mockClient = MockClient();
  when(mockClient.rooms).thenReturn([]);
  when(mockClient.userID).thenReturn('@$name:example.com');
  when(mockClient.dispose()).thenAnswer((_) async {});
  when(mockClient.onSync).thenReturn(CachedStreamController<SyncUpdate>());
  when(mockClient.onPresenceChanged)
      .thenReturn(CachedStreamController<CachedPresence>());
  return MatrixService(client: mockClient, clientName: name);
}

void main() {
  late MatrixService accountA;
  late MatrixService accountB;

  setUp(() {
    accountA = _makeService('a');
    accountB = _makeService('b');
  });

  group('AccountSwitchRedirector', () {
    test('no redirect when the active account is unchanged', () {
      final redirector = AccountSwitchRedirector(accountA);

      expect(redirector.redirectFor(accountA, '/rooms/!x:server'), isNull);
      expect(redirector.redirectFor(accountA, '/'), isNull);
    });

    test('falls back to room list when account switches on a room route', () {
      final redirector = AccountSwitchRedirector(accountA);

      expect(redirector.redirectFor(accountB, '/rooms/!x:server'), '/');
    });

    test('redirects from nested room sub-routes too', () {
      final redirector = AccountSwitchRedirector(accountA);

      expect(
        redirector.redirectFor(accountB, '/rooms/!x:server/details'),
        '/',
      );
    });

    test('no redirect when account switches off a room route', () {
      final redirector = AccountSwitchRedirector(accountA);

      expect(redirector.redirectFor(accountB, '/settings'), isNull);
    });

    test('only redirects once per switch, not on every later evaluation', () {
      final redirector = AccountSwitchRedirector(accountA);

      expect(redirector.redirectFor(accountB, '/rooms/!x:server'), '/');
      expect(redirector.redirectFor(accountB, '/rooms/!x:server'), isNull);
    });
  });
}

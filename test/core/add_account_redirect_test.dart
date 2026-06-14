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
  group('addAccountRedirect', () {
    test('redirects home when there is no pending service', () {
      expect(addAccountRedirect(null), '/');
    });

    test('does not redirect when a pending service exists', () {
      expect(addAccountRedirect(_makeService('pending')), isNull);
    });
  });
}

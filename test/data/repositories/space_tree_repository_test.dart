import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:kohera/data/repositories/space_tree_repository.dart';
import 'package:kohera/data/services/matrix_client_service.dart';
import 'package:matrix/matrix.dart';
import 'package:matrix/src/utils/cached_stream_controller.dart';
import 'package:mockito/mockito.dart';

import '../../services/matrix_service_test.mocks.dart';

void main() {
  late MockClient mockClient;
  late SpaceTreeRepository repository;

  setUp(() {
    mockClient = MockClient();
    when(mockClient.onSync).thenReturn(CachedStreamController<SyncUpdate>());
    when(mockClient.onLoginStateChanged)
        .thenReturn(CachedStreamController<LoginState>());
    repository = SpaceTreeRepository(
      clientService: MatrixClientService(mockClient),
    );
  });

  tearDown(() {
    repository.dispose();
  });

  group('SpaceTreeRepository initial load state', () {
    test('flags start false', () {
      expect(repository.hasSyncedOnce, false);
      expect(repository.roomsHydrated, false);
    });

    test('hasSyncedOnce true after first sync event', () async {
      final syncCtrl = mockClient.onSync;
      syncCtrl.add(SyncUpdate(nextBatch: 'batch'));
      await Future<void>.delayed(Duration.zero);
      expect(repository.hasSyncedOnce, true);
      expect(repository.roomsHydrated, false);
    });

    test('roomsHydrated true when client already logged in at construction',
        () async {
      final loginCtrl =
          mockClient.onLoginStateChanged;
      final roomsLoading = Completer<void>();
      when(mockClient.roomsLoading).thenAnswer((_) => roomsLoading.future);
      loginCtrl.add(LoginState.loggedIn);

      repository.dispose();
      repository = SpaceTreeRepository(
        clientService: MatrixClientService(mockClient),
      );

      expect(repository.roomsHydrated, false);
      roomsLoading.complete();
      await Future<void>.delayed(Duration.zero);
      expect(repository.roomsHydrated, true);
      expect(repository.hasSyncedOnce, false);
    });

    test('roomsHydrated true when login state transitions after construction',
        () async {
      final loginCtrl =
          mockClient.onLoginStateChanged;
      final roomsLoading = Completer<void>();
      when(mockClient.roomsLoading).thenAnswer((_) => roomsLoading.future);

      loginCtrl.add(LoginState.loggedIn);
      await Future<void>.delayed(Duration.zero);
      expect(repository.roomsHydrated, false);

      roomsLoading.complete();
      await Future<void>.delayed(Duration.zero);
      expect(repository.roomsHydrated, true);
    });
  });
}

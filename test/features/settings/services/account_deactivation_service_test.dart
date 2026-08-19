// Redundant default args are kept in verify() to assert exact forwarding.
// ignore_for_file: avoid_redundant_argument_values
import 'package:flutter_test/flutter_test.dart';
import 'package:kohera/data/repositories/user_repository.dart';
import 'package:matrix/matrix.dart';
import 'package:matrix/src/utils/cached_stream_controller.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';

@GenerateNiceMocks([
  MockSpec<Client>(),
])
import '../../../mocks/matrix_service_mock.mocks.dart';
import 'account_deactivation_service_test.mocks.dart';

void main() {
  late MockClient mockClient;
  late MockMatrixService mockMatrix;
  late UserRepository repo;

  setUp(() {
    mockClient = MockClient();
    mockMatrix = MockMatrixService();
    when(mockMatrix.client).thenReturn(mockClient);
    when(mockClient.onSync).thenReturn(CachedStreamController<SyncUpdate>());

    // Run the UIA callback inline so deactivateAccount is actually invoked.
    when(mockClient.uiaRequestBackground<IdServerUnbindResult>(any))
        .thenAnswer((inv) {
      final cb = inv.positionalArguments[0]
          as Future<IdServerUnbindResult> Function(AuthenticationData?);
      return cb(null);
    });

    repo = UserRepository(matrix: mockMatrix);
  });

  group('UserRepository.deactivateAccount', () {
    test('defaults: erase=false, idServer omitted', () async {
      when(mockClient.deactivateAccount(
        auth: anyNamed('auth'),
        erase: anyNamed('erase'),
        idServer: anyNamed('idServer'),
      )).thenAnswer((_) async => IdServerUnbindResult.success);

      final result = await repo.deactivateAccount();

      expect(result, IdServerUnbindResult.success);
      verify(mockClient.deactivateAccount(
        auth: null,
        erase: false,
        idServer: null,
      )).called(1);
    });

    test('forwards erase=true', () async {
      when(mockClient.deactivateAccount(
        auth: anyNamed('auth'),
        erase: anyNamed('erase'),
        idServer: anyNamed('idServer'),
      )).thenAnswer((_) async => IdServerUnbindResult.success);

      await repo.deactivateAccount(erase: true);

      verify(mockClient.deactivateAccount(
        auth: null,
        erase: true,
        idServer: null,
      )).called(1);
    });

    test('forwards idServer when provided', () async {
      when(mockClient.deactivateAccount(
        auth: anyNamed('auth'),
        erase: anyNamed('erase'),
        idServer: anyNamed('idServer'),
      )).thenAnswer((_) async => IdServerUnbindResult.success);

      await repo.deactivateAccount(idServer: 'https://vector.im');

      verify(mockClient.deactivateAccount(
        auth: null,
        erase: false,
        idServer: 'https://vector.im',
      )).called(1);
    });

    test('surfaces server errors', () async {
      when(mockClient.deactivateAccount(
        auth: anyNamed('auth'),
        erase: anyNamed('erase'),
        idServer: anyNamed('idServer'),
      )).thenThrow(MatrixException.fromJson({
        'errcode': 'M_FORBIDDEN',
        'error': 'Wrong password',
      }));

      await expectLater(
        repo.deactivateAccount(),
        throwsA(isA<MatrixException>()),
      );
    });
  });
}

// Redundant default args are kept in verify() to assert exact forwarding.
// ignore_for_file: avoid_redundant_argument_values
import 'package:flutter_test/flutter_test.dart';
import 'package:kohera/core/services/matrix_service.dart';
import 'package:kohera/features/settings/services/account_deactivation_service.dart';
import 'package:matrix/matrix.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';

@GenerateNiceMocks([
  MockSpec<Client>(),
  MockSpec<MatrixService>(),
])
import 'account_deactivation_service_test.mocks.dart';

void main() {
  late MockClient mockClient;
  late MockMatrixService mockMatrix;
  late AccountDeactivationService service;

  setUp(() {
    mockClient = MockClient();
    mockMatrix = MockMatrixService();
    when(mockMatrix.client).thenReturn(mockClient);

    // Run the UIA callback inline so deactivateAccount is actually invoked.
    when(mockClient.uiaRequestBackground<IdServerUnbindResult>(any))
        .thenAnswer((inv) {
      final cb = inv.positionalArguments[0]
          as Future<IdServerUnbindResult> Function(AuthenticationData?);
      return cb(null);
    });

    service = AccountDeactivationService(matrix: mockMatrix);
  });

  group('AccountDeactivationService.deactivate', () {
    test('defaults: erase=false, idServer omitted', () async {
      when(mockClient.deactivateAccount(
        auth: anyNamed('auth'),
        erase: anyNamed('erase'),
        idServer: anyNamed('idServer'),
      )).thenAnswer((_) async => IdServerUnbindResult.success);

      final result = await service.deactivate();

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

      await service.deactivate(erase: true);

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

      await service.deactivate(idServer: 'https://vector.im');

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
        service.deactivate(),
        throwsA(isA<MatrixException>()),
      );
    });
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:kohera/core/state/uia_interaction_controller.dart';
import 'package:kohera/data/services/matrix_client_service.dart';
import 'package:kohera/data/services/password_cache.dart';
import 'package:matrix/matrix.dart';
import 'package:matrix/src/utils/cached_stream_controller.dart';
import 'package:mockito/mockito.dart';

import '../../services/matrix_service_test.mocks.dart';

void main() {
  late MockClient mockClient;
  late UiaInteractionController controller;

  setUp(() {
    mockClient = MockClient();
    when(mockClient.onUiaRequest).thenReturn(CachedStreamController());
    controller = UiaInteractionController(
      matrixClientService: MatrixClientService(mockClient),
      passwordCache: PasswordCache(),
    );
  });

  group('listenForUia', () {
    test('subscribes to client UIA stream', () {
      controller.listenForUia();
      verify(mockClient.onUiaRequest).called(greaterThanOrEqualTo(1));
    });
  });

  group('cancelUiaSub', () {
    test('cancels subscription without error', () {
      controller.listenForUia();
      controller.cancelUiaSub();
    });
  });

  group('dispose', () {
    test('closes stream controller and subscription', () {
      controller.listenForUia();
      controller.dispose();
    });
  });

  group('completeUiaWithPassword', () {
    test('does nothing when client has no userID', () {
      when(mockClient.userID).thenReturn(null);

      final request = MockUiaRequest();
      controller.completeUiaWithPassword(request, 'password');

      verifyZeroInteractions(request);
    });
  });
}

class MockUiaRequest extends Mock implements UiaRequest<dynamic> {}

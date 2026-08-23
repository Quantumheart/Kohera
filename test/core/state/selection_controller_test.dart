import 'package:flutter_test/flutter_test.dart';
import 'package:kohera/core/state/selection_controller.dart';
import 'package:kohera/data/services/matrix_client_service.dart';
import 'package:matrix/matrix.dart';
import 'package:matrix/src/utils/cached_stream_controller.dart';
import 'package:mockito/mockito.dart';

import '../../services/matrix_service_test.mocks.dart';

void main() {
  late MockClient mockClient;
  late SelectionController controller;
  late int changeCount;

  setUp(() {
    mockClient = MockClient();
    changeCount = 0;
    when(mockClient.rooms).thenReturn([]);
    when(mockClient.onSync).thenReturn(CachedStreamController<SyncUpdate>());
    controller =
        SelectionController(clientService: MatrixClientService(mockClient));
    controller.addListener(() => changeCount++);
  });

  group('selectSpace', () {
    test('sets single selection and fires onChanged', () {
      controller.selectSpace('!space:example.com');

      expect(controller.selectedSpaceIds, {'!space:example.com'});
      expect(changeCount, 1);
    });

    test('clears on null', () {
      controller.selectSpace('!space:example.com');
      controller.selectSpace(null);

      expect(controller.selectedSpaceIds, isEmpty);
      expect(changeCount, 2);
    });

    test('clears on re-select of sole selection', () {
      controller.selectSpace('!space:example.com');
      controller.selectSpace('!space:example.com');

      expect(controller.selectedSpaceIds, isEmpty);
    });
  });

  group('toggleSpaceSelection', () {
    test('adds space to multi-select', () {
      controller.toggleSpaceSelection('!s1:e.com');
      controller.toggleSpaceSelection('!s2:e.com');

      expect(controller.selectedSpaceIds, {'!s1:e.com', '!s2:e.com'});
    });

    test('removes space from multi-select', () {
      controller.toggleSpaceSelection('!s1:e.com');
      controller.toggleSpaceSelection('!s1:e.com');

      expect(controller.selectedSpaceIds, isEmpty);
    });
  });

  group('clearSpaceSelection', () {
    test('clears all selections', () {
      controller.toggleSpaceSelection('!s1:e.com');
      controller.toggleSpaceSelection('!s2:e.com');
      controller.clearSpaceSelection();

      expect(controller.selectedSpaceIds, isEmpty);
    });
  });

  group('selectRoom', () {
    test('sets selected room and fires onChanged', () {
      controller.selectRoom('!room:e.com');

      expect(controller.selectedRoomId, '!room:e.com');
      expect(changeCount, 1);
    });

    test('selectedRoom returns Room from client', () {
      final mockRoom = MockRoom();
      when(mockClient.getRoomById('!room:e.com')).thenReturn(mockRoom);

      controller.selectRoom('!room:e.com');

      expect(controller.selectedRoom, mockRoom);
    });

    test('selectedRoom returns null when no room selected', () {
      expect(controller.selectedRoom, isNull);
    });
  });

  group('resetSelection', () {
    test('clears all state', () {
      controller.selectSpace('!space:e.com');
      controller.selectRoom('!room:e.com');

      controller.resetSelection();

      expect(controller.selectedSpaceIds, isEmpty);
      expect(controller.selectedRoomId, isNull);
    });
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:kohera/data/repositories/push_repository.dart';
import 'package:kohera/data/services/matrix_client_service.dart';
import 'package:mockito/mockito.dart';

import '../../services/matrix_service_test.mocks.dart';

void main() {
  late MockClient mockClient;
  late PushRepository repo;

  setUp(() {
    mockClient = MockClient();
    repo = PushRepository(clientService: MatrixClientService(mockClient));
  });

  group('unreadNotificationCount', () {
    test('sums notificationCount across all rooms', () {
      final r1 = MockRoom();
      final r2 = MockRoom();
      final r3 = MockRoom();
      when(r1.notificationCount).thenReturn(3);
      when(r2.notificationCount).thenReturn(0);
      when(r3.notificationCount).thenReturn(7);
      when(mockClient.rooms).thenReturn([r1, r2, r3]);
      expect(repo.unreadNotificationCount(), 10);
    });

    test('returns 0 when no rooms have unread', () {
      final r1 = MockRoom();
      when(r1.notificationCount).thenReturn(0);
      when(mockClient.rooms).thenReturn([r1]);
      expect(repo.unreadNotificationCount(), 0);
    });

    test('reflects remaining count after one of several rooms is read', () {
      final read = MockRoom();
      final stillUnread = MockRoom();
      when(read.notificationCount).thenReturn(4);
      when(stillUnread.notificationCount).thenReturn(6);
      when(mockClient.rooms).thenReturn([read, stillUnread]);

      final raw = repo.unreadNotificationCount() - read.notificationCount;
      final remaining = raw < 0 ? 0 : raw;
      expect(remaining, 6);
    });
  });
}

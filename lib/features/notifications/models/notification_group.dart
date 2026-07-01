import 'package:kohera/features/notifications/models/thread_sub_group.dart';
import 'package:matrix/matrix.dart' as matrix_sdk;

class NotificationGroup {
  final String roomId;
  final String roomName;
  final List<matrix_sdk.Notification> notifications;
  final List<ThreadSubGroup> subGroups;

  const NotificationGroup({
    required this.roomId,
    required this.roomName,
    required this.notifications,
    required this.subGroups,
  });
}

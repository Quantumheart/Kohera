import 'package:kohera/features/notifications/models/kohera_notification_item.dart';
import 'package:kohera/features/notifications/models/thread_sub_group.dart';

class NotificationGroup {
  final String roomId;
  final String roomName;
  final List<KoheraNotificationItem> notifications;
  final List<ThreadSubGroup> subGroups;

  const NotificationGroup({
    required this.roomId,
    required this.roomName,
    required this.notifications,
    required this.subGroups,
  });
}

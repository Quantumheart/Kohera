import 'package:kohera/features/notifications/models/kohera_notification_item.dart';

class ThreadSubGroup {
  final String? threadRootId;
  final List<KoheraNotificationItem> notifications;

  const ThreadSubGroup({
    required this.threadRootId,
    required this.notifications,
  });
}

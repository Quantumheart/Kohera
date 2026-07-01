class KoheraNotificationItem {
  final String eventId;
  final String roomId;
  final String senderName;
  final String body;
  final int timestamp;
  final bool isRead;
  final bool isMention;
  final String? threadRootId;

  const KoheraNotificationItem({
    required this.eventId,
    required this.roomId,
    required this.senderName,
    required this.body,
    required this.timestamp,
    required this.isRead,
    required this.isMention,
    required this.threadRootId,
  });
}

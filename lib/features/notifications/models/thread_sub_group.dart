import 'package:matrix/matrix.dart' as matrix_sdk;

class ThreadSubGroup {
  final String? threadRootId;
  final List<matrix_sdk.Notification> notifications;

  const ThreadSubGroup({
    required this.threadRootId,
    required this.notifications,
  });
}

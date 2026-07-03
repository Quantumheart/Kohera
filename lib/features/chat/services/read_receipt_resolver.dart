import 'package:kohera/features/chat/models/kohera_read_receipt.dart';
import 'package:kohera/shared/models/kohera_user_summary_mapper.dart';
import 'package:matrix/matrix.dart';

/// Builds a map from eventId → list of [KoheraReadReceipt] for other users.
///
/// This is the conversion boundary: it reads SDK receipt state from [room]
/// and produces Kohera-owned [KoheraReadReceipt]s with pre-computed
/// [KoheraUserSummary] fields. The consuming widgets (ReadReceiptsRow,
/// showReadersSheet) never touch the Matrix SDK directly.
///
/// Iterates [room.receiptState.global.otherUsers] (and optionally
/// mainThread) once, so cost is O(N) where N = number of users with
/// receipts, rather than O(N×M) if we queried per-event.
Map<String, List<KoheraReadReceipt>> buildReceiptMap(
  Room room,
  String? myUserId, {
  String? threadRootId,
}) {
  final map = <String, List<KoheraReadReceipt>>{};
  final seen = <String>{};

  void addReceipts(Map<String, LatestReceiptStateData> users) {
    for (final entry in users.entries) {
      final userId = entry.key;
      if (userId == myUserId || seen.contains(userId)) continue;
      seen.add(userId);

      final data = entry.value;
      final user = room.unsafeGetUserFromMemoryOrFallback(userId);
      final receipt = KoheraReadReceipt(
        user: toKoheraUserSummary(user),
        time: data.timestamp,
      );
      (map[data.eventId] ??= []).add(receipt);
    }
  }

  if (threadRootId != null) {
    final threadState = room.receiptState.byThread[threadRootId];
    if (threadState != null) addReceipts(threadState.otherUsers);
    return map;
  }

  addReceipts(room.receiptState.global.otherUsers);

  final mainThread = room.receiptState.mainThread;
  if (mainThread != null) {
    addReceipts(mainThread.otherUsers);
  }

  return map;
}

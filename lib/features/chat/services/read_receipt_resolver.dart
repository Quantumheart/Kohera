import 'package:kohera/features/chat/models/kohera_read_receipt.dart';
import 'package:kohera/shared/services/user_summary_resolver.dart';
import 'package:matrix/matrix.dart';

/// Builds a map from eventId → list of [KoheraReadReceipt] for other users.
///
/// This is the conversion boundary: it reads SDK receipt state from [room]
/// and produces Kohera-owned [KoheraReadReceipt]s with pre-computed
/// [KoheraUserSummary] fields (via [UserSummaryResolver]). The consuming
/// widgets (ReadReceiptsRow, showReadersSheet) never touch the Matrix SDK
/// directly.
///
/// Iterate [room.receiptState.global.otherUsers] (and optionally mainThread)
/// once, so cost is O(N) where N = number of users with receipts, rather than
/// O(N×M) if we queried per-event. Invoke as
/// `const ReadReceiptResolver()(room, myUserId)`.
class ReadReceiptResolver {
  const ReadReceiptResolver();

  Map<String, List<KoheraReadReceipt>> call(
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
          user: const UserSummaryResolver()(user),
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
}

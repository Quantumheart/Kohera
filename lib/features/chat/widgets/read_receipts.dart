import 'dart:async';

import 'package:flutter/material.dart';
import 'package:kohera/features/chat/models/kohera_read_receipt.dart';
import 'package:kohera/shared/models/kohera_user_summary_mapper.dart';
import 'package:kohera/shared/services/avatar_resolver.dart';
import 'package:kohera/shared/widgets/user_avatar.dart';
import 'package:matrix/matrix.dart';

// ── Receipt map builder ──────────────────────────────────────

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

// ── ReadReceiptsRow ──────────────────────────────────────────

/// Shows up to 3 overlapping user avatars for read receipts on a message,
/// with a "+N" badge when more than 3 users have read it.
class ReadReceiptsRow extends StatelessWidget {
  const ReadReceiptsRow({
    required this.receipts,
    required this.avatarResolver,
    required this.isMe,
    super.key,
  });

  final List<KoheraReadReceipt> receipts;
  final AvatarResolver avatarResolver;
  final bool isMe;

  static const double _avatarSize = 16;
  static const double _borderWidth = 1.5;
  static const double _borderedSize = _avatarSize + _borderWidth * 2;
  static const double _overlap = 4;
  static const int _maxVisible = 3;

  @override
  Widget build(BuildContext context) {
    if (receipts.isEmpty) return const SizedBox.shrink();

    final visibleCount = receipts.length.clamp(0, _maxVisible);
    final overflow = receipts.length - _maxVisible;

    return GestureDetector(
      onTap: () => showReadersSheet(context, receipts, avatarResolver),
      child: Padding(
        padding: const EdgeInsets.only(top: 2, bottom: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment:
              isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
          children: [
            SizedBox(
              width: _borderedSize +
                  (visibleCount - 1) * (_borderedSize - _overlap) +
                  (overflow > 0 ? 20 : 0),
              height: _borderedSize,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  for (var i = 0; i < visibleCount; i++)
                    Positioned(
                      left: i * (_borderedSize - _overlap),
                      child: _AvatarBorder(
                        borderWidth: _borderWidth,
                        child: UserAvatar(
                          avatarResolver: avatarResolver,
                          avatarUrl: receipts[i].user.avatarUrl,
                          userId: receipts[i].user.userId,
                          displayname: receipts[i].user.displayname,
                          size: _avatarSize,
                        ),
                      ),
                    ),
                  if (overflow > 0)
                    Positioned(
                      left: visibleCount * (_borderedSize - _overlap),
                      top: 0,
                      child: SizedBox(
                        height: _borderedSize,
                        child: Center(
                          child: Text(
                            '+$overflow',
                            style: TextStyle(
                              fontSize: 10,
                              color: Theme.of(context).colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Adds a thin background-colored border around each avatar to create
/// the overlapping "chip" effect.
class _AvatarBorder extends StatelessWidget {
  const _AvatarBorder({required this.borderWidth, required this.child});

  final double borderWidth;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: Theme.of(context).scaffoldBackgroundColor,
          width: borderWidth,
        ),
      ),
      child: child,
    );
  }
}

// ── Readers bottom sheet ─────────────────────────────────────

/// Shows a modal bottom sheet listing all users who have read a message.
void showReadersSheet(
  BuildContext context,
  List<KoheraReadReceipt> receipts,
  AvatarResolver avatarResolver,
) {
  unawaited(showModalBottomSheet(
    context: context,
    builder: (context) {
      final localizations = MaterialLocalizations.of(context);
      return SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Text(
                'Read by ${receipts.length}',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            const Divider(height: 1),
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: receipts.length,
                itemBuilder: (context, i) {
                  final receipt = receipts[i];
                  final name = receipt.user.displayname;
                  final timeOfDay =
                      TimeOfDay.fromDateTime(receipt.time.toLocal());
                  final timeStr =
                      localizations.formatTimeOfDay(timeOfDay);

                  return ListTile(
                    leading: UserAvatar(
                      avatarResolver: avatarResolver,
                      avatarUrl: receipt.user.avatarUrl,
                      userId: receipt.user.userId,
                      displayname: receipt.user.displayname,
                      size: 36,
                    ),
                    title: Text(name),
                    trailing: Text(
                      timeStr,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      );
    },
  ),);
}

import 'package:kohera/core/services/matrix_service.dart';
import 'package:kohera/features/chat/services/thread_roots_service.dart';
import 'package:matrix/matrix.dart';

/// Loads thread root + reply events, storing SDK [Event] objects internally.
///
/// Screens use this to avoid referencing `Event` in their own state fields.
/// All getters return inferred types so callers can use them without
/// importing `package:matrix/matrix.dart`.
class ThreadReplyLoader {
  ThreadReplyLoader();

  List<Event> _threadReplies = const [];
  Event? _threadRootEvent;
  String? _repliesNextBatch;

  /// The thread root event (inferred `Event?` — callers can pass to
  /// `ComposeStateController.setThreadRoot` without importing matrix).
  Event? get rootEvent => _threadRootEvent;

  /// Root event + all replies, for `MessageTimelineController.updateExtraEvents`.
  List<Event> get seedEvents {
    final root = _threadRootEvent;
    if (root == null) return _threadReplies;
    return [root, ..._threadReplies];
  }

  /// Event IDs of loaded replies (for dedup checks without holding `Event`).
  List<String> get replyIds =>
      _threadReplies.map((e) => e.eventId).toList(growable: false);

  /// Whether more replies can be loaded.
  bool get hasMore => _repliesNextBatch != null;

  /// Loads the thread root event and first page of replies.
  ///
  /// Returns `true` if the root event was found.
  Future<bool> loadRoot(
    MatrixService matrix,
    String roomId,
    String threadRootEventId,
  ) async {
    final room = matrix.client.getRoomById(roomId);
    if (room == null) return false;

    final root = await room.getEventById(threadRootEventId);
    final page = await fetchThreadChildrenPage(
      matrix.client,
      room,
      threadRootEventId,
    );

    _threadRootEvent = root;
    _threadReplies = page.events;
    _repliesNextBatch = page.nextBatch;
    return root != null;
  }

  /// Loads the next page of replies.
  ///
  /// Returns `true` if new replies were loaded, `false` if there are no more.
  Future<bool> loadMoreReplies(
    MatrixService matrix,
    String roomId,
    String threadRootEventId,
  ) async {
    final from = _repliesNextBatch;
    if (from == null) return false;

    final room = matrix.client.getRoomById(roomId);
    if (room == null) return false;

    final page = await fetchThreadChildrenPage(
      matrix.client,
      room,
      threadRootEventId,
      from: from,
    );

    final seen = _threadReplies.map((e) => e.eventId).toSet();
    _threadReplies = [
      ..._threadReplies,
      ...page.events.where((e) => seen.add(e.eventId)),
    ];
    _repliesNextBatch = page.nextBatch;
    return page.events.isNotEmpty;
  }

  /// Resets all loaded state (e.g. when navigating away).
  void dispose() {
    _threadReplies = const [];
    _threadRootEvent = null;
    _repliesNextBatch = null;
  }
}

import 'package:kohera/data/models/kohera_timeline_event.dart';
import 'package:kohera/data/repositories/message_repository.dart';

/// Loads thread root + reply events as domain models.
///
/// All getters return SDK-free types so callers never import
/// `package:matrix/matrix.dart`.
class ThreadReplyLoader {
  ThreadReplyLoader();

  List<KoheraTimelineEvent> _threadReplies = const [];
  KoheraTimelineEvent? _threadRootEvent;
  String? _repliesNextBatch;

  /// The thread root event.
  KoheraTimelineEvent? get rootEvent => _threadRootEvent;

  /// Root event + all replies, for
  /// `MessageTimelineController.updateExtraEvents`.
  List<KoheraTimelineEvent> get seedEvents {
    final root = _threadRootEvent;
    if (root == null) return _threadReplies;
    return [root, ..._threadReplies];
  }

  /// Event IDs of loaded replies (for dedup checks).
  List<String> get replyIds =>
      _threadReplies.map((e) => e.eventId).toList(growable: false);

  /// Whether more replies can be loaded.
  bool get hasMore => _repliesNextBatch != null;

  /// Loads the thread root event and first page of replies.
  ///
  /// Returns `true` if the root event was found.
  Future<bool> loadRoot(
    MessageRepository messages,
    String roomId,
    String threadRootEventId,
  ) async {
    final root = await messages.fetchEvent(roomId, threadRootEventId);
    final page = await messages.fetchThreadChildrenPage(
      roomId,
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
    MessageRepository messages,
    String roomId,
    String threadRootEventId,
  ) async {
    final from = _repliesNextBatch;
    if (from == null) return false;

    final page = await messages.fetchThreadChildrenPage(
      roomId,
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

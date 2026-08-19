import 'dart:async';
import 'dart:collection';

import 'package:flutter/foundation.dart';
import 'package:kohera/data/services/message_search_database.dart';
import 'package:matrix/matrix.dart';

/// Indexes decrypted message content into a local FTS5 database so
/// encrypted rooms can be searched.
///
/// **Architecture (lazy per-room indexing):**
///
/// On `init()` the service subscribes to `client.onSync` but does **no**
/// database work and **no** backfill.  Startup cost is near-zero.
///
/// When a user opens or searches an encrypted room, `ensureRoomIndexed(room)`
/// is called.  If the room hasn't been indexed yet, a background backfill
/// runs for **that room only** — fetching local events, decrypting them,
/// and inserting into the FTS5 index.  The caller does not wait; search
/// returns whatever is already indexed and shows "indexing…" while the
/// backfill continues.
///
/// Sync events are only processed for rooms that have already been
/// indexed, keeping the steady-state cost proportional to the number of
/// rooms the user actively uses.
class MessageIndexerService extends ChangeNotifier {
  MessageIndexerService({
    required Client client,
    required String clientName,
    MessageSearchDatabase? databaseOverride,
  })  : _client = client,
        _db = databaseOverride ?? MessageSearchDatabase(clientName: clientName);

  final Client _client;
  final MessageSearchDatabase _db;

  bool _started = false;
  bool _disposed = false;

  StreamSubscription<SyncUpdate>? _syncSub;
  final Map<String, StreamSubscription<String>> _keySubs = {};

  /// Rooms that have completed backfill (in-memory cache of the
  /// `indexed_rooms` table). Populated lazily on first access.
  Set<String>? _indexedRoomsCache;

  /// Rooms currently being backfilled.
  final Set<String> _indexingRooms = {};

  /// `true` while any room backfill is in progress.  The search UI uses
  /// this to show an "indexing…" indicator.
  bool get isIndexing => _indexingRooms.isNotEmpty;

  /// Per-room indexing progress: room_id → number of events indexed so far.
  final Map<String, int> _roomIndexProgress = {};

  /// Returns progress for [roomId], or `null` if not currently indexing.
  int? indexingProgressFor(String roomId) =>
      _indexingRooms.contains(roomId) ? _roomIndexProgress[roomId] : null;

  int _indexedCount = 0;
  int get indexedCount => _indexedCount;

  final List<SyncUpdate> _syncQueue = [];
  bool _processingSync = false;
  @visibleForTesting
  bool get isProcessingSync => _processingSync;

  Future<void>? _drainFuture;

  static const maxPendingDecryptionsPerRoom = 1000;
  final Map<String, Set<String>> _pendingDecryptions = {};

  MessageSearchDatabase get database => _db;

  // ── Lifecycle ─────────────────────────────────────────────

  Future<void> init() async {
    if (_started || _disposed || !_db.isAvailable) return;
    _started = true;
    _syncSub = _client.onSync.stream.listen(_onSync);
  }

  // ── Lazy per-room indexing ────────────────────────────────

  /// Ensures [room]'s historical events are indexed.  If the room has
  /// already been indexed, this is a no-op.  If indexing is already in
  /// progress, this returns immediately without starting a duplicate.
  ///
  /// The backfill runs in the background — callers should **not** await
  /// this for search.  Instead, search the FTS5 index directly and use
  /// [isIndexing] / [indexingProgressFor] to show an "indexing…" state.
  Future<void> ensureRoomIndexed(Room room) async {
    if (_disposed || !_db.isAvailable) return;

    // Fast path: check the in-memory cache.
    final cache = _indexedRoomsCache;
    if (cache != null && cache.contains(room.id)) return;

    // Check the metadata table (and warm the cache on first call).
    if (await _db.isRoomIndexed(room.id)) {
      _indexedRoomsCache ??= {};
      _indexedRoomsCache!.add(room.id);
      return;
    }

    // Already indexing this room?
    if (_indexingRooms.contains(room.id)) return;

    // Start background backfill for this room only.
    unawaited(_backfillRoomInBackground(room));
  }

  Future<void> _backfillRoomInBackground(Room room) async {
    if (_disposed) return;
    _indexingRooms.add(room.id);
    _roomIndexProgress[room.id] = 0;
    _safeNotify();

    try {
      _subscribeToRoomKeys(room);
      var eventCount = 0;
      const chunkSize = 500;
      var offset = 0;

      while (!_disposed) {
        List<Event> events;
        try {
          events = await _client.database.getEventList(
            room,
            limit: chunkSize,
            start: offset,
          );
        } catch (e) {
          debugPrint(
            '[Kohera] search index: getEventList failed for ${room.id}: $e',
          );
          break;
        }
        if (events.isEmpty) break;

        final batch = <IndexedMessage>[];
        for (final event in events) {
          if (event.redacted) continue;
          final decrypted = await _decryptIfNeeded(event);
          if (decrypted.type == EventTypes.Encrypted) {
            _markPending(room.id, decrypted.eventId);
            continue;
          }
          final indexed = _toIndexedMessage(decrypted);
          if (indexed != null) batch.add(indexed);
        }
        if (batch.isNotEmpty) {
          await _db.upsertBatch(batch);
          eventCount += batch.length;
          _indexedCount += batch.length;
          _roomIndexProgress[room.id] = eventCount;
          _safeNotify();
        }

        // Yield to the event loop between chunks to keep the UI responsive.
        await Future<void>.delayed(Duration.zero);

        if (events.length < chunkSize) break;
        offset += chunkSize;
      }

      await _db.markRoomIndexed(room.id, eventCount);
      _indexedRoomsCache ??= {};
      _indexedRoomsCache!.add(room.id);
    } catch (e) {
      debugPrint('[Kohera] search index: backfill failed for ${room.id}: $e');
    } finally {
      _indexingRooms.remove(room.id);
      _roomIndexProgress.remove(room.id);
      _safeNotify();
    }
  }

  // ── Sync processing (gated by indexed rooms) ──────────────

  void _onSync(SyncUpdate update) {
    if (_disposed) return;
    _syncQueue.add(update);
    _drainFuture ??= _drainSyncQueue().whenComplete(() {
      _drainFuture = null;
    });
  }

  Future<void> _drainSyncQueue() async {
    if (_processingSync || _syncQueue.isEmpty || _disposed) return;
    _processingSync = true;
    try {
      while (_syncQueue.isNotEmpty && !_disposed) {
        final update = _syncQueue.removeAt(0);
        await _processSyncUpdate(update);
      }
    } finally {
      _processingSync = false;
    }
  }

  Future<void> _processSyncUpdate(SyncUpdate update) async {
    final join = update.rooms?.join;
    if (join == null || join.isEmpty) return;

    // Determine which rooms are indexed (lazy load cache on first use).
    final indexed = await _getIndexedRooms();

    for (final entry in join.entries) {
      final roomId = entry.key;

      // Only process events for rooms that have been explicitly indexed.
      // Rooms the user hasn't opened yet are skipped — their history will
      // be indexed on demand via ensureRoomIndexed.
      if (!indexed.contains(roomId)) continue;

      final room = _client.getRoomById(roomId);
      if (room == null) continue;

      final events = entry.value.timeline?.events;
      if (events == null || events.isEmpty) continue;
      await _indexEventBatch(room, events);
    }

    final leave = update.rooms?.leave;
    if (leave != null && leave.isNotEmpty) {
      for (final roomId in leave.keys) {
        _cleanupRoom(roomId);
      }
    }
  }

  Future<Set<String>> _getIndexedRooms() async {
    final cache = _indexedRoomsCache;
    if (cache != null) return cache;
    _indexedRoomsCache = await _db.indexedRoomIds();
    return _indexedRoomsCache!;
  }

  Future<void> _indexEventBatch(Room room, List<MatrixEvent> rawEvents) async {
    for (final raw in rawEvents) {
      final event = Event.fromMatrixEvent(raw, room);
      if (event.type == EventTypes.Redaction) {
        final redacts = event.redacts;
        if (redacts != null) {
          await _db.remove(redacts);
        }
        continue;
      }
      if (event.type != EventTypes.Message &&
          event.type != EventTypes.Encrypted) {
        continue;
      }
      final decrypted = await _decryptIfNeeded(event);
      if (decrypted.type == EventTypes.Encrypted) {
        _markPending(room.id, decrypted.eventId);
        continue;
      }
      final indexed = _toIndexedMessage(decrypted);
      if (indexed == null) continue;
      if (event.relationshipType == RelationshipTypes.edit) {
        await _db.remove(indexed.eventId);
      }
      await _db.upsert(indexed);
      _safeNotify();
    }
  }

  // ── Decryption helpers ────────────────────────────────────

  Future<Event> _decryptIfNeeded(Event event) async {
    if (event.type != EventTypes.Encrypted) return event;
    final encryption = _client.encryption;
    if (encryption == null) return event;
    try {
      return await encryption
          .decryptRoomEvent(event)
          .timeout(const Duration(milliseconds: 500));
    } catch (_) {
      return event;
    }
  }

  void _markPending(String roomId, String eventId) {
    final set = _pendingDecryptions.putIfAbsent(
      roomId,
      LinkedHashSet<String>.new,
    );
    if (set.length >= maxPendingDecryptionsPerRoom && !set.contains(eventId)) {
      set.remove(set.first);
    }
    set.add(eventId);
  }

  void _unmarkPending(String roomId, String eventId) {
    _pendingDecryptions[roomId]?.remove(eventId);
  }

  void _cleanupRoom(String roomId) {
    final sub = _keySubs.remove(roomId);
    if (sub != null) {
      unawaited(sub.cancel());
    }
    _pendingDecryptions.remove(roomId);
    unawaited(_db.removeRoom(roomId));
    _indexedRoomsCache?.remove(roomId);
  }

  void _subscribeToRoomKeys(Room room) {
    if (_keySubs.containsKey(room.id)) return;
    _keySubs[room.id] = room.onSessionKeyReceived.stream.listen(
      (_) => unawaited(_retryPendingForRoom(room)),
    );
  }

  Future<void> _retryPendingForRoom(Room room) async {
    final pending = _pendingDecryptions[room.id];
    if (pending == null || pending.isEmpty || _disposed) return;
    final eventIds = pending.toList(growable: false);
    final indexed = <IndexedMessage>[];
    for (final eventId in eventIds) {
      Event? event;
      try {
        event = await _client.database.getEventById(eventId, room);
      } catch (e) {
        debugPrint('[Kohera] search index: retry fetch $eventId failed: $e');
      }
      if (event == null) {
        _unmarkPending(room.id, eventId);
        continue;
      }
      final decrypted = await _decryptIfNeeded(event);
      if (decrypted.type == EventTypes.Encrypted) continue;
      final message = _toIndexedMessage(decrypted);
      if (message != null) {
        indexed.add(message);
      }
      _unmarkPending(room.id, eventId);
    }
    if (indexed.isNotEmpty) {
      await _db.upsertBatch(indexed);
      _safeNotify();
    }
  }

  IndexedMessage? _toIndexedMessage(Event event) {
    if (event.redacted) return null;
    if (event.type != EventTypes.Message) return null;
    final isEdit = event.relationshipType == RelationshipTypes.edit;
    final body = isEdit ? _editBody(event) : event.body;
    if (body == null || body.isEmpty) return null;
    final eventId = isEdit
        ? (event.relationshipEventId ?? event.eventId)
        : event.eventId;
    final msgtype = isEdit ? _editMsgtype(event) : event.messageType;
    return IndexedMessage(
      eventId: eventId,
      roomId: event.roomId!,
      senderId: event.senderId,
      body: body,
      msgtype: msgtype,
      originServerTs: event.originServerTs,
    );
  }

  String? _editBody(Event event) {
    final newContent = event.content
        .tryGet<Map<String, Object?>>('m.new_content');
    if (newContent == null) return null;
    return newContent.tryGet<String>('body');
  }

  String _editMsgtype(Event event) {
    final newContent = event.content
        .tryGet<Map<String, Object?>>('m.new_content');
    return newContent?.tryGet<String>('msgtype') ?? event.messageType;
  }

  void _safeNotify() {
    if (_disposed) return;
    notifyListeners();
  }

  // ── Test helpers ─────────────────────────────────────────

  @visibleForTesting
  Future<void> waitForIdle() async {
    for (var i = 0; i < 10; i++) {
      await Future<void>.delayed(Duration.zero);
    }
    await _drainFuture?.catchError((_) {});
    while (_indexingRooms.isNotEmpty) {
      await Future<void>.delayed(Duration.zero);
    }
  }

  @visibleForTesting
  Future<void> processSyncForTest(SyncUpdate update) =>
      _processSyncUpdate(update);

  @visibleForTesting
  Future<void> backfillRoomForTest(Room room) => _backfillRoomInBackground(room);

  @override
  void dispose() {
    _disposed = true;
    unawaited(_syncSub?.cancel());
    for (final sub in _keySubs.values) {
      unawaited(sub.cancel());
    }
    _keySubs.clear();
    unawaited(
      _drainFuture?.catchError((_) {}).then((_) async => _db.close()),
    );
    super.dispose();
  }
}

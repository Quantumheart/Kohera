import 'dart:async';
import 'dart:collection';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:kohera/features/chat/services/message_search_database.dart';
import 'package:matrix/matrix.dart';

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
  bool _isBackfilling = false;
  bool get isBackfilling => _isBackfilling;

  int _indexedCount = 0;
  int get indexedCount => _indexedCount;

  StreamSubscription<SyncUpdate>? _syncSub;
  final Map<String, StreamSubscription<String>> _keySubs = {};
  final List<SyncUpdate> _syncQueue = [];
  bool _processingSync = false;
  @visibleForTesting
  bool get isProcessingSync => _processingSync;

  @visibleForTesting
  Future<void> waitForIdle() async {
    for (var i = 0; i < 5; i++) {
      await Future<void>.delayed(Duration.zero);
    }
    await _drainFuture?.catchError((_) {});
    while (_isBackfilling) {
      await Future<void>.delayed(Duration.zero);
    }
  }

  Future<void>? _drainFuture;

  static const maxPendingDecryptionsPerRoom = 1000;

  final Map<String, Set<String>> _pendingDecryptions = {};

  MessageSearchDatabase get database => _db;

  Future<void> init() async {
    if (_started || _disposed || !_db.isAvailable) return;
    _started = true;
    _syncSub = _client.onSync.stream.listen(_onSync);
    _hookRoomKeyStreams();
    unawaited(_maybeBackfill());
  }

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
    for (final entry in join.entries) {
      final roomId = entry.key;
      final room = _client.getRoomById(roomId);
      if (room == null) continue;
      _subscribeToRoomKeys(room);
      final events = entry.value.timeline?.events;
      if (events == null || events.isEmpty) continue;
      await _indexEventBatch(room, events);
    }
  }

  Future<void> _indexEventBatch(Room room, List<MatrixEvent> rawEvents) async {
    for (final raw in rawEvents) {
      final event = Event.fromMatrixEvent(raw, room);
      if (event.type == EventTypes.Redaction) {
        final redacts = event.redacts;
        if (redacts != null) {
          await _db.remove(redacts);
          _indexedCount = math.max(0, _indexedCount - 1);
          _safeNotify();
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
        _indexedCount = math.max(0, _indexedCount - 1);
      }
      await _db.upsert(indexed);
      _indexedCount++;
      _safeNotify();
    }
  }

  Future<void> _maybeBackfill() async {
    if (_isBackfilling || _disposed || !_db.isAvailable) return;
    try {
      final existing = await _db.countAll();
      if (existing > 0) return;
    } catch (e) {
      debugPrint('[Kohera] search index: countAll failed: $e');
      return;
    }
    await _backfill();
  }

  Future<void> _backfill() async {
    if (_isBackfilling || _disposed) return;
    _isBackfilling = true;
    _safeNotify();
    try {
      for (final room in _client.rooms) {
        if (_disposed) break;
        _subscribeToRoomKeys(room);
        await _backfillRoom(room);
      }
    } catch (e) {
      debugPrint('[Kohera] search index: backfill failed: $e');
    } finally {
      _isBackfilling = false;
      _safeNotify();
    }
  }

  Future<void> _backfillRoom(Room room) async {
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
        _indexedCount += batch.length;
        _safeNotify();
      }
      if (events.length < chunkSize) break;
      offset += chunkSize;
    }
  }

  Future<Event> _decryptIfNeeded(Event event) async {
    if (event.type != EventTypes.Encrypted) return event;
    final encryption = _client.encryption;
    if (encryption == null) return event;
    try {
      return await encryption
          .decryptRoomEvent(event)
          .timeout(const Duration(seconds: 3));
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

  void _hookRoomKeyStreams() {
    for (final room in _client.rooms) {
      _subscribeToRoomKeys(room);
    }
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
        event = await room.getEventById(eventId);
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
      _indexedCount += indexed.length;
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

  @visibleForTesting
  Future<void> runBackfillForTest() => _backfill();

  @visibleForTesting
  Future<void> processSyncForTest(SyncUpdate update) => _processSyncUpdate(update);

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

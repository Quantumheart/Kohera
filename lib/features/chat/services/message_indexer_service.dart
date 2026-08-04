import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:kohera/features/chat/services/message_search_database.dart';
import 'package:matrix/matrix.dart';

class MessageIndexerService extends ChangeNotifier {
  MessageIndexerService({
    required Client client,
    MessageSearchDatabase? databaseOverride,
  })  : _client = client,
        _dbOverride = databaseOverride;

  final Client _client;
  final MessageSearchDatabase? _dbOverride;
  MessageSearchDatabase? _db;
  StreamSubscription<SyncUpdate>? _syncSub;
  bool _isBackfilling = false;
  int _indexedCount = 0;
  bool _disposed = false;

  bool get isBackfilling => _isBackfilling;
  int get indexedCount => _indexedCount;
  MessageSearchDatabase get database => _db!;
  bool get isAvailable => _db != null;

  Future<void> init() async {
    try {
      _db = _dbOverride ??
          MessageSearchDatabase(clientName: _client.clientName);
      await _db!.ensureSchema();
      _syncSub = _client.onSync.stream.listen(_onSync);
      if (await _db!.countAll() == 0) {
        unawaited(_backfill());
      }
    } catch (e) {
      debugPrint('[Kohera] Message search index init failed: $e');
    }
  }

  void _onSync(SyncUpdate sync) {
    if (_disposed) return;
    final joins = sync.rooms?.join;
    if (joins == null) return;

    for (final entry in joins.entries) {
      final roomId = entry.key;
      final joinedRoom = entry.value;
      final events = joinedRoom.timeline?.events;
      if (events == null || events.isEmpty) continue;

      final room = _client.getRoomById(roomId);
      if (room == null) continue;

      unawaited(_processEvents(room, events));
    }
  }

  Future<void> _processEvents(Room room, List<MatrixEvent> events) async {
    final toIndex = <IndexedMessage>[];

    for (final me in events) {
      if (me.type == 'm.room.redaction') {
        final redacts = me.content.tryGet<String>('redacts');
        if (redacts != null) {
          await _db!.remove(redacts);
        }
        continue;
      }

      if (me.type != 'm.room.message' && me.type != 'm.room.encrypted') {
        continue;
      }

      final event = Event.fromMatrixEvent(me, room);

      if (event.redacted) {
        await _db!.remove(event.eventId);
        continue;
      }

      if (me.type == 'm.room.encrypted') {
        final decrypted = await _tryDecrypt(room, event);
        if (decrypted == null) continue;
        _addIfMessage(decrypted, toIndex);
      } else {
        _addIfMessage(event, toIndex);
      }
    }

    if (toIndex.isNotEmpty) {
      await _db!.upsertBatch(toIndex);
      _indexedCount += toIndex.length;
      notifyListeners();
    }
  }

  void _addIfMessage(Event event, List<IndexedMessage> toIndex) {
    final relatesTo =
        event.content.tryGet<Map<String, Object?>>('m.relates_to');
    final relType = relatesTo?.tryGet<String>('rel_type');

    if (relType == 'm.replace') {
      final newContent = event.content.tryGet<Map<String, Object?>>('m.new_content');
      final originalId = relatesTo?.tryGet<String>('event_id');
      if (originalId != null && newContent != null) {
        final body = newContent.tryGet<String>('body') ?? '';
        if (body.isNotEmpty) {
          toIndex.add(IndexedMessage(
            eventId: originalId,
            roomId: event.room.id,
            senderId: event.senderId,
            body: body,
            msgtype: newContent.tryGet<String>('msgtype'),
            originServerTs: event.originServerTs.millisecondsSinceEpoch,
          ));
        }
      }
      return;
    }

    if (relType == 'm.thread') return;

    final body = event.body;
    if (body.isEmpty) return;

    toIndex.add(IndexedMessage(
      eventId: event.eventId,
      roomId: event.room.id,
      senderId: event.senderId,
      body: body,
      msgtype: event.messageType,
      originServerTs: event.originServerTs.millisecondsSinceEpoch,
    ));
  }

  Future<Event?> _tryDecrypt(Room room, Event event) async {
    try {
      if (_client.encryption == null) return null;
      final decrypted = await _client.encryption!.decryptRoomEvent(
        event,

      );
      return decrypted.type == EventTypes.Encrypted ? null : decrypted;
    } catch (_) {
      return null;
    }
  }

  Future<void> _backfill() async {
    if (_disposed) return;
    _isBackfilling = true;
    notifyListeners();
    debugPrint('[Kohera] Search index backfill starting');

    try {
      for (final room in _client.rooms) {
        if (_disposed) return;
        await _backfillRoom(room);
      }
    } catch (e) {
      debugPrint('[Kohera] Search index backfill error: $e');
    }

    _isBackfilling = false;
    debugPrint('[Kohera] Search index backfill done: $_indexedCount events indexed');
    notifyListeners();
  }

  Future<void> _backfillRoom(Room room) async {
    final db = _client.database;

    var start = 0;
    const chunkSize = 500;

    while (true) {
      if (_disposed) return;
      final events = await db.getEventList(room, start: start, limit: chunkSize);
      if (events.isEmpty) break;

      final toIndex = <IndexedMessage>[];
      for (final event in events) {
        if (event.type != EventTypes.Message) continue;
        if (event.redacted) continue;

        final relatesTo =
            event.content.tryGet<Map<String, Object?>>('m.relates_to');
        final relType = relatesTo?.tryGet<String>('rel_type');
        if (relType == 'm.replace' || relType == 'm.thread') continue;

        final body = event.body;
        if (body.isEmpty) continue;

        toIndex.add(IndexedMessage(
          eventId: event.eventId,
          roomId: room.id,
          senderId: event.senderId,
          body: body,
          msgtype: event.messageType,
          originServerTs: event.originServerTs.millisecondsSinceEpoch,
        ));
      }

      if (toIndex.isNotEmpty) {
        await _db!.upsertBatch(toIndex);
        _indexedCount += toIndex.length;
      }

      if (events.length < chunkSize) break;
      start += chunkSize;
    }
  }

  @override
  void dispose() {
    _disposed = true;
    unawaited(_syncSub?.cancel());
    _syncSub = null;
    final db = _db;
    if (db != null) {
      unawaited(db.close());
    }
    super.dispose();
  }
}

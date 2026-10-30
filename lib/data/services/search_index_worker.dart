import 'dart:async';
import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:kohera/data/services/message_search_database.dart';

/// Runs [MessageSearchDatabase] on a dedicated worker isolate.
///
/// The FTS5 index is owned exclusively by this app — the Matrix SDK never
/// touches it — so a single worker can own the one and only connection.
/// That keeps every `sqlite3_step` off the UI isolate, which is what the
/// backfill loop in `MessageIndexerService` was blocking on.
///
/// Only primitives cross the isolate boundary: request ids, enum indices,
/// strings, ints and row maps. Nothing holds a reference to `Client`,
/// `Room` or a vodozemac handle, so nothing is unsendable.
class IsolatedSearchIndex implements SearchIndex {
  IsolatedSearchIndex({required this.clientName});

  final String clientName;

  Isolate? _isolate;
  SendPort? _tx;
  ReceivePort? _rx;
  Future<void>? _starting;
  final Map<int, Completer<Object?>> _pending = {};
  int _nextId = 0;
  bool _closed = false;

  @override
  bool get isAvailable => !kIsWeb;

  // ── Isolate lifecycle ─────────────────────────────────────

  Future<void> _ensureStarted() {
    final starting = _starting;
    if (starting != null) return starting;
    return _starting = _start();
  }

  Future<void> _start() async {
    final token = RootIsolateToken.instance;
    final rx = ReceivePort();
    _rx = rx;
    final ready = Completer<SendPort>();

    rx.listen((message) {
      if (message is SendPort) {
        if (!ready.isCompleted) ready.complete(message);
        return;
      }
      final reply = message! as List<Object?>;
      final completer = _pending.remove(reply[0]! as int);
      if (completer == null) return;
      final error = reply[2] as String?;
      if (error != null) {
        completer.completeError(SearchIndexWorkerException(error));
      } else {
        completer.complete(reply[1]);
      }
    });

    _isolate = await Isolate.spawn(
      searchIndexWorkerMain,
      SearchIndexWorkerBoot(
        replyTo: rx.sendPort,
        clientName: clientName,
        rootToken: token,
      ),
      debugName: 'kohera-search-index',
      errorsAreFatal: false,
    );

    _tx = await ready.future;
  }

  Future<Object?> _call(_Op op, [List<Object?> args = const []]) async {
    if (_closed || !isAvailable) return null;
    await _ensureStarted();
    final tx = _tx;
    if (tx == null) return null;
    final id = _nextId++;
    final completer = Completer<Object?>();
    _pending[id] = completer;
    tx.send([id, op.index, args]);
    return completer.future;
  }

  // ── FTS5 message operations ───────────────────────────────

  @override
  Future<void> upsert(IndexedMessage message) =>
      _call(_Op.upsert, [message.toRow()]);

  @override
  Future<void> upsertBatch(List<IndexedMessage> messages) {
    if (messages.isEmpty) return Future<void>.value();
    return _call(_Op.upsertBatch, [
      messages.map((m) => m.toRow()).toList(growable: false),
    ]);
  }

  @override
  Future<void> remove(String eventId) => _call(_Op.remove, [eventId]);

  @override
  Future<void> removeRoom(String roomId) => _call(_Op.removeRoom, [roomId]);

  @override
  Future<List<IndexedMessage>> search({
    required String query,
    String? roomId,
    Set<String>? roomIds,
    String? senderId,
    int? startTs,
    int? endTs,
    int limit = 50,
    int offset = 0,
    bool onlyIndexedRooms = false,
  }) async {
    final rows = await _call(_Op.search, [
      query,
      roomId,
      roomIds?.toList(growable: false),
      senderId,
      startTs,
      endTs,
      limit,
      offset,
      onlyIndexedRooms,
    ]) as List<Object?>?;
    if (rows == null) return const [];
    return rows
        .map((r) => IndexedMessage.fromRow(r! as Map<String, Object?>))
        .toList(growable: false);
  }

  @override
  Future<int> count({
    String? roomId,
    Set<String>? roomIds,
    String? query,
    String? senderId,
    int? startTs,
    int? endTs,
    bool onlyIndexedRooms = false,
  }) async {
    final result = await _call(_Op.count, [
      roomId,
      roomIds?.toList(growable: false),
      query,
      senderId,
      startTs,
      endTs,
      onlyIndexedRooms,
    ]);
    return (result as int?) ?? 0;
  }

  @override
  Future<int> countAll() async => (await _call(_Op.countAll) as int?) ?? 0;

  // ── Per-room metadata operations ──────────────────────────

  @override
  Future<bool> isRoomIndexed(String roomId) async =>
      (await _call(_Op.isRoomIndexed, [roomId]) as bool?) ?? false;

  @override
  Future<Set<String>> indexedRoomIds() async {
    final ids = await _call(_Op.indexedRoomIds) as List<Object?>?;
    if (ids == null) return {};
    return ids.cast<String>().toSet();
  }

  @override
  Future<void> markRoomIndexed(String roomId, int eventCount) =>
      _call(_Op.markRoomIndexed, [roomId, eventCount]);

  @override
  Future<void> clear() => _call(_Op.clear);

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    if (_starting == null) return;
    try {
      await _ensureStarted();
      final tx = _tx;
      if (tx != null) {
        final id = _nextId++;
        final completer = Completer<Object?>();
        _pending[id] = completer;
        tx.send([id, _Op.close.index, const <Object?>[]]);
        await completer.future.timeout(
          const Duration(seconds: 5),
          onTimeout: () => null,
        );
      }
    } catch (e) {
      debugPrint('[Kohera] search index: worker close failed: $e');
    } finally {
      for (final completer in _pending.values) {
        if (!completer.isCompleted) {
          completer.completeError(
            const SearchIndexWorkerException('search index worker closed'),
          );
        }
      }
      _pending.clear();
      _rx?.close();
      _isolate?.kill();
      _rx = null;
      _tx = null;
      _isolate = null;
    }
  }
}

/// Error raised on the calling isolate when the worker reports a failure.
///
/// Exceptions are not sendable in general, so the worker ships
/// `toString()` across the port and this type re-wraps it.
class SearchIndexWorkerException implements Exception {
  const SearchIndexWorkerException(this.message);

  final String message;

  @override
  String toString() => 'SearchIndexWorkerException: $message';
}

// ── Worker protocol ─────────────────────────────────────────

enum _Op {
  upsert,
  upsertBatch,
  remove,
  removeRoom,
  search,
  count,
  countAll,
  isRoomIndexed,
  indexedRoomIds,
  markRoomIndexed,
  clear,
  close,
}

@visibleForTesting
class SearchIndexWorkerBoot {
  const SearchIndexWorkerBoot({
    required this.replyTo,
    required this.clientName,
    required this.rootToken,
  });

  final SendPort replyTo;
  final String clientName;
  final RootIsolateToken? rootToken;
}

/// Entry point for the worker isolate. Must be a top-level function.
@visibleForTesting
Future<void> searchIndexWorkerMain(SearchIndexWorkerBoot boot) async {
  // sqflite and path_provider are platform-channel plugins. Background
  // isolates get no messenger by default, so wire one up before any
  // plugin call. Without this the first openDatabase throws.
  final token = boot.rootToken;
  if (token != null) {
    BackgroundIsolateBinaryMessenger.ensureInitialized(token);
  }

  final db = MessageSearchDatabase(clientName: boot.clientName);
  final rx = ReceivePort();
  boot.replyTo.send(rx.sendPort);

  await for (final Object? message in rx) {
    final request = message! as List<Object?>;
    final id = request[0]! as int;
    final op = _Op.values[request[1]! as int];
    final args = request[2]! as List<Object?>;

    Object? result;
    String? error;
    try {
      result = await _dispatch(db, op, args);
    } catch (e) {
      error = e.toString();
    }
    boot.replyTo.send([id, result, error]);

    if (op == _Op.close) break;
  }

  rx.close();
}

Future<Object?> _dispatch(
  MessageSearchDatabase db,
  _Op op,
  List<Object?> args,
) async {
  switch (op) {
    case _Op.upsert:
      await db.upsert(
        IndexedMessage.fromRow(args[0]! as Map<String, Object?>),
      );
      return null;
    case _Op.upsertBatch:
      final rows = args[0]! as List<Object?>;
      await db.upsertBatch(
        rows
            .map((r) => IndexedMessage.fromRow(r! as Map<String, Object?>))
            .toList(growable: false),
      );
      return null;
    case _Op.remove:
      await db.remove(args[0]! as String);
      return null;
    case _Op.removeRoom:
      await db.removeRoom(args[0]! as String);
      return null;
    case _Op.search:
      final matches = await db.search(
        query: args[0]! as String,
        roomId: args[1] as String?,
        roomIds: (args[2] as List<Object?>?)?.cast<String>().toSet(),
        senderId: args[3] as String?,
        startTs: args[4] as int?,
        endTs: args[5] as int?,
        limit: args[6]! as int,
        offset: args[7]! as int,
        onlyIndexedRooms: args[8] as bool? ?? false,
      );
      return matches.map((m) => m.toRow()).toList(growable: false);
    case _Op.count:
      return db.count(
        roomId: args[0] as String?,
        roomIds: (args[1] as List<Object?>?)?.cast<String>().toSet(),
        query: args[2] as String?,
        senderId: args[3] as String?,
        startTs: args[4] as int?,
        endTs: args[5] as int?,
        onlyIndexedRooms: args[6] as bool? ?? false,
      );
    case _Op.countAll:
      return db.countAll();
    case _Op.isRoomIndexed:
      return db.isRoomIndexed(args[0]! as String);
    case _Op.indexedRoomIds:
      final ids = await db.indexedRoomIds();
      return ids.toList(growable: false);
    case _Op.markRoomIndexed:
      await db.markRoomIndexed(args[0]! as String, args[1]! as int);
      return null;
    case _Op.clear:
      await db.clear();
      return null;
    case _Op.close:
      await db.close();
      return null;
  }
}

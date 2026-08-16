// coverage:ignore-file

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_vodozemac/flutter_vodozemac.dart' as vod;
import 'package:kohera/core/backend/dto/account_dto.dart';
import 'package:kohera/core/backend/dto/event_dto.dart';
import 'package:kohera/core/backend/dto/room_dto.dart';
import 'package:kohera/core/backend/ports/worker_handler.dart';
import 'package:kohera/core/backend/transport/protocol.dart';
import 'package:matrix/matrix.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

// ── MatrixSdkWorkerHandler ────────────────────────────────────────
//
// Runs the real matrix SDK on the worker isolate.  Mirrors the lifecycle
// proven in the spike (docs/spike-worker-isolate.md):
//   vod.init → databaseFactoryFfi → MatrixSdkDatabase.init → Client →
//   init(waitForFirstSync: false) → backgroundSync = true.
//
// Serves the rooms-list capability: accounts.list, rooms.list,
// rooms.listUpdates (pushed on client.onSync).

class MatrixSdkWorkerHandler implements WorkerHandler {
  MatrixSdkWorkerHandler({
    required this.dbPath,
    required this.clientName,
  });

  final String dbPath;
  final String clientName;

  Client? _client;
  Database? _db;
  StreamSubscription<SyncUpdate>? _syncSub;
  final Map<String, StreamSubscription<SyncUpdate>> _timelineSyncSubs = {};
  final Map<String, Timeline> _timelines = {};
  bool _initialized = false;

  // ── Lifecycle ──────────────────────────────────────────────────

  @visibleForTesting
  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;

    debugPrint('[Kohera] Worker: initializing vodozemac');
    await vod.init();

    debugPrint('[Kohera] Worker: opening database at $dbPath');
    sqfliteFfiInit();
    _db = await databaseFactoryFfi.openDatabase(dbPath);

    final database = await MatrixSdkDatabase.init(
      'kohera_$clientName',
      database: _db,
    );

    _client = Client(
      'Kohera ($clientName)',
      database: database,
      nativeImplementations: NativeImplementationsIsolate(
        compute,
        vodozemacInit: vod.init,
      ),
    );

    debugPrint('[Kohera] Worker: restoring session');
    await _client!.init(waitForFirstSync: false);

    debugPrint('[Kohera] Worker: starting background sync');
    _client!.backgroundSync = true;
  }

  // ── WorkerHandler ─────────────────────────────────────────────

  @override
  Future<BackendResult> handle(BackendCall call, EmitEvent emit) async {
    await init();

    switch (call.op) {
      case 'accounts.list':
        return BackendResult.ok({
          'accounts': [serializeAccount()],
        });

      case 'rooms.list':
        return BackendResult.ok({
          'rooms': serializeRooms(),
        });

      case 'subscribe.rooms.listUpdates':
        _subscribeRoomListUpdates(call, emit);
        return const BackendResult.ok({});

      case 'timeline.fetch':
        return _handleTimelineFetch(call);

      case 'timeline.paginate':
        return _handleTimelinePaginate(call);

      case 'subscribe.timeline.newEvents':
        _subscribeTimelineUpdates(call, emit);
        return const BackendResult.ok({});

      default:
        return BackendResult.error(
          BackendError(code: 'unknown_op', message: 'Unknown op: ${call.op}'),
        );
    }
  }

  @override
  Future<void> dispose() async {
    debugPrint('[Kohera] Worker: disposing');
    await _syncSub?.cancel();
    _syncSub = null;
    for (final sub in _timelineSyncSubs.values) {
      await sub.cancel();
    }
    _timelineSyncSubs.clear();
    _timelines.clear();
    if (_client != null) {
      _client!.backgroundSync = false;
      await _client!.dispose();
      _client = null;
    }
    await _db?.close();
    _db = null;
  }

  // ── Serialization ──────────────────────────────────────────────

  Map<String, dynamic> serializeAccount() {
    if (_client == null) return {};
    return AccountDto.fromSdk(_client!).toMap();
  }

  List<Map<String, dynamic>> serializeRooms() {
    if (_client == null) return [];
    return _client!.rooms
        .map((room) => RoomDto.fromSdk(room).toMap())
        .toList();
  }

  // ── Stream subscription ────────────────────────────────────────

  void _subscribeRoomListUpdates(BackendCall call, EmitEvent emit) {
    if (_client == null) return;
    final accountId = call.args['accountId'] as String? ?? clientName;

    unawaited(_syncSub?.cancel());
    _syncSub = _client!.onSync.stream.listen((_) {
      emit(BackendEvent(
        name: 'rooms.listUpdates',
        payload: {
          'accountId': accountId,
          'rooms': serializeRooms(),
        },
      ));
    });
  }

  // ── Timeline ───────────────────────────────────────────────────

  List<Map<String, dynamic>> _serializeTimeline(Timeline timeline, Room room) =>
      timeline.events
          .map((e) => EventDto.fromSdk(e, timeline: timeline, room: room).toMap())
          .toList();

  Future<BackendResult> _handleTimelineFetch(BackendCall call) async {
    final roomId = call.args['roomId'] as String;
    final limit = call.args['limit'] as int? ?? 50;
    final room = _client?.getRoomById(roomId);
    if (room == null) {
      return BackendResult.error(
        BackendError(code: 'room_not_found', message: 'No room $roomId'),
      );
    }

    final timeline = await room.getTimeline(limit: limit);
    _timelines[roomId] = timeline;
    return BackendResult.ok({'events': _serializeTimeline(timeline, room)});
  }

  Future<BackendResult> _handleTimelinePaginate(BackendCall call) async {
    final roomId = call.args['roomId'] as String;
    final direction = call.args['direction'] as String? ?? 'backward';
    final limit = call.args['limit'] as int? ?? 50;

    final room = _client?.getRoomById(roomId);
    final timeline = _timelines[roomId];
    if (room == null || timeline == null) {
      return BackendResult.error(
        BackendError(code: 'no_timeline', message: 'No timeline for $roomId'),
      );
    }

    if (direction == 'forward') {
      if (timeline.canRequestFuture) {
        await timeline.requestFuture(historyCount: limit);
      }
    } else {
      if (timeline.canRequestHistory) {
        await timeline.requestHistory(historyCount: limit);
      }
    }
    return BackendResult.ok({'events': _serializeTimeline(timeline, room)});
  }

  void _subscribeTimelineUpdates(BackendCall call, EmitEvent emit) {
    if (_client == null) return;
    final roomId = call.args['roomId'] as String;
    final accountId = call.args['accountId'] as String? ?? clientName;

    final existing = _timelineSyncSubs.remove(roomId);
    unawaited(existing?.cancel());
    _timelineSyncSubs[roomId] = _client!.onSync.stream.listen((_) {
      final room = _client?.getRoomById(roomId);
      final timeline = _timelines[roomId];
      if (room == null || timeline == null) return;
      emit(BackendEvent(
        name: 'timeline.newEvents',
        payload: {
          'accountId': accountId,
          'roomId': roomId,
          'events': _serializeTimeline(timeline, room),
        },
      ));
    });
  }
}

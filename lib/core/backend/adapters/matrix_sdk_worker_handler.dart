// coverage:ignore-file

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_vodozemac/flutter_vodozemac.dart' as vod;
import 'package:kohera/core/backend/dto/account_dto.dart';
import 'package:kohera/core/backend/dto/device_key_dto.dart';
import 'package:kohera/core/backend/dto/event_dto.dart';
import 'package:kohera/core/backend/dto/member_dto.dart';
import 'package:kohera/core/backend/dto/room_dto.dart';
import 'package:kohera/core/backend/dto/user_dto.dart';
import 'package:kohera/core/backend/dto/verification_dto.dart';
import 'package:kohera/core/backend/ports/worker_handler.dart';
import 'package:kohera/core/backend/transport/backend_ops.dart';
import 'package:kohera/core/backend/transport/protocol.dart';
import 'package:matrix/encryption.dart';
import 'package:matrix/matrix.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

// ── MatrixSdkWorkerHandler ────────────────────────────────────────
//
// Runs the real matrix SDK on the worker isolate.  Mirrors the lifecycle
//   vod.init → databaseFactoryFfi → MatrixSdkDatabase.init → Client →
//   init(waitForFirstSync: false) → backgroundSync = true.
//
// Serves the rooms-list, timeline, messaging, and read-state capabilities:
// accounts.list, rooms.list, rooms.listUpdates, timeline.fetch,
// timeline.paginate, timeline.newEvents, message.*, read.*.

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
  bool _syncing = false;
  StreamSubscription<KeyVerification>? _keyVerificationSub;

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
    _syncing = true;
  }

  // ── WorkerHandler ─────────────────────────────────────────────

  @override
  Future<BackendResult> handle(BackendCall call, EmitEvent emit) async {
    await init();

    switch (call.op) {
      case BackendOp.accountsList:
        return BackendResult.ok({
          'accounts': [serializeAccount()],
        });

      case BackendOp.roomsList:
        return BackendResult.ok({
          'rooms': serializeRooms(),
        });

      case BackendOp.subscribeRoomsListUpdates:
        _subscribeRoomListUpdates(call, emit);
        return const BackendResult.ok({});

      case BackendOp.timelineFetch:
        return _handleTimelineFetch(call);

      case BackendOp.timelinePaginate:
        return _handleTimelinePaginate(call);

      case BackendOp.subscribeTimelineNewEvents:
        _subscribeTimelineUpdates(call, emit);
        return const BackendResult.ok({});

      case BackendOp.roomMgmtLeave:
        return _handleRoomMgmtLeave(call);

      case BackendOp.roomMgmtJoin:
        return _handleRoomMgmtJoin(call);

      case BackendOp.roomMgmtInvite:
        return _handleRoomMgmtInvite(call);

      case BackendOp.roomMgmtKick:
        return _handleRoomMgmtKick(call);

      case BackendOp.roomMgmtBan:
        return _handleRoomMgmtBan(call);

      case BackendOp.roomMgmtUnban:
        return _handleRoomMgmtUnban(call);

      case BackendOp.roomMgmtSetName:
        return _handleRoomMgmtSetName(call);

      case BackendOp.roomMgmtSetTopic:
        return _handleRoomMgmtSetTopic(call);

      case BackendOp.roomMgmtSetAvatar:
        return _handleRoomMgmtSetAvatar(call);

      case BackendOp.roomsCreate:
        return _handleRoomsCreate(call);

      case BackendOp.roomStateGet:
        return _handleRoomStateGet(call);

      case BackendOp.roomStateSet:
        return _handleRoomStateSet(call);

      case BackendOp.roomStateCanChange:
        return _handleRoomStateCanChange(call);

      case BackendOp.roomStateGetPowerLevel:
        return _handleRoomStateGetPowerLevel(call);

      case BackendOp.membersGet:
        return _handleMembersGet(call);

      case BackendOp.membersGetUser:
        return _handleMembersGetUser(call);

      case BackendOp.membersSearch:
        return _handleMembersSearch(call);

      case BackendOp.messageSend:
        return _handleMessageSend(call);

      case BackendOp.messageSendText:
        return _handleMessageSendText(call);

      case BackendOp.messageReact:
        return _handleMessageReact(call);

      case BackendOp.messageRedact:
        return _handleMessageRedact(call);

      case BackendOp.messageReport:
        return _handleMessageReport(call);

      case BackendOp.messageSendFile:
        return _handleMessageSendFile(call);

      case BackendOp.readSetMarker:
        return _handleReadSetMarker(call);

      case BackendOp.readSetReceipt:
        return _handleReadSetReceipt(call);

      case BackendOp.readGetReceipts:
        return _handleReadGetReceipts(call);

      case BackendOp.e2eeEncryptionEnabled:
        final roomId = call.args['roomId'] as String?;
        final room = roomId == null ? null : _client?.getRoomById(roomId);
        return BackendResult.ok({'enabled': room?.encrypted ?? false});

      case BackendOp.e2eeDeviceKeys:
        return _handleDeviceKeys(call);

      case BackendOp.e2eeVerifyDevice:
        return _handleVerifyDevice(call);

      case BackendOp.e2eeStartVerification:
        return _handleStartVerification(call);

      case BackendOp.e2eeCrossSigningEnabled:
        return BackendResult.ok({
          'enabled': _client?.encryption?.crossSigning.enabled ?? false,
        });

      case BackendOp.e2eeCrossSigningIsCached:
        return _handleCrossSigningIsCached(call);

      case BackendOp.e2eeCrossSigningSelfSign:
        return _handleCrossSigningSelfSign(call);

      case BackendOp.e2eeBootstrap:
        return _handleBootstrap(call);

      case BackendOp.e2eeKeyBackupUnlock:
        return _handleKeyBackupUnlock(call);

      case BackendOp.subscribeE2eeKeyVerificationRequest:
        _subscribeKeyVerificationRequests(call, emit);
        return const BackendResult.ok({});

      case BackendOp.syncStatus:
        return BackendResult.ok({'syncing': _syncing});

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
    await _keyVerificationSub?.cancel();
    _keyVerificationSub = null;
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
        name: BackendEventName.roomsListUpdates,
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
        name: BackendEventName.timelineNewEvents,
        payload: {
          'accountId': accountId,
          'roomId': roomId,
          'events': _serializeTimeline(timeline, room),
        },
      ));
    });
  }

  // ── Room helpers ──────────────────────────────────────────────

  Room? _roomOf(BackendCall call) {
    final roomId = call.args['roomId'] as String?;
    if (roomId == null) return null;
    return _client?.getRoomById(roomId);
  }

  BackendResult _roomNotFound(String roomId) => BackendResult.error(
        BackendError(code: 'room_not_found', message: 'No room $roomId'),
      );

  BackendResult _notConnected() => const BackendResult.error(
        BackendError(code: 'not_connected', message: 'Client not initialized'),
      );

  // ── Room management ───────────────────────────────────────────

  Future<BackendResult> _handleRoomMgmtLeave(BackendCall call) async {
    final roomId = call.args['roomId'] as String;
    final room = _roomOf(call);
    if (room == null) return _roomNotFound(roomId);
    await room.leave();
    return const BackendResult.ok({});
  }

  Future<BackendResult> _handleRoomMgmtJoin(BackendCall call) async {
    final roomId = call.args['roomId'] as String;
    final client = _client;
    if (client == null) return _notConnected();
    await client.joinRoomById(roomId);
    return const BackendResult.ok({});
  }

  Future<BackendResult> _handleRoomMgmtInvite(BackendCall call) async {
    final roomId = call.args['roomId'] as String;
    final userId = call.args['userId'] as String;
    final reason = call.args['reason'] as String?;
    final room = _roomOf(call);
    if (room == null) return _roomNotFound(roomId);
    await room.invite(userId, reason: reason);
    return const BackendResult.ok({});
  }

  Future<BackendResult> _handleRoomMgmtKick(BackendCall call) async {
    final roomId = call.args['roomId'] as String;
    final userId = call.args['userId'] as String;
    final room = _roomOf(call);
    if (room == null) return _roomNotFound(roomId);
    await room.kick(userId);
    return const BackendResult.ok({});
  }

  Future<BackendResult> _handleRoomMgmtBan(BackendCall call) async {
    final roomId = call.args['roomId'] as String;
    final userId = call.args['userId'] as String;
    final room = _roomOf(call);
    if (room == null) return _roomNotFound(roomId);
    await room.ban(userId);
    return const BackendResult.ok({});
  }

  Future<BackendResult> _handleRoomMgmtUnban(BackendCall call) async {
    final roomId = call.args['roomId'] as String;
    final userId = call.args['userId'] as String;
    final room = _roomOf(call);
    if (room == null) return _roomNotFound(roomId);
    await room.unban(userId);
    return const BackendResult.ok({});
  }

  Future<BackendResult> _handleRoomMgmtSetName(BackendCall call) async {
    final roomId = call.args['roomId'] as String;
    final name = call.args['name'] as String;
    final room = _roomOf(call);
    if (room == null) return _roomNotFound(roomId);
    final eventId = await room.setName(name);
    return BackendResult.ok({'eventId': eventId});
  }

  Future<BackendResult> _handleRoomMgmtSetTopic(BackendCall call) async {
    final roomId = call.args['roomId'] as String;
    final topic = call.args['topic'] as String;
    final room = _roomOf(call);
    if (room == null) return _roomNotFound(roomId);
    final eventId = await room.setDescription(topic);
    return BackendResult.ok({'eventId': eventId});
  }

  Future<BackendResult> _handleRoomMgmtSetAvatar(BackendCall call) async {
    final roomId = call.args['roomId'] as String;
    final bytes = call.args['bytes'] as Uint8List?;
    final name = call.args['name'] as String?;
    final mimeType = call.args['mimeType'] as String?;
    final room = _roomOf(call);
    if (room == null) return _roomNotFound(roomId);
    final file = bytes == null
        ? null
        : MatrixFile(bytes: bytes, name: name ?? 'avatar', mimeType: mimeType);
    final eventId = await room.setAvatar(file);
    return BackendResult.ok({'eventId': eventId});
  }

  Future<BackendResult> _handleRoomsCreate(BackendCall call) async {
    final options = call.args['options'] as Map<String, dynamic>;
    final client = _client;
    if (client == null) return _notConnected();
    final roomId = await client.createRoom(
      name: options['name'] as String?,
      topic: options['topic'] as String?,
      roomAliasName: options['roomAliasName'] as String?,
      roomVersion: options['roomVersion'] as String?,
      isDirect: options['isDirect'] as bool?,
      invite: (options['invite'] as List?)?.cast<String>(),
      creationContent: options['creationContent'] as Map<String, Object?>?,
      powerLevelContentOverride:
          options['powerLevelContentOverride'] as Map<String, Object?>?,
      preset: _presetFromName(options['preset'] as String?),
      visibility: _visibilityFromName(options['visibility'] as String?),
    );
    return BackendResult.ok({'roomId': roomId});
  }

  CreateRoomPreset? _presetFromName(String? name) {
    switch (name) {
      case 'privateChat':
        return CreateRoomPreset.privateChat;
      case 'trustedPrivateChat':
        return CreateRoomPreset.trustedPrivateChat;
      case 'publicChat':
        return CreateRoomPreset.publicChat;
      default:
        return null;
    }
  }

  Visibility? _visibilityFromName(String? name) {
    switch (name) {
      case 'public':
        return Visibility.public;
      case 'private':
        return Visibility.private;
      default:
        return null;
    }
  }

  // ── Room state ────────────────────────────────────────────────

  Future<BackendResult> _handleRoomStateGet(BackendCall call) async {
    final roomId = call.args['roomId'] as String;
    final eventType = call.args['eventType'] as String;
    final key = call.args['key'] as String;
    final room = _roomOf(call);
    if (room == null) return _roomNotFound(roomId);
    final state = room.getState(eventType, key);
    return BackendResult.ok({'content': state?.content});
  }

  Future<BackendResult> _handleRoomStateSet(BackendCall call) async {
    final roomId = call.args['roomId'] as String;
    final eventType = call.args['eventType'] as String;
    final key = call.args['key'] as String;
    final content = call.args['content'] as Map<String, dynamic>;
    final room = _roomOf(call);
    if (room == null) return _roomNotFound(roomId);
    final eventId = await room.client.setRoomStateWithKey(
      roomId,
      eventType,
      key,
      content,
    );
    return BackendResult.ok({'eventId': eventId});
  }

  Future<BackendResult> _handleRoomStateCanChange(BackendCall call) async {
    final roomId = call.args['roomId'] as String;
    final eventType = call.args['eventType'] as String;
    final room = _roomOf(call);
    if (room == null) return _roomNotFound(roomId);
    return BackendResult.ok({'canChange': room.canChangeStateEvent(eventType)});
  }

  Future<BackendResult> _handleRoomStateGetPowerLevel(BackendCall call) async {
    final roomId = call.args['roomId'] as String;
    final userId = call.args['userId'] as String;
    final room = _roomOf(call);
    if (room == null) return _roomNotFound(roomId);
    final level = room.getPowerLevelByUserId(userId);
    return BackendResult.ok({'powerLevel': level.level});
  }

  // ── Members & users ──────────────────────────────────────────

  Future<BackendResult> _handleMembersGet(BackendCall call) async {
    final roomId = call.args['roomId'] as String;
    final client = _client;
    if (client == null) return _notConnected();
    final room = _roomOf(call);
    if (room == null) return _roomNotFound(roomId);
    final memberEvents = await client.getMembersByRoom(roomId);
    final memberDtos = (memberEvents ?? <MatrixEvent>[])
        .where((m) => m.content['membership'] == 'join')
        .map((m) => Event.fromMatrixEvent(m, room).asUser)
        .map((user) => MemberDto.fromSdk(
              user,
              room.getPowerLevelByUserId(user.id).level,
            ).toMap())
        .toList();
    return BackendResult.ok({'members': memberDtos});
  }

  Future<BackendResult> _handleMembersGetUser(BackendCall call) async {
    final roomId = call.args['roomId'] as String;
    final userId = call.args['userId'] as String;
    final room = _roomOf(call);
    if (room == null) return _roomNotFound(roomId);
    final user = await room.requestUser(userId);
    final dto = user != null
        ? UserDto.fromSdk(user)
        : UserDto(userId: userId, displayName: userId);
    return BackendResult.ok({'user': dto.toMap()});
  }

  Future<BackendResult> _handleMembersSearch(BackendCall call) async {
    final term = call.args['term'] as String;
    final client = _client;
    if (client == null) return _notConnected();
    final response = await client.searchUserDirectory(term);
    final userDtos =
        response.results.map((p) => UserDto.fromProfile(p).toMap()).toList();
    return BackendResult.ok({'users': userDtos});
  }

  // ── Messaging ─────────────────────────────────────────────────

  Future<BackendResult> _handleMessageSend(BackendCall call) async {
    final roomId = call.args['roomId'] as String;
    final content = call.args['content'] as Map<String, dynamic>;
    final room = _roomOf(call);
    if (room == null) return _roomNotFound(roomId);
    final eventId = await room.sendEvent(content);
    return BackendResult.ok({'eventId': eventId});
  }

  Future<BackendResult> _handleMessageSendText(BackendCall call) async {
    final roomId = call.args['roomId'] as String;
    final text = call.args['text'] as String;
    final room = _roomOf(call);
    if (room == null) return _roomNotFound(roomId);
    final eventId = await room.sendTextEvent(text);
    return BackendResult.ok({'eventId': eventId});
  }

  Future<BackendResult> _handleMessageReact(BackendCall call) async {
    final roomId = call.args['roomId'] as String;
    final targetEventId = call.args['eventId'] as String;
    final key = call.args['key'] as String? ?? call.args['emoji'] as String?;
    if (key == null) {
      return const BackendResult.error(
        BackendError(code: 'missing_key', message: 'reaction key required'),
      );
    }
    final room = _roomOf(call);
    if (room == null) return _roomNotFound(roomId);
    final eventId = await room.sendReaction(targetEventId, key);
    return BackendResult.ok({'eventId': eventId});
  }

  Future<BackendResult> _handleMessageRedact(BackendCall call) async {
    final roomId = call.args['roomId'] as String;
    final targetEventId = call.args['eventId'] as String;
    final reason = call.args['reason'] as String?;
    final room = _roomOf(call);
    if (room == null) return _roomNotFound(roomId);
    final eventId = await room.redactEvent(targetEventId, reason: reason);
    return BackendResult.ok({'eventId': eventId});
  }

  Future<BackendResult> _handleMessageReport(BackendCall call) async {
    final roomId = call.args['roomId'] as String;
    final targetEventId = call.args['eventId'] as String;
    final reason = call.args['reason'] as String?;
    // score is accepted for contract parity; SDK 9.0.0 has no score param.
    final room = _roomOf(call);
    if (room == null) return _roomNotFound(roomId);
    await room.client.reportEvent(roomId, targetEventId, reason: reason);
    return const BackendResult.ok({});
  }

  Future<BackendResult> _handleMessageSendFile(BackendCall call) async {
    final roomId = call.args['roomId'] as String;
    final bytes = call.args['bytes'] as Uint8List;
    final name = call.args['name'] as String;
    final mimeType = call.args['mimeType'] as String?;
    final room = _roomOf(call);
    if (room == null) return _roomNotFound(roomId);
    final file = MatrixFile(bytes: bytes, name: name, mimeType: mimeType);
    final eventId = await room.sendFileEvent(file);
    return BackendResult.ok({'eventId': eventId});
  }

  // ── Read state ─────────────────────────────────────────────────

  Future<BackendResult> _handleReadSetMarker(BackendCall call) async {
    final roomId = call.args['roomId'] as String;
    final eventId = call.args['eventId'] as String;
    final room = _roomOf(call);
    if (room == null) return _roomNotFound(roomId);
    await room.setReadMarker(eventId);
    return const BackendResult.ok({});
  }

  Future<BackendResult> _handleReadSetReceipt(BackendCall call) async {
    final roomId = call.args['roomId'] as String;
    final eventId = call.args['eventId'] as String;
    final room = _roomOf(call);
    if (room == null) return _roomNotFound(roomId);
    // Set a public read receipt at [eventId] without moving the fully-read
    // marker (mFullyRead: null). setReadMarker is the non-deprecated path.
    await room.setReadMarker(null, mRead: eventId, public: true);
    return const BackendResult.ok({});
  }

  Future<BackendResult> _handleReadGetReceipts(BackendCall call) async {
    final roomId = call.args['roomId'] as String;
    final room = _roomOf(call);
    if (room == null) return _roomNotFound(roomId);
    return BackendResult.ok({'receipts': room.receiptState.toJson()});
  }

  // ── E2EE ─────────────────────────────────────────────────────

  Future<BackendResult> _handleDeviceKeys(BackendCall call) async {
    final userId = call.args['userId'] as String;
    final client = _client;
    if (client == null) return _notConnected();
    await client.updateUserDeviceKeys();
    final devices = client.userDeviceKeys[userId]?.deviceKeys.values.toList() ??
        const <DeviceKeys>[];
    return BackendResult.ok({
      'devices': devices.map((dk) => DeviceKeyDto.fromSdk(dk).toMap()).toList(),
    });
  }

  Future<BackendResult> _handleVerifyDevice(BackendCall call) async {
    final userId = call.args['userId'] as String;
    final deviceId = call.args['deviceId'] as String;
    final client = _client;
    if (client == null) return _notConnected();
    final deviceKeys = client.userDeviceKeys[userId]?.deviceKeys[deviceId];
    if (deviceKeys == null) {
      return const BackendResult.error(
        BackendError(code: 'device_not_found', message: 'Device not found'),
      );
    }
    await deviceKeys.setVerified(true);
    return const BackendResult.ok({});
  }

  Future<BackendResult> _handleStartVerification(BackendCall call) async {
    final userId = call.args['userId'] as String;
    final deviceId = call.args['deviceId'] as String?;
    final client = _client;
    final encryption = client?.encryption;
    if (client == null || encryption == null) return _notConnected();

    final verification = KeyVerification(
      encryption: encryption,
      userId: userId,
      deviceId: deviceId ?? '*',
    );
    await verification.start();
    encryption.keyVerificationManager.addRequest(verification);
    return BackendResult.ok({
      'verification': VerificationDto.fromSdk(verification).toMap(),
    });
  }

  Future<BackendResult> _handleCrossSigningIsCached(BackendCall call) async {
    final encryption = _client?.encryption;
    if (encryption == null) return _notConnected();
    return BackendResult.ok({
      'isCached': await encryption.crossSigning.isCached(),
    });
  }

  Future<BackendResult> _handleCrossSigningSelfSign(BackendCall call) async {
    final recoveryKey = call.args['recoveryKey'] as String?;
    final encryption = _client?.encryption;
    if (encryption == null) return _notConnected();
    await encryption.crossSigning.selfSign(recoveryKey: recoveryKey);
    return const BackendResult.ok({});
  }

  Future<BackendResult> _handleBootstrap(BackendCall call) async {
    final encryption = _client?.encryption;
    if (encryption == null) return _notConnected();
    // Coarse trigger: kicks off the SDK's interactive bootstrap state
    // machine (askNewSsss/askSetupCrossSigning/etc.). Driving the individual
    // states remains a client-side UI concern (Phase 2 widget migration).
    encryption.bootstrap();
    return const BackendResult.ok({});
  }

  Future<BackendResult> _handleKeyBackupUnlock(BackendCall call) async {
    final recoveryKey = call.args['recoveryKey'] as String;
    final client = _client;
    if (client == null) return _notConnected();
    try {
      await client.restoreCryptoIdentity(recoveryKey);
      return const BackendResult.ok({'unlocked': true});
    } catch (e) {
      debugPrint('[Kohera] Worker: keyBackup.unlock failed: $e');
      return const BackendResult.ok({'unlocked': false});
    }
  }

  void _subscribeKeyVerificationRequests(BackendCall call, EmitEvent emit) {
    final client = _client;
    if (client == null) return;
    final accountId = call.args['accountId'] as String? ?? clientName;

    unawaited(_keyVerificationSub?.cancel());
    _keyVerificationSub =
        client.onKeyVerificationRequest.stream.listen((verification) {
      emit(BackendEvent(
        name: BackendEventName.e2eeKeyVerificationRequest,
        payload: {
          'accountId': accountId,
          'verification': VerificationDto.fromSdk(verification).toMap(),
        },
      ));
    });
  }
}

// coverage:ignore-file

import 'dart:async';
import 'dart:isolate';

import 'package:flutter/services.dart';
import 'package:kohera/core/backend/adapters/matrix_sdk_worker_handler.dart';
import 'package:kohera/core/backend/dto/account_dto.dart';
import 'package:kohera/core/backend/dto/device_key_dto.dart';
import 'package:kohera/core/backend/dto/event_dto.dart';
import 'package:kohera/core/backend/dto/member_dto.dart';
import 'package:kohera/core/backend/dto/room_dto.dart';
import 'package:kohera/core/backend/dto/user_dto.dart';
import 'package:kohera/core/backend/dto/verification_dto.dart';
import 'package:kohera/core/backend/ports/matrix_backend.dart';
import 'package:kohera/core/backend/ports/worker_handler.dart';
import 'package:kohera/core/backend/transport/backend_ops.dart';
import 'package:kohera/core/backend/transport/protocol.dart';
import 'package:kohera/core/backend/transport/worker_entry.dart';

// ── WorkerBackend ─────────────────────────────────────────────────
//
// The UI-side adapter that implements [MatrixBackend] by talking to a
// long-lived worker isolate over SendPort/ReceivePort.  The worker runs a
// [WorkerHandler] (stub in this issue, real SDK in issue #3).
//
// Lifecycle:
//   connect()  → spawn worker, handshake (receive worker's SendPort), ready.
//   _call(op)  → register a Completer, send BackendCall, await the Completer.
//   disconnect() → kill isolate, reject pending, close streams.

class WorkerBackend implements MatrixBackend {
  WorkerBackend({required WorkerHandler Function() handlerFactory})
      : _handlerFactory = handlerFactory;

  /// Production factory: hosts the real matrix SDK on the worker isolate.
  factory WorkerBackend.hostSdk({
    required String dbPath,
    required String clientName,
  }) =>
      WorkerBackend(
        handlerFactory: () => MatrixSdkWorkerHandler(
          dbPath: dbPath,
          clientName: clientName,
        ),
      );

  final WorkerHandler Function() _handlerFactory;

  Isolate? _isolate;
  ReceivePort? _uiReceivePort;
  SendPort? _workerSendPort;
  bool _ready = false;

  final _pending = PendingCalls();
  final _roomListControllers = <String, StreamController<List<RoomDto>>>{};
  final _timelineControllers = <String, StreamController<List<EventDto>>>{};
  final _loginStateController = StreamController<String>.broadcast();
  final _errorController = StreamController<BackendError>.broadcast();
  final _keyVerificationControllers =
      <String, StreamController<VerificationDto>>{};

  // ── Lifecycle ──────────────────────────────────────────────────

  @override
  bool get isReady => _ready;

  @override
  Future<void> connect() async {
    _uiReceivePort = ReceivePort();

    _isolate = await Isolate.spawn(
      workerEntry,
      WorkerBoot(
        uiPort: _uiReceivePort!.sendPort,
        token: RootIsolateToken.instance,
        handlerFactory: _handlerFactory,
      ),
    );

    // Wait for the worker's SendPort (first message on the port).
    final handshake = Completer<void>();
    var firstMessage = true;

    _uiReceivePort!.listen((message) {
      if (firstMessage) {
        firstMessage = false;
        if (message is SendPort) {
          _workerSendPort = message;
          handshake.complete();
        }
        return;
      }
      _handleMessage(message);
    });

    await handshake.future;
    _ready = true;
  }

  @override
  Future<void> disconnect() async {
    _ready = false;
    _workerSendPort?.send(null); // signal worker to shut down
    _isolate?.kill(priority: Isolate.immediate);
    _isolate = null;
    _workerSendPort = null;
    _uiReceivePort?.close();
    _uiReceivePort = null;
    _pending.rejectAll('disconnected');
    for (final controller in _roomListControllers.values) {
      await controller.close();
    }
    _roomListControllers.clear();
    for (final controller in _timelineControllers.values) {
      await controller.close();
    }
    _timelineControllers.clear();
    for (final controller in _keyVerificationControllers.values) {
      await controller.close();
    }
    _keyVerificationControllers.clear();
    await _loginStateController.close();
    await _errorController.close();
  }

  // ── Message handling ───────────────────────────────────────────

  void _handleMessage(dynamic message) {
    if (message is! Map<String, dynamic>) return;
    final decoded = decodeMessage(message);
    if (decoded is BackendReply) {
      _pending.resolve(decoded);
    } else if (decoded is BackendEvent) {
      _handleEvent(decoded);
    }
  }

  void _handleEvent(BackendEvent event) {
    switch (event.name) {
      case BackendEventName.roomsListUpdates:
        final accountId = event.payload['accountId'] as String?;
        if (accountId == null) return;
        final rooms = (event.payload['rooms'] as List?)
                ?.map((r) => RoomDto.fromMap(r as Map<String, dynamic>))
                .toList() ??
            const <RoomDto>[];
        _roomListControllers[accountId]?.add(rooms);
      case BackendEventName.timelineNewEvents:
        final accountId = event.payload['accountId'] as String?;
        final roomId = event.payload['roomId'] as String?;
        if (accountId == null || roomId == null) return;
        _timelineControllers[_timelineKey(accountId, roomId)]
            ?.add(_decodeEvents(event.payload));
      case BackendEventName.accountsLoginStateChanged:
        _loginStateController.add(event.payload['accountId'] as String);
      case BackendEventName.e2eeKeyVerificationRequest:
        final accountId = event.payload['accountId'] as String?;
        final verification = event.payload['verification'] as Map<String, dynamic>?;
        if (accountId == null || verification == null) return;
        _keyVerificationControllers[accountId]
            ?.add(VerificationDto.fromMap(verification));
      case BackendEventName.error:
        _errorController.add(BackendError.fromMap(event.payload));
      default:
        break;
    }
  }

  // ── Call helper ────────────────────────────────────────────────

  Future<Map<String, dynamic>> _call(
    String op,
    Map<String, dynamic> args,
  ) async {
    if (_workerSendPort == null || !_ready) {
      throw StateError('WorkerBackend is not connected');
    }
    final id = _pending.nextId;
    final completer = Completer<Map<String, dynamic>>();
    _pending.register(id, completer);
    _workerSendPort!.send(encodeMessage(BackendCall(id: id, op: op, args: args)));
    return completer.future;
  }

  // ── MatrixBackend ops ──────────────────────────────────────────

  @override
  Future<List<AccountDto>> accountsList() async {
    final result = await _call(BackendOp.accountsList, {});
    final accounts = (result['accounts'] as List?)
            ?.map((a) => AccountDto.fromMap(a as Map<String, dynamic>))
            .toList() ??
        const <AccountDto>[];
    return accounts;
  }

  @override
  Future<bool> login({
    required String homeserver,
    required String username,
    required String password,
  }) async {
    final result = await _call(BackendOp.accountsLogin, {
      'homeserver': homeserver,
      'username': username,
      'password': password,
    });
    return result['ok'] as bool? ?? false;
  }

  @override
  Future<bool> completeSsoLogin({
    required String homeserver,
    required String loginToken,
  }) async {
    final result = await _call(BackendOp.accountsSso, {
      'homeserver': homeserver,
      'loginToken': loginToken,
    });
    return result['ok'] as bool? ?? false;
  }

  @override
  Future<bool> register({
    required String homeserver,
    required String username,
    required String password,
  }) async {
    final result = await _call(BackendOp.accountsRegister, {
      'homeserver': homeserver,
      'username': username,
      'password': password,
    });
    return result['ok'] as bool? ?? false;
  }

  @override
  Future<void> logout() async {
    await _call(BackendOp.accountsLogout, {});
  }

  @override
  Future<bool> restore({
    required String homeserver,
    required String accessToken,
    required String userId,
    required String deviceId,
    String? refreshToken,
  }) async {
    final result = await _call(BackendOp.accountsRestore, {
      'homeserver': homeserver,
      'accessToken': accessToken,
      'userId': userId,
      'deviceId': deviceId,
      'refreshToken': ?refreshToken,
    });
    return result['ok'] as bool? ?? false;
  }

  @override
  Future<List<RoomDto>> roomsList(String accountId) async {
    final result = await _call(BackendOp.roomsList, {'accountId': accountId});
    final rooms = (result['rooms'] as List?)
            ?.map((r) => RoomDto.fromMap(r as Map<String, dynamic>))
            .toList() ??
        const <RoomDto>[];
    return rooms;
  }

  @override
  Stream<List<RoomDto>> roomListUpdates(String accountId) {
    return (_roomListControllers[accountId] ??=
            StreamController<List<RoomDto>>.broadcast())
        .stream;
  }

  // ── Timeline ───────────────────────────────────────────────────

  @override
  Future<List<EventDto>> fetchTimeline(
    String accountId,
    String roomId, {
    int limit = 50,
  }) async {
    final result = await _call(BackendOp.timelineFetch, {
      'accountId': accountId,
      'roomId': roomId,
      'limit': limit,
    });
    return _decodeEvents(result);
  }

  @override
  Future<List<EventDto>> paginateTimeline(
    String accountId,
    String roomId,
    String direction, {
    int limit = 50,
  }) async {
    final result = await _call(BackendOp.timelinePaginate, {
      'accountId': accountId,
      'roomId': roomId,
      'direction': direction,
      'limit': limit,
    });
    return _decodeEvents(result);
  }

  @override
  Stream<List<EventDto>> timelineUpdates(String accountId, String roomId) {
    final key = _timelineKey(accountId, roomId);
    final stream = (_timelineControllers[key] ??=
            StreamController<List<EventDto>>.broadcast())
        .stream;
    unawaited(
      _call(BackendOp.subscribeTimelineNewEvents, {
        'accountId': accountId,
        'roomId': roomId,
      }).catchError((Object e) => <String, dynamic>{}),
    );
    return stream;
  }

  static String _timelineKey(String accountId, String roomId) =>
      '$accountId|$roomId';

  static List<EventDto> _decodeEvents(Map<String, dynamic> payload) =>
      (payload['events'] as List?)
          ?.map((e) => EventDto.fromMap(e as Map<String, dynamic>))
          .toList() ??
      const <EventDto>[];

  // ── Room management ───────────────────────────────────────────

  @override
  Future<void> leaveRoom(String accountId, String roomId) async {
    await _call(BackendOp.roomMgmtLeave, {'accountId': accountId, 'roomId': roomId});
  }

  @override
  Future<void> joinRoom(String accountId, String roomId) async {
    await _call(BackendOp.roomMgmtJoin, {'accountId': accountId, 'roomId': roomId});
  }

  @override
  Future<void> inviteUser(
    String accountId,
    String roomId,
    String userId, {
    String? reason,
  }) async {
    await _call(BackendOp.roomMgmtInvite, {
      'accountId': accountId,
      'roomId': roomId,
      'userId': userId,
      'reason': ?reason,
    });
  }

  @override
  Future<void> kickUser(String accountId, String roomId, String userId) async {
    await _call(BackendOp.roomMgmtKick, {
      'accountId': accountId,
      'roomId': roomId,
      'userId': userId,
    });
  }

  @override
  Future<void> banUser(String accountId, String roomId, String userId) async {
    await _call(BackendOp.roomMgmtBan, {
      'accountId': accountId,
      'roomId': roomId,
      'userId': userId,
    });
  }

  @override
  Future<void> unbanUser(String accountId, String roomId, String userId) async {
    await _call(BackendOp.roomMgmtUnban, {
      'accountId': accountId,
      'roomId': roomId,
      'userId': userId,
    });
  }

  @override
  Future<String> setRoomName(
    String accountId,
    String roomId,
    String name,
  ) async {
    final result = await _call(BackendOp.roomMgmtSetName, {
      'accountId': accountId,
      'roomId': roomId,
      'name': name,
    });
    return result['eventId'] as String? ?? '';
  }

  @override
  Future<String> setRoomTopic(
    String accountId,
    String roomId,
    String topic,
  ) async {
    final result = await _call(BackendOp.roomMgmtSetTopic, {
      'accountId': accountId,
      'roomId': roomId,
      'topic': topic,
    });
    return result['eventId'] as String? ?? '';
  }

  @override
  Future<String> setRoomAvatar(
    String accountId,
    String roomId,
    Uint8List bytes,
    String name, {
    String? mimeType,
  }) async {
    final result = await _call(BackendOp.roomMgmtSetAvatar, {
      'accountId': accountId,
      'roomId': roomId,
      'bytes': bytes,
      'name': name,
      'mimeType': ?mimeType,
    });
    return result['eventId'] as String? ?? '';
  }

  @override
  Future<String> createRoom(
    String accountId,
    Map<String, dynamic> options,
  ) async {
    final result = await _call(BackendOp.roomsCreate, {
      'accountId': accountId,
      'options': options,
    });
    return result['roomId'] as String? ?? '';
  }

  // ── Room state ────────────────────────────────────────────────

  @override
  Future<Map<String, dynamic>> getRoomState(
    String accountId,
    String roomId,
    String eventType,
    String key,
  ) async {
    final result = await _call(BackendOp.roomStateGet, {
      'accountId': accountId,
      'roomId': roomId,
      'eventType': eventType,
      'key': key,
    });
    return (result['content'] as Map<String, dynamic>?) ?? const {};
  }

  @override
  Future<String> setRoomState(
    String accountId,
    String roomId,
    String eventType,
    String key,
    Map<String, dynamic> content,
  ) async {
    final result = await _call(BackendOp.roomStateSet, {
      'accountId': accountId,
      'roomId': roomId,
      'eventType': eventType,
      'key': key,
      'content': content,
    });
    return result['eventId'] as String? ?? '';
  }

  @override
  Future<bool> canChangeState(
    String accountId,
    String roomId,
    String eventType,
  ) async {
    final result = await _call(BackendOp.roomStateCanChange, {
      'accountId': accountId,
      'roomId': roomId,
      'eventType': eventType,
    });
    return result['canChange'] as bool? ?? false;
  }

  @override
  Future<int> getPowerLevel(
    String accountId,
    String roomId,
    String userId,
  ) async {
    final result = await _call(BackendOp.roomStateGetPowerLevel, {
      'accountId': accountId,
      'roomId': roomId,
      'userId': userId,
    });
    return result['powerLevel'] as int? ?? 0;
  }

  // ── Members & users ──────────────────────────────────────────

  @override
  Future<List<MemberDto>> getJoinedMembers(
    String accountId,
    String roomId,
  ) async {
    final result = await _call(BackendOp.membersGet, {
      'accountId': accountId,
      'roomId': roomId,
    });
    return (result['members'] as List?)
            ?.map((m) => MemberDto.fromMap(m as Map<String, dynamic>))
            .toList() ??
        const <MemberDto>[];
  }

  @override
  Future<UserDto> getUser(
    String accountId,
    String roomId,
    String userId,
  ) async {
    final result = await _call(BackendOp.membersGetUser, {
      'accountId': accountId,
      'roomId': roomId,
      'userId': userId,
    });
    final user = result['user'] as Map<String, dynamic>?;
    if (user == null || user.isEmpty) {
      return UserDto(userId: userId, displayName: userId);
    }
    return UserDto.fromMap(user);
  }

  @override
  Future<List<UserDto>> searchUsers(String accountId, String term) async {
    final result = await _call(BackendOp.membersSearch, {
      'accountId': accountId,
      'term': term,
    });
    return (result['users'] as List?)
            ?.map((u) => UserDto.fromMap(u as Map<String, dynamic>))
            .toList() ??
        const <UserDto>[];
  }

  // ── Messaging ─────────────────────────────────────────────────

  @override
  Future<String?> sendMessage(
    String accountId,
    String roomId,
    Map<String, dynamic> content,
  ) async {
    final result = await _call(BackendOp.messageSend, {
      'accountId': accountId,
      'roomId': roomId,
      'content': content,
    });
    return result['eventId'] as String?;
  }

  @override
  Future<String?> sendText(String accountId, String roomId, String text) async {
    final result = await _call(BackendOp.messageSendText, {
      'accountId': accountId,
      'roomId': roomId,
      'text': text,
    });
    return result['eventId'] as String?;
  }

  @override
  Future<String?> sendReaction(
    String accountId,
    String roomId,
    String eventId,
    String key,
  ) async {
    final result = await _call(BackendOp.messageReact, {
      'accountId': accountId,
      'roomId': roomId,
      'eventId': eventId,
      'key': key,
    });
    return result['eventId'] as String?;
  }

  @override
  Future<String?> redactEvent(
    String accountId,
    String roomId,
    String eventId, {
    String? reason,
  }) async {
    final result = await _call(BackendOp.messageRedact, {
      'accountId': accountId,
      'roomId': roomId,
      'eventId': eventId,
      'reason': ?reason,
    });
    return result['eventId'] as String?;
  }

  @override
  Future<void> reportEvent(
    String accountId,
    String roomId,
    String eventId, {
    String? reason,
    int? score,
  }) async {
    await _call(BackendOp.messageReport, {
      'accountId': accountId,
      'roomId': roomId,
      'eventId': eventId,
      'reason': ?reason,
      'score': ?score,
    });
  }

  @override
  Future<String?> sendFile(
    String accountId,
    String roomId,
    Uint8List bytes,
    String name, {
    String? mimeType,
  }) async {
    final result = await _call(BackendOp.messageSendFile, {
      'accountId': accountId,
      'roomId': roomId,
      'bytes': bytes,
      'name': name,
      'mimeType': ?mimeType,
    });
    return result['eventId'] as String?;
  }

  // ── Read state ────────────────────────────────────────────────

  @override
  Future<void> setReadMarker(
    String accountId,
    String roomId,
    String eventId,
  ) async {
    await _call(BackendOp.readSetMarker, {
      'accountId': accountId,
      'roomId': roomId,
      'eventId': eventId,
    });
  }

  @override
  Future<void> setReadReceipt(
    String accountId,
    String roomId,
    String eventId,
  ) async {
    await _call(BackendOp.readSetReceipt, {
      'accountId': accountId,
      'roomId': roomId,
      'eventId': eventId,
    });
  }

  @override
  Future<Map<String, dynamic>> getReceipts(
    String accountId,
    String roomId,
  ) async {
    final result = await _call(BackendOp.readGetReceipts, {
      'accountId': accountId,
      'roomId': roomId,
    });
    return (result['receipts'] as Map<String, dynamic>?) ?? const {};
  }

  // ── E2EE ──────────────────────────────────────────────────────

  @override
  Future<bool> encryptionEnabled(String accountId, String roomId) async {
    final result = await _call(BackendOp.e2eeEncryptionEnabled, {
      'accountId': accountId,
      'roomId': roomId,
    });
    return result['enabled'] as bool? ?? false;
  }

  @override
  Future<List<DeviceKeyDto>> deviceKeys(String accountId, String userId) async {
    final result = await _call(BackendOp.e2eeDeviceKeys, {
      'accountId': accountId,
      'userId': userId,
    });
    return (result['devices'] as List?)
            ?.map((d) => DeviceKeyDto.fromMap(d as Map<String, dynamic>))
            .toList() ??
        const <DeviceKeyDto>[];
  }

  @override
  Future<void> verifyDevice(String accountId, String userId, String deviceId) async {
    await _call(BackendOp.e2eeVerifyDevice, {
      'accountId': accountId,
      'userId': userId,
      'deviceId': deviceId,
    });
  }

  @override
  Future<VerificationDto> startVerification(
    String accountId,
    String userId, {
    String? deviceId,
  }) async {
    final result = await _call(BackendOp.e2eeStartVerification, {
      'accountId': accountId,
      'userId': userId,
      'deviceId': ?deviceId,
    });
    final verification = result['verification'] as Map<String, dynamic>?;
    return verification == null
        ? const VerificationDto(state: 'error')
        : VerificationDto.fromMap(verification);
  }

  @override
  Future<bool> crossSigningEnabled(String accountId) async {
    final result = await _call(BackendOp.e2eeCrossSigningEnabled, {'accountId': accountId});
    return result['enabled'] as bool? ?? false;
  }

  @override
  Future<bool> crossSigningIsCached(String accountId) async {
    final result = await _call(BackendOp.e2eeCrossSigningIsCached, {'accountId': accountId});
    return result['isCached'] as bool? ?? false;
  }

  @override
  Future<void> crossSigningSelfSign(String accountId, {String? recoveryKey}) async {
    await _call(BackendOp.e2eeCrossSigningSelfSign, {
      'accountId': accountId,
      'recoveryKey': ?recoveryKey,
    });
  }

  @override
  Future<void> bootstrap(String accountId) async {
    await _call(BackendOp.e2eeBootstrap, {'accountId': accountId});
  }

  @override
  Future<bool> unlockKeyBackup(String accountId, String recoveryKey) async {
    final result = await _call(BackendOp.e2eeKeyBackupUnlock, {
      'accountId': accountId,
      'recoveryKey': recoveryKey,
    });
    return result['unlocked'] as bool? ?? false;
  }

  @override
  Stream<VerificationDto> keyVerificationRequests(String accountId) {
    final stream = (_keyVerificationControllers[accountId] ??=
            StreamController<VerificationDto>.broadcast())
        .stream;
    unawaited(
      _call(BackendOp.subscribeE2eeKeyVerificationRequest, {'accountId': accountId})
          .catchError((Object e) => <String, dynamic>{}),
    );
    return stream;
  }

  // ── Sync ──────────────────────────────────────────────────────

  @override
  Future<bool> syncStatus(String accountId) async {

    final result = await _call(BackendOp.syncStatus, {'accountId': accountId});
    return result['syncing'] as bool? ?? false;
  }

  // ── Media ─────────────────────────────────────────────────────

  @override
  Future<String> uploadMedia(
    String accountId,
    Uint8List bytes,
    String filename, {
    String? mimeType,
  }) async {
    final result = await _call(BackendOp.mediaUpload, {
      'accountId': accountId,
      'bytes': bytes,
      'filename': filename,
      'mimeType': ?mimeType,
    });
    return result['mxc'] as String? ?? '';
  }

  @override
  Future<Uint8List> downloadMedia(
    String accountId,
    String mxcUri, {
    String? roomId,
    bool getThumbnail = false,
  }) async {
    final result = await _call(BackendOp.mediaDownload, {
      'accountId': accountId,
      'mxcUri': mxcUri,
      'roomId': ?roomId,
      'getThumbnail': getThumbnail,
    });
    return result['bytes'] as Uint8List? ?? Uint8List(0);
  }

  @override
  Future<String> mxcToHttp(String accountId, String mxcUri) async {
    final result = await _call(BackendOp.mediaMxcToHttp, {
      'accountId': accountId,
      'mxcUri': mxcUri,
    });
    return result['http'] as String? ?? '';
  }

  @override
  Stream<String> get onLoginStateChanged => _loginStateController.stream;

  @override
  Stream<BackendError> get onError => _errorController.stream;
}

// coverage:ignore-file

import 'dart:async';
import 'dart:typed_data';

import 'package:kohera/core/backend/dto/account_dto.dart';
import 'package:kohera/core/backend/dto/event_dto.dart';
import 'package:kohera/core/backend/dto/member_dto.dart';
import 'package:kohera/core/backend/dto/room_dto.dart';
import 'package:kohera/core/backend/dto/user_dto.dart';
import 'package:kohera/core/backend/ports/matrix_backend.dart';
import 'package:kohera/core/backend/transport/protocol.dart';

// ── InProcessBackend (no-op fake) ────────────────────────────────
//
// A trivial MatrixBackend implementation that returns empty data.  Used as:
//   - a fake in unit/widget tests
//   - a placeholder before the real worker-backed adapter exists
//
// No isolate, no SDK — pure in-process stubs.

class InProcessBackend implements MatrixBackend {
  bool _ready = false;
  final _loginStateController = StreamController<String>.broadcast();
  final _errorController = StreamController<BackendError>.broadcast();

  @override
  Future<void> connect() async => _ready = true;

  @override
  Future<void> disconnect() async {
    _ready = false;
    await _loginStateController.close();
    await _errorController.close();
  }

  @override
  bool get isReady => _ready;

  @override
  Future<List<AccountDto>> accountsList() async => const [];

  @override
  Future<List<RoomDto>> roomsList(String accountId) async => const [];

  @override
  Stream<List<RoomDto>> roomListUpdates(String accountId) =>
      const Stream<List<RoomDto>>.empty();

  @override
  Future<List<EventDto>> fetchTimeline(
    String accountId,
    String roomId, {
    int limit = 50,
  }) async => const [];

  @override
  Future<List<EventDto>> paginateTimeline(
    String accountId,
    String roomId,
    String direction, {
    int limit = 50,
  }) async => const [];

  @override
  Stream<List<EventDto>> timelineUpdates(String accountId, String roomId) =>
      const Stream<List<EventDto>>.empty();

  // ── Room management (no-op) ─────────────────────────────────

  @override
  Future<void> leaveRoom(String accountId, String roomId) async {}

  @override
  Future<void> joinRoom(String accountId, String roomId) async {}

  @override
  Future<void> inviteUser(
    String accountId,
    String roomId,
    String userId, {
    String? reason,
  }) async {}

  @override
  Future<void> kickUser(String accountId, String roomId, String userId, {String? reason}) async {}

  @override
  Future<void> banUser(String accountId, String roomId, String userId) async {}

  @override
  Future<void> unbanUser(String accountId, String roomId, String userId) async {}

  @override
  Future<String> setRoomName(String accountId, String roomId, String name) async => '';

  @override
  Future<String> setRoomTopic(String accountId, String roomId, String topic) async => '';

  @override
  Future<String> setRoomAvatar(
    String accountId,
    String roomId,
    Uint8List bytes,
    String name, {
    String? mimeType,
  }) async => '';

  @override
  Future<String> createRoom(String accountId, Map<String, dynamic> options) async => '';

  // ── Room state (no-op) ────────────────────────────────────────

  @override
  Future<Map<String, dynamic>> getRoomState(
    String accountId,
    String roomId,
    String eventType,
    String key,
  ) async => const <String, dynamic>{};

  @override
  Future<String> setRoomState(
    String accountId,
    String roomId,
    String eventType,
    String key,
    Map<String, dynamic> content,
  ) async => '';

  @override
  Future<bool> canChangeState(String accountId, String roomId, String eventType) async => false;

  @override
  Future<int> getPowerLevel(String accountId, String roomId, String userId) async => 0;

  // ── Members & users (no-op) ──────────────────────────────────

  @override
  Future<List<MemberDto>> getJoinedMembers(String accountId, String roomId) async => const [];

  @override
  Future<UserDto> getUser(String accountId, String roomId, String userId) async {
    return UserDto(userId: userId, displayName: userId);
  }

  @override
  Future<List<UserDto>> searchUsers(String accountId, String term) async => const [];

  // ── Messaging (no-op) ─────────────────────────────────────────

  @override
  Future<String?> sendMessage(
    String accountId,
    String roomId,
    Map<String, dynamic> content,
  ) async => null;

  @override
  Future<String?> sendText(String accountId, String roomId, String text) async =>
      null;

  @override
  Future<String?> sendReaction(
    String accountId,
    String roomId,
    String eventId,
    String key,
  ) async => null;

  @override
  Future<String?> redactEvent(
    String accountId,
    String roomId,
    String eventId, {
    String? reason,
  }) async => null;

  @override
  Future<void> reportEvent(
    String accountId,
    String roomId,
    String eventId, {
    String? reason,
    int? score,
  }) async {}

  @override
  Future<String?> sendFile(
    String accountId,
    String roomId,
    Uint8List bytes,
    String name, {
    String? mimeType,
  }) async => null;

  // ── Read state (no-op) ────────────────────────────────────────

  @override
  Future<void> setReadMarker(
    String accountId,
    String roomId,
    String eventId,
  ) async {}

  @override
  Future<void> setReadReceipt(
    String accountId,
    String roomId,
    String eventId,
  ) async {}

  @override
  Future<Map<String, dynamic>> getReceipts(
    String accountId,
    String roomId,
  ) async => const <String, dynamic>{};

  @override
  Stream<String> get onLoginStateChanged => _loginStateController.stream;

  @override
  Stream<BackendError> get onError => _errorController.stream;
}

// coverage:ignore-file

import 'dart:async';

import 'package:kohera/core/backend/dto/dto.dart';
import 'package:kohera/core/backend/dto/account_dto.dart';
import 'package:kohera/core/backend/dto/event_dto.dart';
import 'package:kohera/core/backend/dto/room_dto.dart';
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

  @override
  Stream<String> get onLoginStateChanged => _loginStateController.stream;

  @override
  Stream<BackendError> get onError => _errorController.stream;
}

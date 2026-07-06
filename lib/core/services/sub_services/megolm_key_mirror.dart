import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:matrix/matrix.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart' as sqflite;

/// Inlined from `apns_push_service.dart` to avoid core→features dependency.
const _apnsMethodChannel = MethodChannel('kohera/apns');

class MegolmKeyMirror {
  MegolmKeyMirror({required this.client, required this.clientName});

  final Client client;
  final String clientName;

  final Set<String> _subscribedRooms = <String>{};
  final List<StreamSubscription<dynamic>> _subs = [];
  String? _appGroupPath;
  bool _started = false;

  String get _mirrorDbName => 'kohera_${clientName}_keys.db';
  String get _legacyDbName => 'kohera_$clientName.db';
  String get _backfillFlagKey => 'kohera_key_mirror_backfilled_$clientName';

  Future<void> start() async {
    if (_started || !Platform.isIOS) return;
    _started = true;

    _appGroupPath = await _resolveAppGroupPath();
    if (_appGroupPath == null) {
      debugPrint('[Kohera] Key mirror: no App Group path, skipping');
      return;
    }

    await _migrateLegacyDbIfNeeded();
    await _backfillIfNeeded();
    _hookExistingRooms();
    _subs.add(client.onSync.stream.listen((_) => _hookExistingRooms()));
  }

  Future<void> dispose() async {
    for (final s in _subs) {
      await s.cancel();
    }
    _subs.clear();
    _subscribedRooms.clear();
    _started = false;
  }

  Future<String?> _resolveAppGroupPath() async {
    try {
      return await _apnsMethodChannel.invokeMethod<String>('getAppGroupPath');
    } on PlatformException catch (e) {
      debugPrint('[Kohera] Key mirror: failed to read App Group path: $e');
      return null;
    }
  }

  Future<void> _migrateLegacyDbIfNeeded() async {
    final legacyPath = p.join(_appGroupPath!, _legacyDbName);
    final legacyFile = File(legacyPath);
    if (!legacyFile.existsSync()) return;

    debugPrint('[Kohera] Key mirror: migrating legacy App Group DB');
    sqflite.Database? legacy;
    try {
      legacy = await sqflite.openReadOnlyDatabase(legacyPath);
      final rows = await legacy.rawQuery(
        'SELECT k, v FROM box_inbound_group_session',
      );
      await _writeRows(rows);
    } catch (e) {
      debugPrint('[Kohera] Key mirror: legacy migration failed: $e');
    } finally {
      await legacy?.close();
    }

    for (final suffix in const ['', '-wal', '-shm', '-journal']) {
      final f = File('$legacyPath$suffix');
      if (f.existsSync()) {
        try {
          await f.delete();
        } catch (e) {
          debugPrint('[Kohera] Key mirror: failed to delete $f: $e');
        }
      }
    }
  }

  Future<void> _backfillIfNeeded() async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(_backfillFlagKey) ?? false) return;

    try {
      final sessions = await client.database.getAllInboundGroupSessions();
      final rows = sessions
          .map(
            (s) => {
              'k': s.sessionId,
              'v': jsonEncode({
                'room_id': s.roomId,
                'session_id': s.sessionId,
                'pickle': s.pickle,
                'content': s.content,
                'indexes': s.indexes,
                'allowed_at_index': s.allowedAtIndex,
                'sender_key': s.senderKey,
                'sender_claimed_keys': s.senderClaimedKeys,
              }),
            },
          )
          .toList();
      await _writeRows(rows);
      await prefs.setBool(_backfillFlagKey, true);
      debugPrint(
        '[Kohera] Key mirror: backfilled ${rows.length} sessions',
      );
    } catch (e) {
      debugPrint('[Kohera] Key mirror: backfill failed: $e');
    }
  }

  void _hookExistingRooms() {
    for (final room in client.rooms) {
      if (_subscribedRooms.add(room.id)) {
        _subs.add(
          room.onSessionKeyReceived.stream.listen(
            (sessionId) => unawaited(_mirrorSession(room.id, sessionId)),
          ),
        );
      }
    }
  }

  Future<void> _mirrorSession(String roomId, String sessionId) async {
    try {
      final session =
          await client.database.getInboundGroupSession(roomId, sessionId);
      if (session == null) return;
      await _writeRows([
        {
          'k': sessionId,
          'v': jsonEncode({
            'room_id': session.roomId,
            'session_id': session.sessionId,
            'pickle': session.pickle,
            'content': session.content,
            'indexes': session.indexes,
            'allowed_at_index': session.allowedAtIndex,
            'sender_key': session.senderKey,
            'sender_claimed_keys': session.senderClaimedKeys,
          }),
        },
      ]);
    } catch (e) {
      debugPrint('[Kohera] Key mirror: failed to mirror $sessionId: $e');
    }
  }

  Future<void> _writeRows(List<Map<String, Object?>> rows) async {
    if (rows.isEmpty) return;
    final dbPath = p.join(_appGroupPath!, _mirrorDbName);
    sqflite.Database? db;
    try {
      db = await sqflite.openDatabase(
        dbPath,
        version: 1,
        onCreate: (d, _) async {
          await d.execute(
            'CREATE TABLE IF NOT EXISTS box_inbound_group_session '
            '(k TEXT PRIMARY KEY NOT NULL, v TEXT)',
          );
        },
      );
      final batch = db.batch();
      for (final row in rows) {
        batch.insert(
          'box_inbound_group_session',
          row,
          conflictAlgorithm: sqflite.ConflictAlgorithm.replace,
        );
      }
      await batch.commit(noResult: true);
      await _checkpoint(db);
    } finally {
      await db?.close();
    }
  }

  Future<void> _checkpoint(sqflite.Database db) async {
    try {
      await db.rawQuery('PRAGMA wal_checkpoint(TRUNCATE)');
    } catch (_) {}
  }
}

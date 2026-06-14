import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:kohera/features/notifications/services/apns_push_service.dart';
import 'package:kohera/features/notifications/services/key_mirror_crypto.dart';
import 'package:matrix/matrix.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart' as sqflite;

class MegolmKeyMirror {
  MegolmKeyMirror({
    required this.client,
    required this.clientName,
    FlutterSecureStorage? storage,
  }) : _storage = storage ??
            const FlutterSecureStorage(
              iOptions: IOSOptions(
                groupId: 'group.io.github.quantumheart.kohera',
                accessibility: KeychainAccessibility.first_unlock,
              ),
            );

  final Client client;
  final String clientName;
  final FlutterSecureStorage _storage;

  final Set<String> _subscribedRooms = <String>{};
  final List<StreamSubscription<dynamic>> _subs = [];
  String? _appGroupPath;
  Uint8List? _dbKey;
  bool _started = false;

  String get _mirrorDbName => 'kohera_${clientName}_keys.db';
  String get _legacyDbName => 'kohera_$clientName.db';
  String get _backfillFlagKey => 'kohera_key_mirror_backfilled_$clientName';
  String get _encryptionFlagKey => 'kohera_key_mirror_encrypted_$clientName';
  String get _dbKeyStorageKey => 'kohera_${clientName}_key_mirror_db_key';

  Future<void> start() async {
    if (_started || !Platform.isIOS) return;
    _started = true;

    _appGroupPath = await _resolveAppGroupPath();
    if (_appGroupPath == null) {
      debugPrint('[Kohera] Key mirror: no App Group path, skipping');
      return;
    }

    _dbKey = await _loadOrCreateDbKey();
    if (_dbKey == null) {
      debugPrint('[Kohera] Key mirror: no encryption key, skipping');
      return;
    }

    await _upgradeToEncryptedFormatIfNeeded();
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
      return await apnsMethodChannel.invokeMethod<String>('getAppGroupPath');
    } on PlatformException catch (e) {
      debugPrint('[Kohera] Key mirror: failed to read App Group path: $e');
      return null;
    }
  }

  Future<Uint8List?> _loadOrCreateDbKey() async {
    try {
      final existing = await _storage.read(key: _dbKeyStorageKey);
      if (existing != null) {
        final decoded = base64Decode(existing);
        if (decoded.length == KeyMirrorCrypto.keyLength) {
          return Uint8List.fromList(decoded);
        }
        debugPrint('[Kohera] Key mirror: stored key malformed, regenerating');
      }
      final key = KeyMirrorCrypto.generateKey();
      await _storage.write(key: _dbKeyStorageKey, value: base64Encode(key));
      return key;
    } catch (e) {
      debugPrint('[Kohera] Key mirror: failed to load encryption key: $e');
      return null;
    }
  }

  Future<void> _upgradeToEncryptedFormatIfNeeded() async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(_encryptionFlagKey) ?? false) return;

    _deleteDbFiles(p.join(_appGroupPath!, _mirrorDbName));
    await prefs.setBool(_backfillFlagKey, false);
    await prefs.setBool(_encryptionFlagKey, true);
    debugPrint('[Kohera] Key mirror: reset mirror for encrypted format');
  }

  void _deleteDbFiles(String basePath) {
    for (final suffix in const ['', '-wal', '-shm', '-journal']) {
      final f = File('$basePath$suffix');
      if (f.existsSync()) {
        try {
          f.deleteSync();
        } catch (e) {
          debugPrint('[Kohera] Key mirror: failed to delete $f: $e');
        }
      }
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

    _deleteDbFiles(legacyPath);
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
          {'k': row['k'], 'v': _encryptValue(row['v']! as String)},
          conflictAlgorithm: sqflite.ConflictAlgorithm.replace,
        );
      }
      await batch.commit(noResult: true);
      await _checkpoint(db);
    } finally {
      await db?.close();
    }
  }

  String _encryptValue(String plaintext) {
    final sealed = KeyMirrorCrypto.encrypt(
      _dbKey!,
      Uint8List.fromList(utf8.encode(plaintext)),
    );
    return base64Encode(sealed);
  }

  Future<void> _checkpoint(sqflite.Database db) async {
    try {
      await db.rawQuery('PRAGMA wal_checkpoint(TRUNCATE)');
    } catch (_) {}
  }
}

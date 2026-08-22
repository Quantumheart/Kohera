import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart' as sqflite_native;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class IndexedMessage {
  const IndexedMessage({
    required this.eventId,
    required this.roomId,
    required this.senderId,
    required this.body,
    required this.msgtype,
    required this.originServerTs,
  });

  final String eventId;
  final String roomId;
  final String senderId;
  final String body;
  final String msgtype;
  final DateTime originServerTs;

  Map<String, Object?> toRow() => {
        'event_id': eventId,
        'room_id': roomId,
        'sender_id': senderId,
        'body': body,
        'msgtype': msgtype,
        'origin_server_ts': originServerTs.millisecondsSinceEpoch,
      };

  factory IndexedMessage.fromRow(Map<String, Object?> row) => IndexedMessage(
        eventId: row['event_id']! as String,
        roomId: row['room_id']! as String,
        senderId: row['sender_id']! as String,
        body: row['body']! as String,
        msgtype: row['msgtype']! as String,
        originServerTs: DateTime.fromMillisecondsSinceEpoch(
          row['origin_server_ts']! as int,
        ),
      );
}

/// Per-room metadata tracking which rooms have been indexed and when.
///
/// Replaces the expensive FTS5 COUNT scan that was run on every startup.
/// A quick primary-key lookup is O(1).
class IndexedRoom {
  const IndexedRoom({
    required this.roomId,
    required this.indexedAt,
    required this.eventCount,
  });

  final String roomId;
  final DateTime indexedAt;
  final int eventCount;

  Map<String, Object?> toRow() => {
        'room_id': roomId,
        'indexed_at': indexedAt.millisecondsSinceEpoch,
        'event_count': eventCount,
      };

  factory IndexedRoom.fromRow(Map<String, Object?> row) => IndexedRoom(
        roomId: row['room_id']! as String,
        indexedAt: DateTime.fromMillisecondsSinceEpoch(
          row['indexed_at']! as int,
        ),
        eventCount: row['event_count']! as int,
      );
}

class MessageSearchDatabase {
  MessageSearchDatabase({required this.clientName, Database? overrideDb})
      : _override = overrideDb,
        _isAvailable = overrideDb != null || !kIsWeb;

  final String clientName;
  final Database? _override;
  Database? _db;

  bool _isAvailable;
  bool get isAvailable => _isAvailable;

  Future<Database> _open() async {
    final override = _override;
    if (override != null) return override;
    final cached = _db;
    if (cached != null) return cached;
    if (kIsWeb) {
      _isAvailable = false;
      throw StateError('FTS5 search index is not available on web');
    }
    final dir = await getApplicationSupportDirectory();
    final dbPath = p.join(dir.path, 'kohera_${clientName}_search_index.db');
    if (Platform.isIOS || Platform.isAndroid) {
      _db = await sqflite_native.openDatabase(
        dbPath,
        version: 2,
        onCreate: _createSchema,
        onUpgrade: _onUpgrade,
      );
    } else {
      sqfliteFfiInit();
      _db = await databaseFactoryFfi.openDatabase(
        dbPath,
        options: OpenDatabaseOptions(
          version: 2,
          onCreate: _createSchema,
          onUpgrade: _onUpgrade,
        ),
      );
    }
    return _db!;
  }

  static Future<void> _onUpgrade(Database d, int oldVersion, int newVersion) async {
    if (oldVersion < 1) {
      await _createFts5Table(d);
    }
    if (oldVersion < 2) {
      await _createIndexedRoomsTable(d);
      // Migrate: if the FTS5 table already has data (from v1), mark all
      // existing rooms as indexed so we don't re-backfill.
      await _migrateExistingRooms(d);
    }
  }

  static Future<void> _createSchema(Database d, [int? _]) async {
    await _createFts5Table(d);
    await _createIndexedRoomsTable(d);
  }

  static Future<void> _createFts5Table(Database d) async {
    await d.execute(
      'CREATE VIRTUAL TABLE IF NOT EXISTS message_search USING fts5( '
      'event_id UNINDEXED, '
      'room_id UNINDEXED, '
      'sender_id UNINDEXED, '
      'body, '
      'msgtype UNINDEXED, '
      'origin_server_ts UNINDEXED)',
    );
  }

  static Future<void> _createIndexedRoomsTable(Database d) async {
    await d.execute(
      'CREATE TABLE IF NOT EXISTS indexed_rooms ( '
      'room_id TEXT PRIMARY KEY, '
      'indexed_at INTEGER NOT NULL, '
      'event_count INTEGER NOT NULL DEFAULT 0)',
    );
  }

  /// Migrates from v1: if the FTS5 table already has data, find all
  /// distinct room_ids and insert them into indexed_rooms so they don't
  /// get re-backfilled.
  static Future<void> _migrateExistingRooms(Database d) async {
    final rows = await d.rawQuery(
      'SELECT DISTINCT room_id FROM message_search',
    );
    if (rows.isEmpty) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    for (final row in rows) {
      final roomId = row['room_id']! as String;
      final countRow = await d.rawQuery(
        'SELECT COUNT(*) AS c FROM message_search WHERE room_id = ?',
        [roomId],
      );
      final count = (countRow.first['c'] as int?) ?? 0;
      await d.insert(
        'indexed_rooms',
        {
          'room_id': roomId,
          'indexed_at': now,
          'event_count': count,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
  }

  static String? _sanitizeFts5Query(String query) {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return null;
    final tokens = trimmed.split(RegExp(r'\s+'));
    final escaped = tokens.map((token) {
      final escapedQuotes = token.replaceAll('"', '""');
      return '"$escapedQuotes"';
    }).join(' ');
    return escaped.isEmpty ? null : escaped;
  }

  // ── FTS5 message operations ───────────────────────────────

  Future<void> upsert(IndexedMessage message) async {
    if (!_isAvailable) return;
    final db = await _open();
    await db.transaction((txn) async {
      await txn.delete(
        'message_search',
        where: 'event_id = ?',
        whereArgs: [message.eventId],
      );
      await txn.insert('message_search', message.toRow());
    });
  }

  Future<void> upsertBatch(List<IndexedMessage> messages) async {
    if (!_isAvailable || messages.isEmpty) return;
    final db = await _open();
    await db.transaction((txn) async {
      for (final message in messages) {
        await txn.delete(
          'message_search',
          where: 'event_id = ?',
          whereArgs: [message.eventId],
        );
        await txn.insert('message_search', message.toRow());
      }
    });
  }

  Future<void> remove(String eventId) async {
    if (!_isAvailable) return;
    final db = await _open();
    await db.delete(
      'message_search',
      where: 'event_id = ?',
      whereArgs: [eventId],
    );
  }

  Future<void> removeRoom(String roomId) async {
    if (!_isAvailable) return;
    final db = await _open();
    await db.transaction((txn) async {
      await txn.delete(
        'message_search',
        where: 'room_id = ?',
        whereArgs: [roomId],
      );
      await txn.delete(
        'indexed_rooms',
        where: 'room_id = ?',
        whereArgs: [roomId],
      );
    });
  }

  /// Searches the FTS5 index for [query], optionally narrowed by [roomId],
  /// [senderId], and/or a date range ([startTs]/[endTs] in milliseconds
  /// since epoch, inclusive).
  Future<List<IndexedMessage>> search({
    required String query,
    String? roomId,
    String? senderId,
    int? startTs,
    int? endTs,
    int limit = 50,
    int offset = 0,
  }) async {
    if (!_isAvailable) return const [];
    final sanitized = _sanitizeFts5Query(query);
    if (sanitized == null) return const [];
    final db = await _open();
    final whereParts = <String>['message_search MATCH ?'];
    final whereArgs = <Object?>[sanitized];
    if (roomId != null) {
      whereParts.add('room_id = ?');
      whereArgs.add(roomId);
    }
    if (senderId != null) {
      whereParts.add('sender_id = ?');
      whereArgs.add(senderId);
    }
    if (startTs != null && endTs != null) {
      whereParts.add('origin_server_ts BETWEEN ? AND ?');
      whereArgs.add(startTs);
      whereArgs.add(endTs);
    }
    final rows = await db.query(
      'message_search',
      where: whereParts.join(' AND '),
      whereArgs: whereArgs,
      orderBy: 'rank ASC',
      limit: limit,
      offset: offset,
    );
    return rows.map(IndexedMessage.fromRow).toList(growable: false);
  }

  /// Counts matches for [query], optionally narrowed by [roomId],
  /// [senderId], and/or a date range ([startTs]/[endTs] in milliseconds
  /// since epoch, inclusive).
  Future<int> count({
    String? roomId,
    String? query,
    String? senderId,
    int? startTs,
    int? endTs,
  }) async {
    if (!_isAvailable) return 0;
    final db = await _open();
    final whereParts = <String>[];
    final whereArgs = <Object?>[];
    if (query != null) {
      final sanitized = _sanitizeFts5Query(query);
      if (sanitized == null) return 0;
      whereParts.add('message_search MATCH ?');
      whereArgs.add(sanitized);
    }
    if (roomId != null) {
      whereParts.add('room_id = ?');
      whereArgs.add(roomId);
    }
    if (senderId != null) {
      whereParts.add('sender_id = ?');
      whereArgs.add(senderId);
    }
    if (startTs != null && endTs != null) {
      whereParts.add('origin_server_ts BETWEEN ? AND ?');
      whereArgs.add(startTs);
      whereArgs.add(endTs);
    }
    final rows = await db.rawQuery(
      'SELECT COUNT(*) AS c FROM message_search'
      '${whereParts.isEmpty ? '' : ' WHERE ${whereParts.join(' AND ')}'}',
      whereArgs,
    );
    return (rows.first['c'] as int?) ?? 0;
  }

  Future<int> countAll() async {
    if (!_isAvailable) return 0;
    final db = await _open();
    final rows = await db.rawQuery('SELECT COUNT(*) AS c FROM message_search');
    return (rows.first['c'] as int?) ?? 0;
  }

  // ── Per-room metadata operations ──────────────────────────

  /// Returns `true` if [roomId] has been fully indexed (backfill completed).
  /// This is a quick O(1) primary-key lookup — far cheaper than
  /// `SELECT COUNT(*) FROM message_search`.
  Future<bool> isRoomIndexed(String roomId) async {
    if (!_isAvailable) return false;
    final db = await _open();
    final rows = await db.query(
      'indexed_rooms',
      where: 'room_id = ?',
      whereArgs: [roomId],
      limit: 1,
    );
    return rows.isNotEmpty;
  }

  /// Returns the set of room_ids that have been indexed.
  Future<Set<String>> indexedRoomIds() async {
    if (!_isAvailable) return {};
    final db = await _open();
    final rows = await db.query('indexed_rooms', columns: ['room_id']);
    return rows.map((r) => r['room_id']! as String).toSet();
  }

  /// Marks [roomId] as fully indexed with [eventCount] events.
  Future<void> markRoomIndexed(String roomId, int eventCount) async {
    if (!_isAvailable) return;
    final db = await _open();
    await db.insert(
      'indexed_rooms',
      {
        'room_id': roomId,
        'indexed_at': DateTime.now().millisecondsSinceEpoch,
        'event_count': eventCount,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  // ── Legacy / maintenance operations ──────────────────────

  Future<void> clear() async {
    if (!_isAvailable) return;
    final db = await _open();
    await db.transaction((txn) async {
      await txn.delete('message_search');
      await txn.delete('indexed_rooms');
    });
  }

  @visibleForTesting
  Future<void> ensureSchema() async {
    if (!_isAvailable) return;
    final db = await _open();
    await _createSchema(db);
  }

  Future<void> close() async {
    if (_override != null) return;
    await _db?.close();
    _db = null;
  }
}

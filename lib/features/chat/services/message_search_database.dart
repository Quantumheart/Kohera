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
        version: 1,
        onCreate: (d, _) => _createSchema(d),
      );
    } else {
      sqfliteFfiInit();
      _db = await databaseFactoryFfi.openDatabase(
        dbPath,
        options: OpenDatabaseOptions(
          version: 1,
          onCreate: (d, _) => _createSchema(d),
        ),
      );
    }
    return _db!;
  }

  static Future<void> _createSchema(Database d) async {
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

  Future<void> upsert(IndexedMessage message) async {
    if (!_isAvailable) return;
    final db = await _open();
    await db.delete(
      'message_search',
      where: 'event_id = ?',
      whereArgs: [message.eventId],
    );
    await db.insert('message_search', message.toRow());
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
    await db.delete(
      'message_search',
      where: 'room_id = ?',
      whereArgs: [roomId],
    );
  }

  Future<List<IndexedMessage>> search({
    required String query,
    String? roomId,
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

  Future<int> count({String? roomId, String? query}) async {
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

  Future<void> clear() async {
    if (!_isAvailable) return;
    final db = await _open();
    await db.delete('message_search');
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

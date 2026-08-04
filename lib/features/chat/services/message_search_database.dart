import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class IndexedMessage {
  const IndexedMessage({
    required this.eventId,
    required this.roomId,
    required this.senderId,
    required this.body,
    required this.originServerTs,
    this.msgtype,
  });

  final String eventId;
  final String roomId;
  final String senderId;
  final String body;
  final String? msgtype;
  final int originServerTs;

  Map<String, Object?> toRow() => {
        'event_id': eventId,
        'room_id': roomId,
        'sender_id': senderId,
        'body': body,
        'msgtype': msgtype,
        'origin_server_ts': originServerTs,
      };

  factory IndexedMessage.fromRow(Map<String, Object?> row) => IndexedMessage(
        eventId: row['event_id']! as String,
        roomId: row['room_id']! as String,
        senderId: row['sender_id']! as String,
        body: row['body']! as String,
        msgtype: row['msgtype'] as String?,
        originServerTs: row['origin_server_ts']! as int,
      );
}

class MessageSearchDatabase {
  MessageSearchDatabase({required this.clientName, Database? overrideDb})
      : _override = overrideDb;

  final String clientName;
  final Database? _override;
  Database? _db;

  Future<Database> _open() async {
    final override = _override;
    if (override != null) return override;
    final cached = _db;
    if (cached != null) return cached;
    final dir = await getApplicationSupportDirectory();
    final dbPath = p.join(dir.path, 'kohera_${clientName}_search_index.db');
    if (Platform.isIOS || Platform.isAndroid) {
      _db = await openDatabase(
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
      'CREATE VIRTUAL TABLE IF NOT EXISTS message_search USING fts5'
      ' (event_id UNINDEXED, room_id UNINDEXED, sender_id UNINDEXED, '
      'body, msgtype UNINDEXED, origin_server_ts UNINDEXED)',
    );
  }

  Future<void> upsert(IndexedMessage message) async {
    final db = await _open();
    await db.insert(
      'message_search',
      message.toRow(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> upsertBatch(List<IndexedMessage> messages) async {
    if (messages.isEmpty) return;
    final db = await _open();
    await db.transaction((txn) async {
      for (final msg in messages) {
        await txn.insert(
          'message_search',
          msg.toRow(),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
    });
  }

  Future<void> remove(String eventId) async {
    final db = await _open();
    await db.delete(
      'message_search',
      where: 'event_id = ?',
      whereArgs: [eventId],
    );
  }

  Future<void> removeRoom(String roomId) async {
    final db = await _open();
    await db.delete(
      'message_search',
      where: 'room_id = ?',
      whereArgs: [roomId],
    );
  }

  Future<List<IndexedMessage>> search({
    required String roomId,
    required String query,
    int limit = 50,
    int offset = 0,
    String? senderFilter,
  }) async {
    final db = await _open();
    final sanitized = _sanitizeFtsQuery(query);
    if (sanitized.isEmpty) return [];

    final rows = await db.query(
      'message_search',
      where: senderFilter != null
        ? 'message_search MATCH ? AND room_id = ? AND sender_id = ?'
        : 'message_search MATCH ? AND room_id = ?',
      whereArgs: senderFilter != null ? [sanitized, roomId, senderFilter] : [sanitized, roomId],
      orderBy: 'rank',
      limit: limit,
      offset: offset,
    );
    return rows.map(IndexedMessage.fromRow).toList(growable: false);
  }

  Future<int> count({required String roomId, required String query, String? senderFilter}) async {
    final db = await _open();
    final sanitized = _sanitizeFtsQuery(query);
    if (sanitized.isEmpty) return 0;

    final rows = await db.rawQuery(
      senderFilter != null
        ? 'SELECT COUNT(*) as cnt FROM message_search WHERE message_search MATCH ? AND room_id = ? AND sender_id = ?'
        : 'SELECT COUNT(*) as cnt FROM message_search WHERE message_search MATCH ? AND room_id = ?',
      senderFilter != null ? [sanitized, roomId, senderFilter] : [sanitized, roomId],
    );
    return (rows.isNotEmpty ? rows.first['cnt'] as int? : null) ?? 0;
  }

  Future<int> countAll() async {
    final db = await _open();
    final rows = await db.rawQuery('SELECT COUNT(*) as cnt FROM message_search');
    return (rows.isNotEmpty ? rows.first['cnt'] as int? : null) ?? 0;
  }

  Future<void> clear() async {
    final db = await _open();
    await db.delete('message_search');
  }

  Future<void> close() async {
    if (_override != null) return;
    await _db?.close();
    _db = null;
  }

  Future<void> ensureSchema() async {
    final db = await _open();
    await _createSchema(db);
  }

  static String _sanitizeFtsQuery(String query) {
    final terms = query.trim().split(RegExp(r'\s+')).where((t) => t.isNotEmpty);
    return terms.map((t) {
      final escaped = t.replaceAll(RegExp(r'["*()\-]'), ' ');
      final cleaned = escaped.trim();
      return cleaned.isEmpty ? '' : '"$cleaned"';
    }).where((t) => t.isNotEmpty).join(' ');
  }
}

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart' as sqflite_native;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class OutboxAttempt {
  const OutboxAttempt({
    required this.txid,
    required this.roomId,
    required this.attempts,
    required this.nextRetryAt,
  });

  final String txid;
  final String roomId;
  final int attempts;
  final DateTime nextRetryAt;

  Map<String, Object?> toRow() => {
        'txid': txid,
        'room_id': roomId,
        'attempts': attempts,
        'next_retry_at': nextRetryAt.millisecondsSinceEpoch,
      };

  factory OutboxAttempt.fromRow(Map<String, Object?> row) => OutboxAttempt(
        txid: row['txid']! as String,
        roomId: row['room_id']! as String,
        attempts: row['attempts']! as int,
        nextRetryAt: DateTime.fromMillisecondsSinceEpoch(
          row['next_retry_at']! as int,
        ),
      );
}

class OutboxDatabase {
  OutboxDatabase({required this.clientName, Database? overrideDb})
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
    final dbPath = p.join(dir.path, 'kohera_${clientName}_outbox.db');
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
      'CREATE TABLE IF NOT EXISTS box_outbox_attempts ( '
      'txid TEXT PRIMARY KEY NOT NULL, '
      'room_id TEXT NOT NULL, '
      'attempts INTEGER NOT NULL, '
      'next_retry_at INTEGER NOT NULL)',
    );
  }

  Future<List<OutboxAttempt>> all() async {
    final db = await _open();
    final rows = await db.query('box_outbox_attempts');
    return rows.map(OutboxAttempt.fromRow).toList(growable: false);
  }

  Future<void> upsert(OutboxAttempt entry) async {
    final db = await _open();
    await db.insert(
      'box_outbox_attempts',
      entry.toRow(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> remove(String txid) async {
    final db = await _open();
    await db.delete(
      'box_outbox_attempts',
      where: 'txid = ?',
      whereArgs: [txid],
    );
  }

  Future<void> retainOnly(Set<String> txids) async {
    final db = await _open();
    if (txids.isEmpty) {
      await db.delete('box_outbox_attempts');
      return;
    }
    final placeholders = List.filled(txids.length, '?').join(',');
    await db.delete(
      'box_outbox_attempts',
      where: 'txid NOT IN ($placeholders)',
      whereArgs: txids.toList(),
    );
  }

  @visibleForTesting
  Future<void> ensureSchema() async {
    final db = await _open();
    await _createSchema(db);
  }

  Future<void> close() async {
    if (_override != null) return;
    await _db?.close();
    _db = null;
  }
}

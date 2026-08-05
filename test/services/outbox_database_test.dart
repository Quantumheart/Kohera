import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kohera/core/services/sub_services/outbox_database.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  late OutboxDatabase db;
  late Directory tempDir;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    tempDir = Directory.systemTemp.createTempSync('outbox_test_');
    final dbPath = p.join(tempDir.path, 'test_outbox.db');
    final memDb = await databaseFactoryFfi.openDatabase(
      dbPath,
      options: OpenDatabaseOptions(
        version: 1,
        onCreate: (d, _) async {
          await d.execute(
            'CREATE TABLE IF NOT EXISTS box_outbox_attempts ( '
            'txid TEXT PRIMARY KEY NOT NULL, '
            'room_id TEXT NOT NULL, '
            'attempts INTEGER NOT NULL, '
            'next_retry_at INTEGER NOT NULL)',
          );
        },
      ),
    );
    db = OutboxDatabase(clientName: 'test', overrideDb: memDb);
  });

  tearDown(() async {
    await db.close();
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  group('OutboxAttempt', () {
    test('toRow serializes correctly', () {
      final attempt = OutboxAttempt(
        txid: 'tx123',
        roomId: '!room:example.com',
        attempts: 3,
        nextRetryAt: DateTime.fromMillisecondsSinceEpoch(1000000),
      );

      final row = attempt.toRow();
      expect(row['txid'], 'tx123');
      expect(row['room_id'], '!room:example.com');
      expect(row['attempts'], 3);
      expect(row['next_retry_at'], 1000000);
    });

    test('fromRow deserializes correctly', () {
      final attempt = OutboxAttempt.fromRow({
        'txid': 'tx456',
        'room_id': '!room2:example.com',
        'attempts': 1,
        'next_retry_at': 2000000,
      });

      expect(attempt.txid, 'tx456');
      expect(attempt.roomId, '!room2:example.com');
      expect(attempt.attempts, 1);
      expect(attempt.nextRetryAt.millisecondsSinceEpoch, 2000000);
    });

    test('toRow/fromRow round-trip', () {
      final original = OutboxAttempt(
        txid: 'roundtrip',
        roomId: '!rt:example.com',
        attempts: 5,
        nextRetryAt: DateTime.fromMillisecondsSinceEpoch(999999),
      );

      final restored = OutboxAttempt.fromRow(original.toRow());
      expect(restored.txid, original.txid);
      expect(restored.roomId, original.roomId);
      expect(restored.attempts, original.attempts);
      expect(restored.nextRetryAt, original.nextRetryAt);
    });
  });

  group('OutboxDatabase CRUD', () {
    test('all returns empty initially', () async {
      final results = await db.all();
      expect(results, isEmpty);
    });

    test('upsert inserts a new entry', () async {
      final attempt = OutboxAttempt(
        txid: 'tx1',
        roomId: '!room:example.com',
        attempts: 1,
        nextRetryAt: DateTime.fromMillisecondsSinceEpoch(1000),
      );

      await db.upsert(attempt);
      final results = await db.all();

      expect(results.length, 1);
      expect(results.first.txid, 'tx1');
    });

    test('upsert replaces existing entry (same txid)', () async {
      final attempt1 = OutboxAttempt(
        txid: 'tx1',
        roomId: '!room:example.com',
        attempts: 1,
        nextRetryAt: DateTime.fromMillisecondsSinceEpoch(1000),
      );
      final attempt2 = OutboxAttempt(
        txid: 'tx1',
        roomId: '!room:example.com',
        attempts: 5,
        nextRetryAt: DateTime.fromMillisecondsSinceEpoch(5000),
      );

      await db.upsert(attempt1);
      await db.upsert(attempt2);
      final results = await db.all();

      expect(results.length, 1);
      expect(results.first.attempts, 5);
    });

    test('remove deletes an entry by txid', () async {
      await db.upsert(OutboxAttempt(
        txid: 'tx1',
        roomId: '!r:e.com',
        attempts: 1,
        nextRetryAt: DateTime.fromMillisecondsSinceEpoch(1000),
      ));
      await db.upsert(OutboxAttempt(
        txid: 'tx2',
        roomId: '!r2:e.com',
        attempts: 2,
        nextRetryAt: DateTime.fromMillisecondsSinceEpoch(2000),
      ));

      await db.remove('tx1');
      final results = await db.all();

      expect(results.length, 1);
      expect(results.first.txid, 'tx2');
    });

    test('remove is a no-op for non-existent txid', () async {
      await db.upsert(OutboxAttempt(
        txid: 'tx1',
        roomId: '!r:e.com',
        attempts: 1,
        nextRetryAt: DateTime.fromMillisecondsSinceEpoch(1000),
      ));

      await db.remove('nonexistent');
      final results = await db.all();

      expect(results.length, 1);
    });

    test('retainOnly with empty set clears all', () async {
      await db.upsert(OutboxAttempt(
        txid: 'tx1',
        roomId: '!r:e.com',
        attempts: 1,
        nextRetryAt: DateTime.fromMillisecondsSinceEpoch(1000),
      ));

      await db.retainOnly({});
      final results = await db.all();

      expect(results, isEmpty);
    });

    test('retainOnly keeps only specified txids', () async {
      for (var i = 0; i < 5; i++) {
        await db.upsert(OutboxAttempt(
          txid: 'tx$i',
          roomId: '!r$i:e.com',
          attempts: i,
          nextRetryAt: DateTime.fromMillisecondsSinceEpoch(1000 * i),
        ));
      }

      await db.retainOnly({'tx1', 'tx3'});
      final results = await db.all();

      expect(results.length, 2);
      final txids = results.map((e) => e.txid).toSet();
      expect(txids, {'tx1', 'tx3'});
    });

    test('retainOnly with all txids keeps everything', () async {
      await db.upsert(OutboxAttempt(
        txid: 'tx1',
        roomId: '!r:e.com',
        attempts: 1,
        nextRetryAt: DateTime.fromMillisecondsSinceEpoch(1000),
      ));

      await db.retainOnly({'tx1'});
      final results = await db.all();

      expect(results.length, 1);
    });

    test('ensureSchema is idempotent', () async {
      await db.ensureSchema();
      await db.upsert(OutboxAttempt(
        txid: 'tx1',
        roomId: '!r:e.com',
        attempts: 1,
        nextRetryAt: DateTime.fromMillisecondsSinceEpoch(1000),
      ));

      final results = await db.all();
      expect(results.length, 1);
    });
  });
}

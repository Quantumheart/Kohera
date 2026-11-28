import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Guards the raw-Room boundary: feature and shared code must not reach
/// the matrix SDK directly.
void main() {
  const guardedDirs = ['lib/features', 'lib/shared'];

  Iterable<File> dartFilesIn(String path) sync* {
    final dir = Directory(path);
    if (!dir.existsSync()) return;
    for (final entity in dir.listSync(recursive: true)) {
      if (entity is File && entity.path.endsWith('.dart')) yield entity;
    }
  }

  test('no feature or shared file calls rawRoom or getRoomById', () {
    final offenders = <String>[];
    for (final dir in guardedDirs) {
      for (final file in dartFilesIn(dir)) {
        final source = file.readAsStringSync();
        if (source.contains('rawRoom(') || source.contains('getRoomById(')) {
          offenders.add(file.path);
        }
      }
    }

    expect(
      offenders,
      isEmpty,
      reason: 'Route SDK room access through a repository instead:\n'
          '${offenders.join('\n')}',
    );
  });

  test('only the e2ee feature imports the matrix SDK', () {
    const allowedPrefix = 'lib/features/e2ee/';
    final offenders = <String>[];
    for (final dir in guardedDirs) {
      for (final file in dartFilesIn(dir)) {
        if (file.path.startsWith(allowedPrefix)) continue;
        final source = file.readAsStringSync();
        if (source.contains("import 'package:matrix/")) {
          offenders.add(file.path);
        }
      }
    }

    expect(
      offenders,
      isEmpty,
      reason: 'Consume domain models from a repository instead:\n'
          '${offenders.join('\n')}',
    );
  });
}

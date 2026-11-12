import 'dart:convert';
import 'dart:io';

import 'package:flutter_driver/flutter_driver.dart';
import 'package:integration_test/common.dart';

Future<void> main() async {
  final driver = await FlutterDriver.connect();
  final jsonResult = await driver.requestData(null);
  final response = Response.fromJson(jsonResult);
  await driver.close();

  final data = response.data ?? <String, dynamic>{};
  final screenshots = (data['screenshots'] as List<dynamic>?) ?? const [];
  final outDir = Directory(
    Platform.environment['KOHERA_SCREENSHOT_DIR'] ?? 'build/screenshots',
  );
  if (!outDir.existsSync()) outDir.createSync(recursive: true);
  for (final entry in screenshots) {
    final map = entry as Map<String, dynamic>;
    final name = map['screenshotName'] as String;
    final List<int> bytes;
    if (map['bytesBase64'] != null) {
      bytes = base64Decode(map['bytesBase64'] as String);
    } else {
      bytes = (map['bytes'] as List<dynamic>).cast<int>();
    }
    final file = File('${outDir.path}/$name.png');
    await file.writeAsBytes(bytes);
    print('[Kohera] screenshot written: ${file.path}');
  }

  if (response.allTestsPassed) {
    print('All tests passed.');
    exit(0);
  } else {
    print('Failure Details:\n${response.formattedFailureDetails}');
    exit(1);
  }
}

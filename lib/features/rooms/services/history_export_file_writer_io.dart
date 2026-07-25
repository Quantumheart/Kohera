import 'dart:io' show File;
import 'dart:typed_data';

import 'package:flutter/foundation.dart';

Future<void> writeExportFile(String path, Uint8List bytes) async {
  await File(path).writeAsBytes(bytes);
}

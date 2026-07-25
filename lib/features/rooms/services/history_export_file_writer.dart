import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:kohera/features/rooms/services/history_export_file_writer_io.dart'
    if (dart.library.html) 'package:kohera/features/rooms/services/history_export_file_writer_web.dart'
    as writer;

/// Writes [bytes] to [path] on native targets. On web this is a no-op because
/// [FilePicker.saveFile] already triggered the browser download.
Future<void> writeExportFile(String path, Uint8List bytes) {
  return writer.writeExportFile(path, bytes);
}

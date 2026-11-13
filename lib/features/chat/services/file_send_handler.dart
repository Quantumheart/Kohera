import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:kohera/core/extensions/auth_error_formatter.dart';
import 'package:kohera/core/models/pending_attachment.dart';
import 'package:kohera/core/models/upload_state.dart';
import 'package:kohera/data/repositories/room_repository.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';
import 'package:provider/provider.dart';

// coverage:ignore-start

Future<void> pickAndSendFile(
  BuildContext context,
  String roomId,
  ValueNotifier<UploadState?> uploadNotifier,
) async {
  final scaffold = ScaffoldMessenger.of(context);
  final rooms = context.read<RoomRepository>();

  final files = await FilePicker.pickFiles(dialogTitle: 'Kohera');
  if (files.isEmpty) return;

  final picked = files.first;
  final bytes = await picked.readAsBytes();
  final name = picked.name;

  final room = rooms.rawRoom(roomId);
  if (room == null) return;

  await sendFileBytes(
    scaffold: scaffold,
    room: room,
    name: name,
    bytes: bytes,
    uploadNotifier: uploadNotifier,
  );
}

Future<PendingAttachment?> pickFileAsAttachment() async {
  final files = await FilePicker.pickFiles(dialogTitle: 'Kohera');
  if (files.isEmpty) return null;
  final picked = files.first;
  final bytes = await picked.readAsBytes();
  return PendingAttachment.fromBytes(bytes: bytes, name: picked.name);
}

Future<bool> sendFileBytes({
  required ScaffoldMessengerState scaffold,
  required Room room,
  required String name,
  required Uint8List bytes,
  required ValueNotifier<UploadState?> uploadNotifier,
  String? threadRootEventId,
  String? threadLastEventId,
}) async {
  uploadNotifier.value = UploadState(
    status: UploadStatus.uploading,
    fileName: name,
  );

  try {
    final file = MatrixFile.fromMimeType(bytes: bytes, name: name);
    await room.sendFileEvent(
      file,
      threadRootEventId: threadRootEventId,
      threadLastEventId: threadLastEventId,
    );
    uploadNotifier.value = null;
    return true;
  } on FileTooBigMatrixException {
    uploadNotifier.value = null;
    scaffold.showSnackBar(
      SnackBar(content: Text('File too large: $name')),
    );
    return false;
  } catch (e) {
    uploadNotifier.value = UploadState(
      status: UploadStatus.error,
      fileName: name,
      error: e.toString(),
    );
    scaffold.showSnackBar(
      SnackBar(content: Text('Upload failed: ${AuthErrorFormatter.friendlyAuthError(e)}')),
    );
    return false;
  }
}
// coverage:ignore-end

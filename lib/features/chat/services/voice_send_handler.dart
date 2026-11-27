import 'package:kohera/core/extensions/auth_error_formatter.dart';
import 'package:kohera/core/models/upload_state.dart';
import 'package:kohera/data/models/kohera_file_too_big_exception.dart';
import 'package:kohera/data/repositories/room_repository.dart';
import 'package:kohera/features/chat/services/read_file_bytes.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

// coverage:ignore-start

Future<void> sendVoiceMessage(
  BuildContext context,
  String roomId,
  ValueNotifier<UploadState?> uploadNotifier,
  String filePath,
  Duration duration, {
  String? threadRootEventId,
  String? threadLastEventId,
}) async {
  final scaffold = ScaffoldMessenger.of(context);
  final rooms = context.read<RoomRepository>();
  if (!rooms.roomExists(roomId)) return;

  final bytes = await readFileBytes(filePath);
  final name = filePath.split('/').last;

  uploadNotifier.value = UploadState(
    status: UploadStatus.uploading,
    fileName: name,
  );

  try {
    await rooms.sendVoiceFile(
      roomId,
      bytes,
      name,
      duration: duration,
      threadRootEventId: threadRootEventId,
      threadLastEventId: threadLastEventId,
    );
    uploadNotifier.value = null;
  } on KoheraFileTooBigException {
    uploadNotifier.value = null;
    scaffold.showSnackBar(
      const SnackBar(content: Text('Voice message too large for this server')),
    );
  } catch (e) {
    uploadNotifier.value = UploadState(
      status: UploadStatus.error,
      fileName: name,
      error: e.toString(),
    );
    scaffold.showSnackBar(
      SnackBar(
          content: Text(
              'Upload failed: ${AuthErrorFormatter.friendlyAuthError(e)}',),),
    );
  } finally {
    try {
      await deleteFile(filePath);
    } catch (_) {}
  }
}
// coverage:ignore-end

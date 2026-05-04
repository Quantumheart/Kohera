import 'package:image_picker/image_picker.dart';
import 'package:kohera/core/models/pending_attachment.dart';

// coverage:ignore-start

Future<List<PendingAttachment>> pickMediaFromGallery({required int limit}) async {
  if (limit <= 0) return const [];
  final picker = ImagePicker();
  final picked = await picker.pickMultipleMedia(limit: limit);
  if (picked.isEmpty) return const [];

  final attachments = <PendingAttachment>[];
  for (final xfile in picked) {
    final bytes = await xfile.readAsBytes();
    final name = xfile.name.isNotEmpty ? xfile.name : _fallbackName(xfile.path);
    attachments.add(PendingAttachment.fromBytes(bytes: bytes, name: name));
  }
  return attachments;
}

Future<PendingAttachment?> takePhotoWithCamera() async {
  final picker = ImagePicker();
  final xfile = await picker.pickImage(source: ImageSource.camera);
  if (xfile == null) return null;
  final bytes = await xfile.readAsBytes();
  final name = xfile.name.isNotEmpty ? xfile.name : _cameraFilename();
  return PendingAttachment.fromBytes(bytes: bytes, name: name);
}

String _cameraFilename() {
  final now = DateTime.now();
  String two(int n) => n.toString().padLeft(2, '0');
  final ts =
      '${now.year}${two(now.month)}${two(now.day)}_${two(now.hour)}${two(now.minute)}${two(now.second)}';
  return 'camera_$ts.jpg';
}

String _fallbackName(String path) {
  final slash = path.lastIndexOf('/');
  if (slash >= 0 && slash < path.length - 1) return path.substring(slash + 1);
  return _cameraFilename();
}

// coverage:ignore-end

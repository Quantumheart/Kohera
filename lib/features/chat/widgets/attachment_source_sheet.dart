import 'package:flutter/material.dart';
import 'package:kohera/core/theme/k_icons.dart';
enum AttachmentSource { gallery, camera, file, gif, sticker }

Future<AttachmentSource?> showAttachmentSourceSheet(
  BuildContext context, {
  bool showGif = false,
  bool showSticker = false,
}) {
  return showModalBottomSheet<AttachmentSource>(
    context: context,
    showDragHandle: true,
    builder: (sheetContext) {
      return SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(KIcons.photoLibraryOutlined),
              title: const Text('Photo or Video'),
              onTap: () => Navigator.pop(sheetContext, AttachmentSource.gallery),
            ),
            ListTile(
              leading: const Icon(KIcons.cameraAltOutlined),
              title: const Text('Take Photo'),
              onTap: () => Navigator.pop(sheetContext, AttachmentSource.camera),
            ),
            ListTile(
              leading: const Icon(KIcons.folderOutlined),
              title: const Text('File'),
              onTap: () => Navigator.pop(sheetContext, AttachmentSource.file),
            ),
            if (showGif)
              ListTile(
                leading: const Icon(KIcons.gifBoxOutlined),
                title: const Text('GIF'),
                onTap: () => Navigator.pop(sheetContext, AttachmentSource.gif),
              ),
            if (showSticker)
              ListTile(
                leading: const Icon(KIcons.emojiEmotionsOutlined),
                title: const Text('Stickers & Emoji'),
                onTap: () =>
                    Navigator.pop(sheetContext, AttachmentSource.sticker),
              ),
            const SizedBox(height: 8),
          ],
        ),
      );
    },
  );
}

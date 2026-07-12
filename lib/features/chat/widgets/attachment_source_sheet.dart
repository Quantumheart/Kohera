import 'package:flutter/material.dart';

enum AttachmentSource { gallery, camera, file, gif, sticker, poll }

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
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.photo_library_outlined),
                title: const Text('Photo or Video'),
                onTap: () =>
                    Navigator.pop(sheetContext, AttachmentSource.gallery),
              ),
              ListTile(
                leading: const Icon(Icons.camera_alt_outlined),
                title: const Text('Take Photo'),
                onTap: () =>
                    Navigator.pop(sheetContext, AttachmentSource.camera),
              ),
              ListTile(
                leading: const Icon(Icons.folder_outlined),
                title: const Text('File'),
                onTap: () => Navigator.pop(sheetContext, AttachmentSource.file),
              ),
              if (showGif)
                ListTile(
                  leading: const Icon(Icons.gif_box_outlined),
                  title: const Text('GIF'),
                  onTap: () => Navigator.pop(sheetContext, AttachmentSource.gif),
                ),
              if (showSticker)
                ListTile(
                  leading: const Icon(Icons.emoji_emotions_outlined),
                  title: const Text('Stickers & Emoji'),
                  onTap: () =>
                      Navigator.pop(sheetContext, AttachmentSource.sticker),
                ),
              ListTile(
                leading: const Icon(Icons.poll_outlined),
                title: const Text('Poll'),
                onTap: () =>
                    Navigator.pop(sheetContext, AttachmentSource.poll),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      );
    },
  );
}

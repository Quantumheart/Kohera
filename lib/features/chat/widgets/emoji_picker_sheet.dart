import 'dart:async';

import 'package:flutter/material.dart';
import 'package:kohera/core/services/preferences_service.dart';
import 'package:kohera/features/chat/widgets/openmoji_picker.dart';
import 'package:provider/provider.dart';

// coverage:ignore-start

void showEmojiPickerSheet(BuildContext context, void Function(String emoji) onSelected) {
  unawaited(showDialog(
    context: context,
    barrierColor: Colors.black26,
    builder: (context) => _EmojiPickerDialog(onSelected: onSelected),
  ),);
}

class _EmojiPickerDialog extends StatelessWidget {
  const _EmojiPickerDialog({required this.onSelected});

  final void Function(String emoji) onSelected;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final prefs = context.watch<PreferencesService>();

    return Dialog(
      backgroundColor: cs.surfaceContainer,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(0)), // Sharp corners for pixel theme
      clipBehavior: Clip.antiAlias,
      child: SizedBox(
        width: 350,
        height: 400,
        child: OpenMojiPicker(
          skinTone: prefs.skinTone,
          onSkinToneChanged: prefs.setSkinTone,
          onSelected: (emoji) {
            Navigator.of(context).pop();
            onSelected(emoji);
          },
        ),
      ),
    );
  }
}
// coverage:ignore-end

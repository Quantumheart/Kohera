import 'dart:async';
import 'dart:js_interop';

import 'package:kohera/features/chat/services/paste_image_handler.dart';
import 'package:web/web.dart';

final _controller = StreamController<ClipboardImageData>.broadcast();

Stream<ClipboardImageData> get webPasteImageStream => _controller.stream;

bool _initialized = false;

void initWebPasteListener() {
  if (_initialized) return;
  _initialized = true;
  document.addEventListener(
    'paste',
    (JSAny? event) {
      if (event == null) return;
      _handlePaste(event as ClipboardEvent);
    }.toJS,
  );
}

void _handlePaste(ClipboardEvent event) {
  final items = event.clipboardData?.items;
  if (items == null) return;

  for (var i = 0; i < items.length; i++) {
    final item = items[i];
    if (item.kind != 'file') continue;
    if (!item.type.startsWith('image/')) continue;

    final file = item.getAsFile();
    if (file == null) continue;

    final mimeType = item.type;
    unawaited(file.arrayBuffer().toDart.then((buffer) {
      _controller.add(ClipboardImageData(
        bytes: buffer.toDart.asUint8List(),
        mimeType: mimeType,
      ),);
    }),);

    // Prevent the browser from trying to handle the image paste itself.
    event.preventDefault();
    return;
  }
}

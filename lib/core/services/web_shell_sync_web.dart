import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:flutter/material.dart';
import 'package:web/web.dart' as web;

@JS('koheraSafeAreaInsets')
external JSObject _koheraSafeAreaInsets();

void setWebShellAccent(Color color) {
  final rgb = color.toARGB32() & 0xFFFFFF;
  final hex = '#${rgb.toRadixString(16).padLeft(6, '0').toUpperCase()}';
  final win = web.window as JSObject;
  if (!win.hasProperty('setKoheraLoaderColor'.toJS).toDart) return;
  win.callMethod('setKoheraLoaderColor'.toJS, hex.toJS);
}

EdgeInsets webSafeAreaInsets() {
  final win = web.window as JSObject;
  if (!win.hasProperty('koheraSafeAreaInsets'.toJS).toDart) return EdgeInsets.zero;
  final obj = _koheraSafeAreaInsets();
  double read(String key) {
    final v = (obj.getProperty(key.toJS) as JSNumber?)?.toDartDouble;
    return v ?? 0;
  }

  return EdgeInsets.fromLTRB(
    read('left'),
    read('top'),
    read('right'),
    read('bottom'),
  );
}

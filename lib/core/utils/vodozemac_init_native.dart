import 'package:flutter_vodozemac/flutter_vodozemac.dart' as vod;

Future<void> initVodozemac() async {
  try {
    await vod.init();
  } catch (e) {
    // flutter_rust_bridge throws StateError if init is called twice (hot restart).
    if (e is StateError && e.message.contains('initialize flutter_rust_bridge twice')) return;
    rethrow;
  }
}

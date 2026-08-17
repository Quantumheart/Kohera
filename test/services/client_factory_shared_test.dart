import 'package:flutter_test/flutter_test.dart';
import 'package:kohera/core/services/client_factory_shared.dart';
import 'package:matrix/matrix.dart';

void main() {
  // The SDK log level must NOT default to `Level.verbose` in debug builds:
  // the SDK's log path is a synchronous `print()` on the main isolate, and at
  // verbose it logs per room/event during a sync, starving the platform event
  // loop and tripping the OS "not responding" watchdog (issue #991). Verbose
  // is opt-in via --dart-define=KOHERA_VERBOSE_SDK_LOGS=true.
  test('koheraSdkLogLevel is not verbose by default (debug build)', () {
    // `flutter test` runs in debug mode, so kReleaseMode is false and the
    // verbose flag is unset → the level collapses to `info`.
    expect(koheraSdkLogLevel, Level.info);
    expect(koheraSdkLogLevel, isNot(Level.verbose));
  });
}

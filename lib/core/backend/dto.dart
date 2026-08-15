// coverage:ignore-file

import 'package:matrix/matrix.dart';

// ── DTO base ──────────────────────────────────────────────────────
//
// Every DTO is plain sendable data (fields are primitives, Lists, or Maps of
// primitives).  No live SDK objects cross the isolate boundary.  Each DTO has
// a factory `fromSdk(...)` that extracts data from the live SDK object on the
// worker, and `toMap()`/`fromMap()` for wire serialization.

abstract class Dto {
  Map<String, dynamic> toMap();
}




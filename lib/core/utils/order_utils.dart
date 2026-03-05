/// Lexicographic order string utilities for Matrix `m.space.child` ordering.
///
/// Order strings use printable ASCII (0x20 – 0x7E) and are at most 50 chars.
/// See: https://spec.matrix.org/latest/client-server-api/#spaces
library;

// Inclusive range of allowed characters.
const int _minChar = 0x20; // space
const int _maxChar = 0x7E; // tilde
const int _maxLength = 50;

/// Generate a lexicographic string between [before] and [after].
///
/// - Both `null` → returns a single midpoint character.
/// - [before] is `null` → returns a string less than [after].
/// - [after] is `null` → returns a string greater than [before].
/// - Both non-null → returns a string strictly between them.
///
/// Returns `null` if no midpoint can be generated within [_maxLength] chars
/// (practically impossible with the 95-char alphabet).
String? midpoint(String? before, String? after) {
  // Normalise: treat empty strings as null.
  if (before != null && before.isEmpty) before = null;
  if (after != null && after.isEmpty) after = null;

  if (before == null && after == null) {
    return String.fromCharCode((_minChar + _maxChar) ~/ 2);
  }

  if (before == null) {
    // Need string < after. Try to find a char position in after that's
    // above _minChar so we can place something before it.
    return _generateBefore(after!);
  }

  if (after == null) {
    // Need string > before. Append midpoint char to extend.
    return _appendAfter(before);
  }

  return _midpointBetween(before, after);
}

/// Return a string that sorts before [upper].
///
/// Scans for the first char above _minChar and places a midpoint before it.
/// Returns `null` if upper consists entirely of _minChar (impossible case).
String? _generateBefore(String upper) {
  for (var i = 0; i < upper.length && i < _maxLength; i++) {
    final c = upper.codeUnitAt(i);
    if (c > _minChar) {
      // Place a char halfway between _minChar and c at this position.
      final mid = (_minChar + c) ~/ 2;
      return upper.substring(0, i) + String.fromCharCode(mid);
    }
  }
  // All chars are _minChar — cannot generate a shorter/smaller string.
  return null;
}

/// Return a string strictly between [lo] and [hi] (lexicographically).
///
/// Conceptually pads [lo] with _minChar and [hi] with _maxChar to infinite
/// length, then finds the shortest midpoint.
String? _midpointBetween(String lo, String hi) {
  // Quick validation.
  if (lo.isNotEmpty && hi.isNotEmpty && lo.compareTo(hi) >= 0) return null;
  // Walk character by character. Conceptual padding:
  //   lo[i] defaults to _minChar when i >= lo.length
  //   hi[i] defaults to _maxChar when i >= hi.length
  //
  // But hi should NOT be padded beyond its length when we still have
  // common prefix with lo — a string of length n is less than any
  // string of length n+1 that shares the same prefix.

  final buf = StringBuffer();

  for (var i = 0; i < _maxLength; i++) {
    final loC = i < lo.length ? lo.codeUnitAt(i) : _minChar;
    // For hi: if we're past hi's length, any character we choose < _maxChar
    // produces a valid result (since "hi" < "hi" + anything is false, but
    // we're choosing chars for a string that must be < hi).
    // Actually, "ab" < "abc" in lex order, so if i >= hi.length, the
    // prefix we've built already equals hi's full string, and any extension
    // would be > hi. So we should NOT go past hi.length on the hi side
    // unless lo forces us to.
    final hiC = i < hi.length ? hi.codeUnitAt(i) : _maxChar;

    if (loC == hiC) {
      buf.writeCharCode(loC);
      continue;
    }

    // loC < hiC at this position.
    if (hiC - loC > 1) {
      // Room between them — pick midpoint.
      buf.writeCharCode((loC + hiC) ~/ 2);
      return buf.toString();
    }

    // hiC - loC == 1: take loC and find a suffix > lo's remaining.
    buf.writeCharCode(loC);
    // Now we need: buf + suffix > lo, and buf + suffix < hi.
    // Since buf ends with loC and hi[i] = loC+1, any suffix that makes
    // buf+suffix > lo will automatically be < hi (because loC < hiC).
    // So we just need suffix > lo[i+1..].
    final remaining = i + 1 < lo.length ? lo.substring(i + 1) : '';
    final suffix = _appendAfter(remaining);
    if (suffix != null && buf.length + suffix.length <= _maxLength) {
      buf.write(suffix);
      return buf.toString();
    }
    // If that fails, keep going deeper.
  }

  return null;
}

/// Return a string that sorts after [s] by appending/modifying characters.
///
/// Strategy: try to increment from the rightmost char. If all chars are
/// _maxChar, append a midpoint character.
String? _appendAfter(String s) {
  if (s.isEmpty) {
    return String.fromCharCode((_minChar + _maxChar) ~/ 2);
  }

  // Try incrementing from the rightmost non-max character.
  for (var i = s.length - 1; i >= 0; i--) {
    final c = s.codeUnitAt(i);
    if (c < _maxChar) {
      // Increment to midpoint between c and _maxChar.
      return s.substring(0, i) + String.fromCharCode((c + _maxChar + 1) ~/ 2);
    }
  }

  // All chars are _maxChar — append a midpoint.
  if (s.length < _maxLength) {
    return s + String.fromCharCode((_minChar + _maxChar) ~/ 2);
  }

  return null;
}

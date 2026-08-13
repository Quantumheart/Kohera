class HighlightSpan {
  const HighlightSpan(this.text, this.isMatch);
  final String text;
  final bool isMatch;
}

class _Match {
  final int start;
  final int end;
  _Match(this.start, this.end);
}

List<HighlightSpan> highlightSpans(String text, List<String> terms) {
  if (terms.isEmpty) return [HighlightSpan(text, false)];

  final lower = text.toLowerCase();
  final matches = <_Match>[];

  for (final term in terms) {
    if (term.isEmpty) continue;
    final termLower = term.toLowerCase();
    var start = 0;
    while (start < text.length) {
      final index = lower.indexOf(termLower, start);
      if (index == -1) break;
      matches.add(_Match(index, index + term.length));
      start = index + 1; // Allow overlapping matches for different terms
    }
  }

  if (matches.isEmpty) {
    if (text.isEmpty) return [];
    return [HighlightSpan(text, false)];
  }

  matches.sort((a, b) => a.start.compareTo(b.start));

  final merged = <_Match>[];
  var current = matches[0];

  for (var i = 1; i < matches.length; i++) {
    final next = matches[i];
    if (next.start <= current.end) {
      current = _Match(current.start, current.end > next.end ? current.end : next.end);
    } else {
      merged.add(current);
      current = next;
    }
  }
  merged.add(current);

  final spans = <HighlightSpan>[];
  var lastEnd = 0;

  for (final match in merged) {
    if (match.start > lastEnd) {
      spans.add(HighlightSpan(text.substring(lastEnd, match.start), false));
    }
    spans.add(HighlightSpan(text.substring(match.start, match.end), true));
    lastEnd = match.end;
  }

  if (lastEnd < text.length) {
    spans.add(HighlightSpan(text.substring(lastEnd), false));
  }

  return spans;
}

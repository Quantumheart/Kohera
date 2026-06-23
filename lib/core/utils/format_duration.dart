String formatDuration(Duration d) {
  final minutes = d.inMinutes;
  final seconds = d.inSeconds % 60;
  return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
}

/// Formats [d] as a clock duration, adding an hours segment only when non-zero.
///
/// [padMinutes] controls whether the minutes segment is zero-padded when there
/// is no hours segment (e.g. `05:03` vs `5:03`); it is always padded once an
/// hours segment is present.
String formatClockDuration(Duration d, {bool padMinutes = true}) {
  final hours = d.inHours;
  final minutes = d.inMinutes.remainder(60);
  final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
  if (hours > 0) {
    return '$hours:${minutes.toString().padLeft(2, '0')}:$seconds';
  }
  return '${padMinutes ? minutes.toString().padLeft(2, '0') : minutes}:$seconds';
}

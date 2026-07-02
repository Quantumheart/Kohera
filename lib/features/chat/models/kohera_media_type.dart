/// Kohera-owned enum representing the type of a media attachment.
///
/// Maps from Matrix `msgtype` values (m.image, m.video, m.audio, m.file)
/// and the sticker event type. No `package:matrix/matrix.dart` import.
enum KoheraMediaType { image, video, audio, file, sticker }

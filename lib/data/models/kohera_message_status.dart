/// Kohera-owned send status for a message.
///
/// Produced by the conversion boundary (`MessageDisplayResolver`) from
/// `Event.status`. Display widgets consume this enum without importing the
/// Matrix SDK.
enum KoheraMessageStatus { sending, sent, error }

enum JoinMode {
  invite,
  restricted,
  knockRestricted,
  public,
  knock;

  String get displayLabel {
    switch (this) {
      case JoinMode.invite:
        return 'Invite-only';
      case JoinMode.restricted:
        return 'Space members';
      case JoinMode.knockRestricted:
        return 'Space members + knock';
      case JoinMode.public:
        return 'Public';
      case JoinMode.knock:
        return 'Knock';
    }
  }

  /// Wire value for the `join_rule` field in `m.room.join_rules`.
  String get wire {
    switch (this) {
      case JoinMode.invite:
        return 'invite';
      case JoinMode.public:
        return 'public';
      case JoinMode.knock:
        return 'knock';
      case JoinMode.restricted:
        return 'restricted';
      case JoinMode.knockRestricted:
        return 'knock_restricted';
    }
  }

  /// Whether this mode uses the `allow` list (restricted / knock_restricted).
  bool get isRestrictedFamily =>
      this == JoinMode.restricted || this == JoinMode.knockRestricted;
}

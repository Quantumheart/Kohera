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
}

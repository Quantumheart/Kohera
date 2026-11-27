/// SDK-free caller identity for incoming and outgoing call UI.
library;

class KoheraCallerProfile {
  const KoheraCallerProfile({required this.displayName, this.avatarUrl});

  final String displayName;
  final Uri? avatarUrl;
}

import 'package:flutter/foundation.dart';
import 'package:kohera/data/services/avatar_resolver.dart';
import 'package:kohera/data/services/media_resolver.dart';

class MediaRepository extends ChangeNotifier {
  MediaRepository({
    required AvatarResolver avatarResolver,
    required MediaResolver mediaResolver,
  })  : _avatarResolver = avatarResolver,
        _mediaResolver = mediaResolver;

  final AvatarResolver _avatarResolver;
  final MediaResolver _mediaResolver;
  bool _disposed = false;

  AvatarResolver get avatarResolver => _avatarResolver;
  MediaResolver get mediaResolver => _mediaResolver;

  @override
  void notifyListeners() {
    if (_disposed) return;
    super.notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

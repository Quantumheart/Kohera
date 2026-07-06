import 'dart:typed_data';

import 'package:matrix/matrix.dart';

/// Wraps avatar upload operations that require [MatrixFile] construction.
///
/// Screens call [uploadAvatar] instead of constructing `MatrixFile` directly,
/// keeping `package:matrix/matrix.dart` out of widget files.
class ProfileAvatarService {
  const ProfileAvatarService();

  Future<void> uploadAvatar(
    Client client,
    Uint8List bytes,
    String name,
  ) async {
    await client.setAvatar(MatrixFile(bytes: bytes, name: name));
  }
}

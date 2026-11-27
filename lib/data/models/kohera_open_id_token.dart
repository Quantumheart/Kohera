/// SDK-free OpenID token payload used to authenticate against a LiveKit
/// service (MSC4198-style `openid_token` payload).
library;

class KoheraOpenIdToken {
  const KoheraOpenIdToken({
    required this.accessToken,
    required this.tokenType,
    required this.matrixServerName,
    required this.expiresIn,
  });

  final String accessToken;
  final String tokenType;
  final String matrixServerName;
  final int expiresIn;

  Map<String, dynamic> toJson() => {
        'access_token': accessToken,
        'token_type': tokenType,
        'matrix_server_name': matrixServerName,
        'expires_in': expiresIn,
      };
}

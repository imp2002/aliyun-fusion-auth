/// An opaque proof returned by the native SDK.
///
/// Submit [verifyToken] to your backend. Only the backend may decide whether to
/// create a session, register a user or update a password after verification.
class FusionAuthResult {
  /// Token for the server-side VerifyWithFusionAuthToken API.
  final String verifyToken;

  /// Whether the iOS authorization page remains owned by this request.
  /// Capture its appearance if needed, then await cancel before navigation.
  /// Also cancel when this flow is abandoned.
  final bool numberPageRetained;

  /// Creates a result from an opaque SDK proof.
  const FusionAuthResult({
    required this.verifyToken,
    this.numberPageRetained = false,
  });

  @override
  String toString() => 'FusionAuthResult(verifyToken: <redacted>)';
}

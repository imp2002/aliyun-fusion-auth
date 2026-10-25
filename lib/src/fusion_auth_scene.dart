/// Supported scenario IDs configured in the Alibaba Cloud console.
enum FusionAuthScene {
  /// Authenticate a phone number before logging in or registering an account.
  login('100001'),

  /// Authenticate the configured phone number before resetting its password.
  resetPassword('100003');

  /// The native SDK's template ID.
  final String id;

  const FusionAuthScene(this.id);
}

/// Ordered events emitted by a fusion-auth session.
enum FusionAuthEventType {
  numberReady,
  authorizing,
  smsSwitching,
  appSmsReady,
  success,
  cancelled,
  failure,
}

/// A session-scoped, non-sensitive authentication event.
class FusionAuthEvent {
  const FusionAuthEvent({required this.type, required this.sessionId});

  final FusionAuthEventType type;
  final String sessionId;
}

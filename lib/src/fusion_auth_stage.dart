import 'dart:async';

/// Presentation progress only; no stage grants consent or proves identity.
enum FusionAuthStage {
  /// The carrier number authorization page is visible and awaits user action.
  numberReady,

  /// The consented number authorization has started. Block duplicate actions.
  authorizing,

  /// The SDK is moving to SMS; sending must wait for `app_sms_ready`.
  smsSwitching,
}

/// May finish preparing the underlying UI before native SMS presentation closes.
/// Do not wait for authentication or SMS completion inside this callback.
typedef FusionAuthStageCallback = FutureOr<void> Function(
    FusionAuthStage stage);

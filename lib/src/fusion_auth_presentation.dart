/// Presentation modes supported by the native fusion-auth bridge.
enum FusionAuthPresentation {
  /// Use a vendor-managed native authorization page.
  nativePage,

  /// Ask the bridge to host authorization inside the Flutter login surface.
  ///
  /// Android enables this only when the bundled vendor AAR exposes a supported
  /// embeddable view/container API.
  flutterHosted,
}

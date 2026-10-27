import 'fusion_auth_scene.dart';
import 'fusion_auth_login_card.dart';
import 'fusion_auth_presentation.dart';

/// Configuration for one explicitly requested authentication attempt.
///
/// Fetch [authToken] from your own backend's GetFusionAuthToken integration.
/// Never pass Alibaba Cloud AccessKey credentials to this plugin.
class FusionAuthConfig {
  /// Short-lived SDK authentication token issued by your server.
  final String authToken;

  /// Scheme matching the current platform, bundle/package ID and signature.
  final String schemeCode;

  /// Scenario to launch after SDK token authentication succeeds.
  final FusionAuthScene scene;

  /// Application name displayed on the native authentication page.
  final String appName;

  /// Optional greeting shown by the Android native authorization page.
  /// The host app should compute this from its own current-time rules.
  final String? greeting;

  /// Your application's HTTPS user agreement URL.
  final Uri termsUrl;

  /// Your application's HTTPS privacy policy URL.
  final Uri privacyUrl;

  /// User agreement link title. Operator agreements are retained separately.
  final String termsTitle;

  /// Privacy policy link title.
  final String privacyTitle;

  /// Whether the user has explicitly accepted your app's privacy disclosures.
  ///
  /// When false the SDK is not initialized unless [deferConsentToNative] is
  /// enabled for login. Native agreement checkboxes always start unchecked.
  final bool privacyAccepted;

  /// Allow login number retrieval before consent. The native SDK still starts
  /// unchecked and requires consent before sending SMS or producing proof.
  /// Does not apply to password resets.
  final bool deferConsentToNative;

  /// Keep fusion SMS in the caller's form using sendSmsCode/submitSmsCode.
  /// The native session remains alive until cancel; login scenes only.
  final bool appSms;

  /// Start at the configured SMS fallback instead of offering the local number.
  final bool startWithSms;

  /// Optional login/registration prefill; required for password resets.
  ///
  /// Your server must compare the verified number with the intended target.
  /// A prefilled native field does not establish ownership of that number.
  final String? phoneNumber;

  /// Optional entry on the native number authorization page for another login
  /// method, such as password login. Clicking it closes the SDK UI and makes
  /// authenticate throw a PlatformException with code `alternative_login`.
  /// The app can then navigate after native cleanup has finished.
  final String? alternateLoginLabel;

  /// Optional label for changing numbers within the native fusion flow.
  /// The SDK owns delivery and proof generation. With [appSms], input returns
  /// to the caller with app_sms_ready; otherwise the SDK keeps its SMS UI.
  final String? phoneInputLabel;

  /// Optional email verification entry. Returns `email_login` after native
  /// cleanup; the app owns email input, code delivery and verification.
  final String? emailLoginLabel;

  /// Optional iOS card styling. Android retains its SDK authorization page.
  final FusionAuthLoginCard? loginCard;

  /// Keep the iOS number authorization page visible after returning its proof.
  /// Paint snapshotNumberPage in the outgoing route, then await cancel before
  /// navigating. Also cancel on failure or disposal. SMS,
  /// Android and other scenes retain their existing completion behavior.
  final bool retainNumberPage;

  /// How the native authorization surface is presented.
  final FusionAuthPresentation presentation;

  /// Creates an authentication request. Validation runs when it is submitted.
  const FusionAuthConfig({
    required this.authToken,
    required this.schemeCode,
    required this.appName,
    this.greeting,
    required this.termsUrl,
    required this.privacyUrl,
    required this.privacyAccepted,
    this.deferConsentToNative = false,
    this.appSms = false,
    this.startWithSms = false,
    this.scene = FusionAuthScene.login,
    this.phoneNumber,
    this.alternateLoginLabel,
    this.phoneInputLabel,
    this.emailLoginLabel,
    this.loginCard,
    this.retainNumberPage = false,
    this.presentation = FusionAuthPresentation.nativePage,
    this.termsTitle = '用户协议',
    this.privacyTitle = '隐私政策',
  });

  // Deliberately inherit Object.toString: never interpolate tokens into logs.
}

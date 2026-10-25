# aliyun_fusion_auth

[简体中文](README.md) | English

A Flutter plugin for Alibaba Cloud Fusion Authentication. It presents the native SDK's authentication screens and returns a `verifyToken` to Dart for verification by your backend. It supports login/registration and password reset.

This is an independent, third-party Flutter plugin for Android and iOS. It provides a unified authentication API, native session management, and token handoff to your backend. See [NOTICE.en](NOTICE.en) for the license scope.

## Supported features and requirements

| Item | 0.1.7 |
| --- | --- |
| Android native SDK | 1.2.16; Android API 21+, compileSdk 36 |
| iOS native SDK | 1.2.15 distribution, with an embedded framework identifying itself as 1.2.14; iOS 15.0+; CocoaPods |
| Flutter / Dart | Flutter 3.19+ / Dart 3.3+; builds must also meet the platform requirements of your Flutter version |
| Standalone example toolchain | Flutter 3.47.6+ / Dart 3.13.5+; the example uses newer platform project templates |
| Login and registration | `FusionAuthScene.login`, scene `100001` |
| Password reset | `FusionAuthScene.resetPassword`, scene `100003`; requires a target phone number |
| Authentication UI | Native SDK screens; configurable app name, application agreements, and privacy policy |
| Successful result | An opaque `verifyToken`; it is neither an application session nor a verified phone number |

Successful iOS device authentication and backend login have been reported; the app-owned fusion SMS form and presentation changes in 0.1.7 still require device verification. The iOS XCFramework includes device and simulator slices; a successful simulator build does not establish that carrier authentication works. Follow the [validation checklist](doc/testing.en.md) on a physical device with your backend before production use.

The plugin does not bundle or initialize UMCommon / UMDevice by default, and does not provide device risk or phone scoring capabilities that depend on those components. Before using such scheme nodes, integrate the required components and handle user disclosure and consent separately; otherwise, disable those nodes in your Alibaba Cloud scheme.

## Installation and platform setup

```yaml
dependencies:
  aliyun_fusion_auth: ^0.1.7
```

To debug the plugin source, temporarily point the dependency to a local package directory:

```yaml
dependencies:
  aliyun_fusion_auth:
    path: ../aliyun-fusion-auth
```

Run `flutter pub get`. Create separate Android and iOS fusion authentication schemes in the Alibaba Cloud Phone Number Verification Service console, and configure the required authentication nodes and scenes. The Android package name and signing certificate, iOS Bundle ID, and each platform's SchemeCode must match the installed application. Check debug and release signatures separately.

On iOS, set the deployment target in your application's `ios/Podfile` to at least `15.0`, and keep the Xcode Runner deployment target consistent. The plugin's CocoaPods configuration integrates the SDK, resource bundles, and privacy manifest; do not manually add another copy of the same SDK. See the [iOS integration guide](ios/README.en.md). Android requires an Android SDK/Gradle environment capable of building with compileSdk 36; the library's permissions and SDK activities are included through manifest merging.

The client does not need and must not contain an Alibaba Cloud AccessKey. Backend integration is required; see the [server integration guide](doc/server-integration.en.md).

## Flutter API

Call the following function after the user explicitly accepts your application's agreements and privacy policy. Obtain `authToken` and `schemeCode` from an authentication attempt created by your backend for the current platform. `termsUrl` and `privacyUrl` must be your application's own HTTPS pages. Agreement titles default to “用户协议” and “隐私政策”. If you customize them through `termsTitle` / `privacyTitle`, both must be nonempty and distinct.

```dart
import 'package:aliyun_fusion_auth/aliyun_fusion_auth.dart';

Future<FusionAuthResult> collectPhoneProof({
  required String authToken,
  required String schemeCode,
  required String appName,
  required Uri termsUrl,
  required Uri privacyUrl,
  required bool userAcceptedPrivacy,
}) {
  return AliyunFusionAuth.authenticate(
    FusionAuthConfig(
      authToken: authToken,
      schemeCode: schemeCode,
      appName: appName,
      termsUrl: termsUrl,
      privacyUrl: privacyUrl,
      privacyAccepted: userAcceptedPrivacy,
      scene: FusionAuthScene.login,
    ),
  );
}
```

After receiving `result.verifyToken`, submit it to your backend over HTTPS and associate it with the server-created authentication attempt. Create an application session, register an account, or reset a password only after the backend successfully calls `VerifyWithFusionAuthToken` and completes the required business checks. Do not log in directly from a native success callback or place tokens in logs, analytics events, or URLs.

For password reset:

```dart
final result = await AliyunFusionAuth.authenticate(
  FusionAuthConfig(
    authToken: authTokenFromYourServer,
    schemeCode: schemeCodeFromYourServer,
    appName: yourAppName,
    termsUrl: yourTermsUrl,
    privacyUrl: yourPrivacyUrl,
    privacyAccepted: userAcceptedPrivacy,
    scene: FusionAuthScene.resetPassword,
    phoneNumber: targetPhoneNumber,
  ),
);
// Submit result.verifyToken and the server's attemptId to your backend.
// The backend must compare the phone number verified by Alibaba Cloud
// with the target phone number saved for this attempt.
```

`phoneNumber` is only a prefilled value or authentication target. Its current format must be an 11-digit mainland China mobile number; it is not proof of ownership. You may also provide it for login, but the backend must save and check any target that must match.

## Open the number login screen directly

After the user explicitly accepts your app privacy policy, call `authenticate()` on entry to the login route to use the native number authorization page as the login screen. An extra outer “one-click login” button is not required. The SDK displays a masked number in its native UI; this plugin has no separate API to prefetch a number into Flutter. Users still confirm carrier authorization on that page. The SDK follows the SMS or other fallback nodes configured in the console when carrier authentication is unavailable.

Set `FusionAuthConfig(alternateLoginLabel: 'Password login', ...)` to add an alternative login entry to the native number authorization page. After that entry is tapped, the plugin closes the native UI, finishes session cleanup, and throws `PlatformException(code: 'alternative_login')`. The app can then navigate to its password screen without submitting a verification proof. Omitting the option preserves the default UI; a configured label must not be blank.

Persist the user's actual app privacy consent. Automatically open the native flow once when entering the login route. After cancellation, terminal failure, or returning from password login, restore the application screen and offer manual retry instead of repeatedly opening it. Show app agreements before the first consent; never hard-code `privacyAccepted: true`.

## Card and number switching within fusion authentication

For login, set `phoneInputLabel: 'Change'` to customize the change-number button label. Switching numbers continues the current fusion authentication scene. The SDK owns phone/code input, SMS delivery and resend, and verification proof generation; carrier node failures also continue to subsequent nodes configured in the console. Success still returns a `verifyToken` for your backend to validate with `VerifyWithFusionAuthToken`. This option is not available for password reset.

The current fix removes the 0.1.1 behavior that closed the session and returned `phone_input` on number switching. Applications should no longer route number switching to a legacy SMS login API. For initialization errors or terminal scene failures, offer manual retry or another login method.

On iOS, optionally provide `loginCard: FusionAuthLoginCard(...)`. Its `frame` is a rectangle in Flutter global logical coordinates. Supply background, primary, text and secondary text colors, and an optional `textScale` from 1 to 1.5. `title` labels the one-click login button and defaults to “本机号码一键登录”. The masked number is centered in the card, with no duplicate heading, and the SDK's `sloganIsHidden` setting hides its service-provider message. Minimum width is 240 and minimum height is 400; coordinates must be finite and nonnegative. Measure after layout has settled and the whole card is visible. Omit the card and continue with the default SDK authorization page if a small screen or enlarged text cannot accommodate it.

This uses public SDK UI configuration to style a native authorization card. It does not expose the number to Flutter. A transparent backdrop preserves the app background; a change-number button sits beside the masked number, while the SDK owns one-click login and initially unchecked carrier agreements. `alternateLoginLabel` can retain a password entry below. Android also preserves the SDK's number-switching and SMS authentication flow while retaining its SDK page layout; iOS card styling does not apply there.

Optional `emailLoginLabel: 'Email code login'` adds a native email entry and returns `email_login` after cleanup. The app owns the email form and backend code delivery/verification. This option is login-only. With iOS `loginCard`, email sits beside password with a thin vertical divider and button widths measured from their labels; the card uses a plain background, compact buttons, and agreements below. Without consent, the login button keeps its normal appearance and only shows a consent reminder when tapped. Public SDK checkbox events switch to the SDK login button after consent; the SDK retains final authorization checks. Agreement text is semibold and left aligned. Android adds email in its existing native navigation area.

## Cancellation, errors, and retries

```dart
import 'package:flutter/services.dart';
import 'package:aliyun_fusion_auth/aliyun_fusion_auth.dart';

Future<void> cancelPhoneProof() => AliyunFusionAuth.cancel();

Future<FusionAuthResult?> tryAuthenticate(FusionAuthConfig config) async {
  try {
    return await AliyunFusionAuth.authenticate(config);
  } on PlatformException catch (error) {
    if (error.code == 'cancelled') return null;
    rethrow; // Show an appropriate message; do not log full arguments or raw tokens.
  }
}
```

Only one authentication flow can run at a time. Calling `cancel()` while idle is safe; it closes authentication without signing out of your application account. The native SDK manages the carrier, SMS, and graphical verification screens configured in your scheme. Recoverable node errors stay within the native flow; terminal failures complete the Dart Future with a `PlatformException`.

| Error code | Application handling |
| --- | --- |
| `cancelled` | The user cancelled; restore the current application screen |
| `email_login` | Open the app email verification form after native cleanup |
| `alternative_login` | Navigate to the selected login method after native cleanup completes |
| `privacy_not_accepted` | Obtain explicit consent before starting authentication |
| `busy` | Wait for or cancel the current attempt; do not start repeated flows |
| `invalid_arguments` | Check the SchemeCode, token, agreement URLs, app name, and phone number |
| `unsupported_platform` | Only Android / iOS are currently supported |
| `auth_token_expired` / `token_expired` | Obtain a fresh token from your backend and start again; native platforms use different codes |
| `auth_timeout` / `timeout` | This attempt has ended; check connectivity and obtain a new token |
| `invalid_result` | No valid proof was obtained; do not complete the business operation |
| `unsupported_sdk_version` / `sdk_cleanup_unavailable` | The iOS SDK does not match the pinned cleanup adapter; check for duplicate or manually replaced native SDKs, fix the integration, and run again |
| Other SDK errors | Treat as failure and allow a retry; you may log redacted error codes and request IDs |

Authentication waits for at most five minutes, followed by up to three seconds for cancellation cleanup. On token expiry, the plugin ends the attempt without waiting for network renewal inside a synchronous native callback. Scene `100002`, which includes operations such as changing a phone number that require intermediate backend verification, is unsupported. Scenes `100004` / `100005` are not exposed either.

## Example

[example](example/lib/main.dart) demonstrates native authentication interaction. Configure your own application identifiers/signatures and console scheme in the example project, then run `flutter run`. Enter a short-lived SDK token issued by your backend, SchemeCode, app name, and agreement URLs at runtime. The token input is obscured, used only in memory, and cleared after submission. The result only indicates that proof was obtained; it does not display or log the token or create an application session.

Production applications should obtain tokens from their own backend and promptly submit the returned proof for verification. The example contains no usable accounts, SchemeCodes, signatures, or keys, and does not embed authentication tokens through `--dart-define`.

Run `sh tool/check.sh` when maintaining the package. See the [development guide](doc/development.en.md) for formatting rules, toolchains, and platform checks.

## Documentation

- [Android SDK integration](android/SDK.en.md)
- [iOS integration](ios/README.en.md)
- [Server integration](doc/server-integration.en.md)
- [Development and code checks](doc/development.en.md)
- [Pre-release and integration validation](doc/testing.en.md)
- [Changelog](doc/changelog.en.md)

## License

The Flutter bridge source is licensed under Apache-2.0; see [LICENSE](LICENSE). Bundled Alibaba Cloud SDK binaries, carrier components, and resources remain subject to their respective vendor terms and **are not relicensed by the bridge's open-source license**. See [NOTICE.en](NOTICE.en). Using this package still requires enabling the relevant Alibaba Cloud services and complying with their terms.

For number retrieval before checkbox consent, explicitly set `deferConsentToNative: true` and pass the actual checkbox value as `privacyAccepted`. This login-only option opens the number page without granting consent. Native one-click login, SMS sending and submission retain their agreement gates. Registration/reset callers should still check consent before submitting. The option defaults to false, preserving the existing strict initialization behavior.

### Reuse an application SMS form

Set `appSms: true` for login to retain the SDK SMS node while hiding its SMS page. Number switching/fallback completes authentication with `app_sms_ready`; obtain the retained ID from `AliyunFusionAuth.smsSessionId`. This is a UI handoff, not successful authentication, and sends nothing. After explicit consent and a user send action, call `sendSmsCode(sessionId:, phone:, privacyAccepted:)`. Completion requires SDK send success. `submitSmsCode(sessionId:, phone:, code:, privacyAccepted:)` generates a fresh fusion proof for each attempt. Validate it on your backend; a rejected code can be corrected in the same form/session. Always `await cancel()` after successful login or when leaving the flow.

The session ID, actual consent and last successfully sent phone must match. SMS operations time out after 30 seconds; the session expires after about five minutes. Never automatically resend after a timeout. Set `startWithSms: true` alongside `appSms` to prepare an SMS node from an existing manual phone form, then send explicitly. Both options are login-only and default off, so other callers retain native SMS UI. Rebuild the native application.

### Number presentation and SMS transitions

`authenticate(config, onStageChanged: ...)` reports `FusionAuthStage.numberReady` when the carrier authorization page is visible and `FusionAuthStage.smsSwitching` when moving to SMS. Stop the app loading indicator on number presentation while keeping authentication pending for user action. Prepare the SMS form on transition, but wait for `app_sms_ready` before sending. Events are scoped to the request and duplicate or backward notifications cannot restore number loading.

The callback may return a Future; native SMS presentation waits for it before closing. For an inline iOS card, callers can await Flutter `endOfFrame` so the underlying form is painted. Android may still have its Flutter Activity in the background, so do not wait for a resumed frame there. Never await authentication or SMS completion inside the callback. Stage events do not grant consent or confirm login.

Native number-page agreements use size 13 throughout (scaled by `textScale` on iOS cards). Carrier and application protocol titles use Chinese book-title marks. Public SDK styling preserves links and consent behavior without changing the host app's Flutter agreement widgets.

## Retaining the iOS number page during login

Set `retainNumberPage: true` for a login scene. After explicit consent and a login tap, the existing button shows a spinner and “登录中” and blocks duplicate actions. A result with `numberPageRetained` leaves the same number, agreements and page visible during backend verification.

Before navigation, call `snapshotNumberPage()` for the page PNG and Flutter frame, paint it inside the outgoing login route, await `AliyunFusionAuth.cancel()`, then navigate home. Waiting until route disposal can leave native UI above home. Keep snapshots in memory only and dispose decoded images on failure or route disposal; do not persist or cache them. On failure, paint the fallback before awaiting cancellation. Do not cancel immediately after receiving proof or start another authentication while retaining this page. Cancellation, engine detachment and session expiry release views, animation and the SDK. Android and fusion SMS behavior are unaffected.

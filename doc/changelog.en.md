# Changelog

[简体中文](../CHANGELOG.md) | English

## 0.1.7 (2026-10-24)

- Keep the iOS loading button and input shield until native dismissal is confirmed, preventing a label flash or repeated actions while SDK cleanup is pending.

## 0.1.6 (2026-10-24)

- Add `snapshotNumberPage()` for an in-memory PNG and Flutter frame of the retained iOS authorization page.
- Paint it inside the outgoing route, await cancellation, then navigate so native UI cannot remain above home. Dispose decoded images on route exit.
- Snapshots do not restart authentication or change consent, SMS, vendor binaries or Android behavior. Late snapshot responses are rejected after cancellation.

## 0.1.5 (2026-10-24)

- Add opt-in iOS login `retainNumberPage`: return proof while retaining the native authorization page until the caller finishes server verification and navigation, then calls `cancel`.
- Consented number login displays a spinner and “登录中” inside the existing button, preserves the number and agreements, and blocks duplicate actions. Add `FusionAuthStage.authorizing` and `numberPageRetained` on the result.
- Retained pages remain exclusive to their request. Duplicate proof/finish callbacks are ignored; cancellation, engine detachment and session expiry release native views, animation and SDK resources. Default calls, Android and fusion SMS remain compatible.

## 0.1.4 (2026-10-24)

- Use a uniform 13-point native number-page agreement font (still scaled with the iOS card), and wrap carrier and application protocol names in Chinese book-title marks while retaining URLs and consent behavior.
- Apply the SDK's whole-agreement font setting to prefixes and link names. The consuming app's own Flutter agreement widgets are unaffected.

## 0.1.3 (2026-10-24)

- Add optional `onStageChanged` and `FusionAuthStage` to distinguish a visible number page from the SMS transition, so apps can stop number-loading UI while authentication awaits user action.
- Wait for the application stage callback before hiding native SMS presentation, allowing the existing phone form to be prepared without exposing an old loading placeholder.
- Scope stage events to their authentication request and ignore duplicate, backward and stale notifications. Consent, fusion SMS sessions, proof verification and vendor SDK binaries are unchanged.

## 0.1.2 (2026-10-24)

- Correct `phoneInputLabel` to customize only the change-number label and continue SDK phone/code input, SMS delivery, and proof generation without closing the session or returning `phone_input`.
- Preserve the current fusion authentication flow on carrier node failure or SMS entry; successful proof still requires application backend validation.
- Show “本机号码一键登录” only inside the iOS card's button, center the masked number with room for the change-number action, and hide the duplicate heading and service-provider message while retaining carrier agreements.
- Add optional `appSms`, `startWithSms`, `smsSessionId`, `sendSmsCode` and `submitSmsCode` APIs to reuse application SMS forms while the fusion SDK delivers messages and produces server-verifiable proof.
- Retain native SMS sessions across UI handoff and backend code rejection. Complete sends only after SDK success, clean up pending operations on cancellation/timeout, and validate consent, session identity and the successfully sent phone.
- Add login-only `deferConsentToNative` for number retrieval before checkbox consent; login, sending and submission still require explicit agreement.
- Widen consent reminders and use consistent wording. Center the number and hide the service slogan on full-page number authorization as well.
- Native SMS UI remains the default. Rebuild native applications to use app-owned SMS forms. Vendor SDK binaries are unchanged.

## 0.1.1 (2026-10-23)

- Add iOS `FusionAuthLoginCard` with public SDK configuration for card position, colors, and text scaling, preserving the masked number and carrier authorization.
- Add login-only `phoneInputLabel`: return `phone_input` after switching numbers or carrier unavailability so the app can show its own phone verification form.
- Add `alternateLoginLabel` and `emailLoginLabel`, returning `alternative_login` and `email_login` for password or other methods and email code login respectively.
- Close native UI and finish session cleanup before switching methods, without yielding or submitting verification proof.
- Separate the iOS card's password and email entries with a thin vertical divider and measure button widths from their labels; keep agreements below the actions, semibold and left aligned.
- Keep the login button's normal appearance before carrier consent and show a reminder when tapped; let the SDK authorize after consent.
- Update Chinese and English integration guides and regression checks for card layout, cancellation cleanup, alternate entries, and consent interactions.

## 0.1.0

- Initial release of `aliyun_fusion_auth` for Android and iOS.
- Bundle Android Fusion Authentication SDK 1.2.16 and the iOS SDK 1.2.15 distribution (its included framework identifies itself as 1.2.14).
- Add typed configuration and results for login/registration (`100001`) and password reset (`100003`).
- Require explicit application privacy consent and configurable application agreements before SDK initialization.
- Return an opaque verification token for backend validation, with no token logging or simulated authentication results.
- Bound authentication lifetime, close native UI on cancellation, and reject overlapping requests.
- Preserve Android authentication when returning from SMS code entry to change the phone number.
- Package iOS device and simulator XCFramework slices, resource bundles, and the vendor privacy manifest.
- Exclude optional UMeng device/risk components from the default integration.
- Add a manual configuration example, server integration notes, and a device validation checklist.
- Add strict Dart analysis, native formatting rules, and regression checks for timeouts and SDK event handling.

Real-device carrier authentication and the complete backend flow remain to be validated before production use.

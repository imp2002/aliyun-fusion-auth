# Release and integration verification

[简体中文](testing.md) | English

Successful iOS device authentication and backend login have been reported for 0.1.0; the app-owned SMS form and presentation changes in 0.1.2 still require device verification. Bridge tests, static analysis, and simulator builds each cover only their own scope. They cannot replace real-device tests of phone number authentication, SMS billing behavior, or application server verification.

## 0.1.4 native styling verification (2026-10-24)

- Passed 146 iOS session assertions, including the uniform size-13 agreement font, card scaling, nonduplicated book-title marks and unchanged protocol URLs.
- Retains the 0.1.3 loading-stage and handoff fixes. The app's own Flutter agreement components are unchanged; native presentation still needs device verification.

## 0.1.3 local verification record (2026-10-24)

- Passed 22 plugin Dart tests, 144 iOS session assertions, 50 cleanup assertions, 22 Android event assertions and static analysis.
- Northward passed 58 login regressions. An iOS-specific test confirms handoff acknowledges only after Flutter paints; number presentation removes its loading placeholder and stale/duplicate events cannot restore loading.
- Android plugin Java compilation passed. The loading layout and number-switch transition still need device verification; automation sends no real SMS.

## 0.1.2 local verification record (2026-10-24)

- 21 Dart tests, 137 iOS session assertions and 22 Android event assertions passed, covering retained sessions, explicit sending, consent, phone matching, fresh-proof retries and cancellation.
- The consuming Northward app passed 55 regression tests; after adding cleanup retry coverage, all 17 authentication service tests passed. Its unsigned iOS Release build using the local plugin passed.
- Plugin Java sources compiled against Android platform APIs, Flutter embedding and the bundled SDK. No Android APK build or real SMS delivery was performed.
- Vendor binaries were not upgraded. Carrier lookup, SMS delivery, backend validation and presentation on both platforms still require device verification.

## 0.1.1 local verification record (2026-10-23)

- All 18 Dart tests passed, including card arguments, input switching, `alternative_login`, and retry. Strict static analysis passed.
- All 102 iOS native session assertions and 50 cleanup assertions passed, covering card and alternate entries, consent reminders, deferred cleanup, repeated taps, and late proofs. Session tests ran on an iOS simulator.
- Android public custom-view APIs were checked against the bundled AAR and demo, and 22 event assertions passed. Android builds and device UI checks have not run.
- The standalone `example` passed an unsigned iOS Release build, verifying native linking and resource packaging.
- The initial-release records below refer only to 0.1.0.

## 0.1.0 local verification record (2026-10-23)

- On Flutter 3.47.6 / Dart 3.13.5, all 13 Dart tests passed with `flutter test`, including virtual-time coverage of timeouts, successful/failed/unresponsive cancellation, and late callbacks from previous attempts. Strict `flutter analyze` reported no issues.
- The standalone `example` built successfully with `flutter build ios --release --no-codesign`. The output contains the native frameworks and both resource bundles.
- The iOS cleanup adapter passed strict compilation checks for device and simulator targets. Native regression tests cover serialized cancellation, late and duplicate callbacks, and completion ordering.
- `flutter pub publish --dry-run` passed with 0 warnings. This command does not upload or publish the package.
- Android checks covered Java syntax, SDK method signatures, XML/POM files, binary integrity, and 22 event-classification assertions. No APK was built because the local machine does not have the Android SDK.

The code quality review fixed an issue where returning from the Android SMS verification code screen to edit the phone number incorrectly canceled the entire flow.
It also aligned the minimum toolchain declared by the example, which uses a newer template, with Flutter 3.47.6 / Dart 3.13.5.
See the [development guide](development.en.md) for formatting conventions and the common check command.

iOS uses the user-supplied 1.2.15 distribution, whose framework internally identifies itself as 1.2.14. The original binaries are unmodified. The cleanup adapter depends on the specific implementation of the bundled SDK and must be revalidated before upgrading the native SDK. See the [iOS integration guide](../ios/README.en.md).

## Build environment

- Use a Flutter toolchain appropriate for the target platform to run `flutter analyze`, `flutter test`, and example builds.
- On iOS, check the iOS 15.0+ deployment target, CocoaPods integration, device signing, and packaging of the XCFramework and both resource bundles.
- On Android, check the compileSdk 36 environment, packaging of SDK AARs/native libraries and resources, manifest merging, and obfuscation in release builds.
- The example's Bundle ID / applicationId and the actual installed app's signature must match your own Alibaba Cloud scheme. Changing only the display name is insufficient.

## Real-device and server integration tests

| Test | Expected result |
| --- | --- |
| The user has not accepted the app's privacy notice | Do not initialize by default. Login-only `deferConsentToNative` may retrieve a number, but login and SMS operations still require explicit consent |
| The native authentication screen opens for the first time | The app name and agreement links are correct; carrier agreements remain available; the consent checkbox is initially unchecked |
| Login/registration `100001` | Submit the returned credential to the backend; create a login session only after the backend verifies the phone number |
| Password reset `100003` | A target number is required; grant reset permission only after the backend verifies that the number matches the stored target |
| Authentication completes with a different phone number | The backend rejects a password reset for the original target and does not accept the client prefill value as proof |
| The carrier authentication path is unavailable | Follow the console-configured scheme to an available SMS/other subsequent node, or return a final failure |
| An SMS code is incorrect, resent, or times out | The flow allows correction or completion without reporting business success incorrectly |
| The token is expired or invalid | Return a failure; start a new attempt with a fresh token from the backend |
| The user selects the native alternate login entry | Return `alternative_login` after native cleanup; navigate without submitting a proof, and do not automatically reopen on return |
| The user goes back, closes the screen, or the app calls `cancel()` | The current Future completes, the native screen closes, and another attempt can start |
| Repeated taps, navigation during authentication, or foreground/background transitions | No concurrent authentication, unresolved Futures, or old callbacks affecting later attempts |
| No network, poor connectivity, or no SDK callback | Recover after failure or timeout without authorizing the requested operation |
| Replay of the same credential, concurrent submissions, or an expired attempt | The backend rejects reuse and does not perform a sensitive operation more than once |
| Logs and error monitoring | No tokens, AccessKeys, or full phone numbers |

Test with the actual target carriers, SIMs, and network conditions. A simulator cannot prove that carrier phone number retrieval works. If you enable additional risk/scoring nodes, separately verify their component dependencies, user notices, and server-side decisions. The demo only shows “credential obtained; server verification required” and must not be treated as proof that an application login has completed.

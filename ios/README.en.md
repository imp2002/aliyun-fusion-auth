# iOS integration

[简体中文](README.md) | English

This Flutter plugin wraps the original XCFramework from Aliyun's supplied **1.2.15 distribution**. Both embedded framework slices actually report **1.2.14** in `Info.plist` and `getSDKVersion`; the vendor files have not been relabeled or modified. The framework includes arm64 device and arm64/x86_64 simulator slices, its privacy manifest, and the `ATAuthSDK.bundle` and `AlicomCaptcha4.bundle` resources. CocoaPods selects the appropriate slice and embeds the vendor dynamic framework. The minimum iOS version is 15.0.

The bridge code is licensed under Apache-2.0. Aliyun binaries, headers and resources retain the vendor's original terms; the bridge license does not relicense them. See [LICENSE](../LICENSE) and [NOTICE](../NOTICE.en) in the package root.

## Method channel

Channel: `aliyun_fusion_auth`. Plugin class: `AliyunFusionAuthPlugin`.

`authenticate` requires this argument map:

| Argument | Requirement |
| --- | --- |
| `authToken` | Nonempty SDK authorization token obtained from your server |
| `schemeCode` | Nonempty iOS scheme configured for your own app's bundle identifier |
| `sceneId` | `100001` for login/registration, or `100003` for password reset |
| `phoneNumber` | Required for `100003`, optional for `100001` |
| `appName` | Nonempty application display name |
| `termsTitle` | Nonempty terms title, distinct from the privacy title |
| `termsUrl` | Absolute HTTPS URL with a host and no embedded credentials |
| `privacyTitle` | Nonempty privacy policy title |
| `privacyUrl` | Absolute HTTPS URL with a host and no embedded credentials |
| `privacyAccepted` | Boolean `true`, reflecting consent already obtained by your app |

The native layer checks these values before initializing the SDK. Missing, false or non-boolean consent returns `privacy_not_accepted`. Invalid configuration returns `invalid_arguments`. No app name, bundle identifier, scheme code, agreement URL or cloud credential is hardcoded in the bridge. Tokens are not logged or persisted by the bridge, and SDK diagnostic logging is disabled.

The SDK supplies the authentication layout. The app name and supplied agreement titles/URLs are applied to each invocation. Carrier agreements remain under SDK control; the bridge adds the application's agreements and keeps the SDK checkbox unchecked. Callers must obtain app privacy consent before calling this API; setting the argument alone does not provide a consent screen.

Successful native completion returns `{ "verifyToken": "..." }`. This is only an opaque proof. Your server must call Aliyun `VerifyWithFusionAuthToken`, check the resulting phone number and intended operation, then decide whether to log in, register or reset a password. Never treat the native callback as an authenticated account. Cloud AccessKeys belong only on your server.

`cancel` has no arguments. It stops and destroys the active native session and resolves pending authentication with `cancelled`, unless a terminal result already started cleanup. Its Future waits for SDK and UI cleanup; it succeeds immediately when no session is active. Repeated cancellation requests each complete once. Each invocation owns a separate delegate; late callbacks cannot complete a later attempt. Engine detachment also destroys the session.


## Login card and number switching within fusion authentication

Optional `alternateLoginLabel` adds a password or other login entry and returns `alternative_login` after cleanup. Login-only `phoneInputLabel` customizes the change-number button label. The button calls the SDK's public `otherPhoneLogin` method. Number switching, carrier node failures, and SMS entry stay within the current fusion authentication flow; the SDK handles SMS delivery, code input, and proof generation. The backend must validate that proof; the native callback alone does not establish that the code was correct.

`loginCard` uses `AFLoginCard` and public `AlicomFusionNumberAuthModel` configuration to position and theme a native card with a centered masked number, number switching beside it, and password login below. `title` labels only the login button; the separate heading and service-provider message are hidden. See the main README for dimensions and validation. It does not export the masked number or bypass the SDK login button and carrier consent. When switching to password or email login, wait for native cleanup before navigation; late proof after cleanup is rejected.

## Pinned SDK cleanup adapter

The supplied SDK's public `destroy` returns before asynchronous teardown completes. It queues work on a per-instance serial `inputQueue`, then can clear process-wide configuration again from carrier dismissal callbacks. Even the internal `AlicomFusionBusiness.destroy:` completion runs **before** that final shared-state cleanup. Releasing an authentication session immediately, or merely waiting for its input queue, lets an old attempt clear a newly initialized attempt.

`AFSDKCleanup` adapts only this supplied vendor implementation. It checks the runtime version and required method signatures before constructing an authentication handler. It then obtains that instance's business/input queue and creates a subclass only for its carrier business instance, using public Objective-C runtime APIs. It does not replace methods on the vendor's global classes and uses no Apple private APIs.

The adapter serializes carrier cancellation calls on the main queue and waits until each vendor callback has returned. Serializing matters because one carrier animation path stores a single dismissal completion; concurrent dismissals could overwrite it. The no-presented-UI branch is a verified no-op that does not call completion. After public `destroy`, the adapter reaches an input-queue barrier and then the main queue, covering graphical/SMS teardown scheduled by that block, before waiting for all tracked carrier cancellations. Duplicate callbacks are ignored before executing vendor cleanup a second time. The bridge finally waits for actual UIKit dismissal/transition completion. A process-wide session owner prevents overlapping attempts across FlutterEngines until these steps succeed.

This depends on vendor internals and must be re-audited when changing the supplied binaries, even if a replacement reports the same version. The runtime/version/ABI guard returns `unsupported_sdk_version` before starting authentication for an unsupported SDK. An unexpected initialized object graph returns `sdk_cleanup_unavailable`. A cleanup that cannot be confirmed returns `sdk_cleanup_failed` or, after ten seconds, `sdk_cleanup_timeout`; a deadline never authorizes reuse of shared state. Process ownership stays held until cleanup is actually confirmed, so new attempts return `busy` in the meantime. If a vendor callback never arrives, restarting the process is necessary for that exceptional failure.

SHA-256 of the unmodified vendor executables:

| XCFramework slice | SHA-256 |
| --- | --- |
| `ios-arm64` | `a72b393f5bca11b294bc8b5ba7bb22222ad8d1127f2f910b2ce22168411e6b36` |
| `ios-arm64_x86_64-simulator` | `42338568ac066f3c623fa0a599cee42e07a5e3b149bec992ca1a0c95618082c2` |

The arm64 device binary establishes these ordering points: serial queue creation at `0x28238`; destroy enqueue at `0x29d40`; caller completion at `0x29ee0`; later shared-state destruction at `0x2a00c`; carrier dismissal completion at `0x16de4`. These addresses describe the supplied executable, not stable APIs.

## Errors and fallback

- Recoverable SMS node errors reported by the SDK keep its screen available for correction. Completing code input may directly produce a proof; the backend must call `VerifyWithFusionAuthToken` to determine whether the code is correct. Carrier failures advance to the next authentication node configured by your scheme.
- Initialization is bounded to 65 seconds; the full native attempt is bounded to 295 seconds.
- Token refresh requests end the attempt with `auth_token_expired`. Fetch a fresh authorization token from your server before retrying. The synchronous SDK refresh callback never waits for Dart or a network request.
- Only login/registration and password reset are exposed. An unexpected halfway callback is rejected with `unsupported_intermediate_verification`; the bridge never acknowledges intermediate proof without server validation.
- Error details expose SDK error codes and request IDs, not raw carrier payloads or tokens.

## Optional dependencies and testing

UMCommon and UMDevice are not bundled or initialized. Per [Aliyun's iOS integration documentation](https://help.aliyun.com/zh/pnvs/developer-reference/the-ios-client-access-3), those plugins are optional and enable device risk/phone scoring capabilities. Disable scheme nodes that require them unless you separately integrate compatible UMeng frameworks and their initialization. The older UMeng binaries in the supplied SDK distribution do not support arm64 simulators.

The carrier, SMS and graphical verification resources are included. Use the simulator to check builds, bridge validation, cancellation and supported UI behavior. Carrier authentication requires a real device with a SIM and cellular data. Configure both supported scenes and the desired SMS/graphical fallback in your own Aliyun scheme, then validate the full process against your server. The plugin neither provisions an Aliyun scheme nor registers your app's bundle identifier.

Run the native regression checks from the package root on macOS with Xcode:

```sh
sh test/native/run_cleanup_tests.sh
FLUTTER_ROOT=/path/to/flutter sh test/native/run_session_tests.sh booted
```

The first command uses mock vendor classes with the real Objective-C runtime and adapter. It passes 50 assertions covering no UI, one/two cancellation requests, main-queue ordering, delayed/duplicate completions, per-instance interception and completion only once. The second needs a booted iOS Simulator and the Flutter SDK's cached iOS artifacts. It passes 93 assertions against the supplied frameworks: runtime `getSDKVersion = 1.2.14`, accepted ABI, synchronously constructed instance graph, real no-UI destroy, repeated finish/cancel, cross-engine exclusion and deferred/unique Flutter results. It uses empty token/scheme values without installing an authentication delegate; it does not start authentication or send SMS. These checks do not validate real carrier animations, network authentication, fallback UI, or a live Aliyun scheme; verify those on a physical iPhone.

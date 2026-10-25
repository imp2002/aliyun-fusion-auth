# Android SDK integration

[简体中文](SDK.md) | English

The Android implementation uses the supplied, unmodified Alibaba Cloud Fusion
Authentication SDK 1.2.16. The vendor binary remains subject to the vendor's
terms; see the package's [NOTICE](../NOTICE.en) for the license scope.

The bundled artifact is resolved from a local Maven repository inside this
package. It includes the SDK's resources, manifest declarations, consumer
ProGuard rules and native libraries; a separate download or absolute local
filesystem path is not required.

For Flutter add-to-app projects distributed with `flutter build aar`, the plugin
AAR retains a transitive dependency on `dev.aliyunfusionauth.vendor:fusionauth:1.2.16`.
Flutter's generated Maven output does not copy this package's `vendor` repository.
Distribute that repository alongside the generated AAR repository, or publish its
unchanged artifact to a repository available to the host Android build. Configure
the host to resolve both repositories; the generated Flutter repository alone is
not sufficient. This additional AAR distribution path has not been build-tested.

| Artifact | SHA-256 |
| --- | --- |
| `fusionauth-1.2.16.aar` | `286efa126634c92da7fa0b6c22808ed8e27b7a485418ebdc2c4d64534ad33fc4` |

This bridge compiles against Android SDK 36 and supports Android API 21 or later.
The supplied native libraries contain `arm64-v8a`, `armeabi-v7a` and `x86`; they do
not contain `x86_64`. Validate authentication on a supported physical device with
a SIM and mobile data. Both supplied ARM64 libraries use 16 KiB ELF load-segment
alignment.

The bridge does not bundle or initialize Umeng. Ordinary authentication uses the
main SDK. If a host app enables optional Umeng-dependent risk nodes in its cloud
strategy, it must integrate the relevant vendor components, obtain consent and
initialize them itself before authentication. Otherwise disable those optional
nodes in the cloud strategy. The SDK detects the presence of optional components
before using them; consumer rules account for their absence in release builds.

Each authentication call requires explicit consent, an app name and two HTTPS
agreement URLs. The bridge keeps the carrier agreement on the one-click page and
adds the host's agreements. It supports login/registration (`100001`) and password
reset (`100003`); reset also requires the existing phone number. The SDK is
initialized only for an explicit authentication call. Carrier failures continue
to the next configured node, including SMS; switching numbers is not treated as
cancellation. Expired SDK tokens finish with `token_expired`, so the app can obtain
a fresh token from its server and retry.

Authentication returns an opaque `verifyToken`. The host server must verify it
with Alibaba Cloud before logging in, registering or resetting a password. SDK
success alone is not authorization. The bridge does not log tokens or phone
numbers. Cancellation, timeout, activity detachment and engine detachment clean
up the active session and protocol page.

Before a new SDK initialization, the bridge observes SDK 1.2.16's
`AlicomFusionSceneUtil.isHasFinish()` flag without blocking the main thread.
This avoids entering the SDK constructor's busy wait while its previous SMS
activity still needs the main thread to finish destruction. This use of a vendor
implementation detail is tied to the bundled SDK version; verify it again when
upgrading the binary. The wait can be cancelled and is bounded by the normal
initialization timeout.

# Development and Code Checks

[简体中文](development.md) | English

The package's Dart API supports Dart 3.3 / Flutter 3.19 and later. The standalone
example uses newer platform templates and requires Dart 3.13.5 / Flutter 3.47.6
or later. The complete checks currently use the latter versions.

## Code style

- Dart uses `dart format` and the official `flutter_lints`, with strict casts,
  inference, and raw type checks enabled.
- `flutter_lints 4.x` is compatible with the package's declared minimum Dart
  version. Check the SDK constraints when upgrading the lint rules.
- Objective-C uses 2-space indentation, Java uses 4-space indentation, and native
  code has a column limit of 100. The root `.clang-format` defines the formatting
  rules (verified with Apple clang-format 21.0.0). Format only bridge code and
  tests; do not modify the vendor SDK.
- Authentication results contain only credentials that must be verified by the
  backend. Production code must not log tokens, phone numbers, or raw vendor
  errors.
- Error codes and SDK events should reflect the actual authentication flow.
  Distinguish navigation within the UI from the end of authentication.

Run from the package directory:

```sh
dart format lib test example/lib
clang-format -i ios/Classes/*.m ios/Classes/*.h test/native/*.m \
  android/src/main/java/dev/aliyunfusionauth/flutter/*.java test/native/*.java
sh tool/check.sh
```

On macOS, you can use `xcrun clang-format`; the check script locates it
automatically. On other platforms, add `clang-format` to PATH. The checks also
require Flutter, Dart, and a JDK (local validation uses JDK 17). Use
`FLUTTER_BIN`, `DART_BIN`, `JAVAC`, and `JAVA` to specify executable paths.

The script checks shell syntax, formatting, static analysis, Dart tests, and
Android event classification tests in sequence. On macOS, it also runs iOS
cleanup adaptation tests that do not require a simulator. It does not publish
the package.

## GitHub CI and automated releases

`.github/workflows/ci.yml` runs for pushes to `main` and pull requests, and can
also be started manually from Actions. It uses Flutter 3.47.6 from `.fvmrc`,
JDK 17, and clang-format 21.1.8 to run the existing checks, release validation
regression tests, and `flutter pub publish --dry-run`. iOS cleanup tests run
separately on macOS. CI does not replace device builds and authentication tests.

`.github/workflows/release.yml` runs when a `v<version>` tag is pushed. Its commit
must already be on `main`, and the tag must match the version in `pubspec.yaml`.
Maintain the version only in `pubspec.yaml`; Android Gradle and the iOS podspec
read it automatically. After all CI checks pass, the workflow publishes to
pub.dev, then creates a GitHub Release.
Versions with suffixes such as `-beta.1` are marked as prereleases on GitHub.

If `CHANGELOG.md` has a nonempty entry for the version, that entry becomes the
release notes. Otherwise, notes are generated from Git commits since the
previous version tag. CI exports committed sources to a temporary directory,
adds the changelog entry to that package, then validates or publishes it. Only
the package version needs a manual edit; native configurations and translated
changelogs do not need synchronized edits for each release.

Enable GitHub Actions publishing on the package's
[Admin page](https://pub.dev/packages/aliyun_fusion_auth/admin), with repository
`imp2002/aliyun-fusion-auth` and tag pattern `v{{version}}`. The workflow uses
temporary OIDC credentials through the official `dart-lang/setup-dart` action;
no pub.dev token or other publishing secret is needed. See the
[official automated publishing guide](https://dart.dev/tools/pub/automated-publishing).

To release the next version, for example `0.1.8`:

1. Change `version` in `pubspec.yaml` to `0.1.8` and commit to `main`. Optionally
   update `CHANGELOG.md` with custom notes.
2. Wait for CI on `main` to pass.
3. Run `git tag v0.1.8`, then `git push origin v0.1.8`.
4. Confirm both publication jobs complete in the Release workflow on Actions.

Published pub.dev versions cannot be overwritten. Version `0.1.7` is already
published; do not use it to test publication. If pub.dev succeeds but creating
the GitHub Release fails, select **Re-run failed jobs** to retry only the failed
jobs without uploading the package again.

## Platform and publication checks

After starting an iOS simulator, run the tests for the actual SDK runtime and
authentication sessions separately:

```sh
FLUTTER_ROOT=/path/to/flutter sh test/native/run_session_tests.sh booted
```

Run `flutter build ios --release --no-codesign` in the `example` directory to
verify iOS linking and resources. In an environment with the Android SDK
configured, run `flutter build apk --release`; the pure Java tests do not replace
an APK build.

Before publication, run `flutter pub publish --dry-run` in the package directory
and review the file list. See the [validation record](testing.en.md) for the
scope of real carrier authentication, SMS fallback, and backend verification
checks. When upgrading an SDK, also review the implementation dependencies
documented in [iOS cleanup adaptation](../ios/README.en.md) and
[Android SDK integration](../android/SDK.en.md).

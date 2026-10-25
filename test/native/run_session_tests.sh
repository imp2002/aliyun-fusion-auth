#!/bin/sh
set -eu
: "${FLUTTER_ROOT:?Set FLUTTER_ROOT to the Flutter SDK used by the example app}"
package_dir=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
test_dir=$(mktemp -d /private/tmp/aliyun-fusion-session.XXXXXX)
trap 'rm -rf "$test_dir"' EXIT
simulator_id=${1:-booted}
architecture=$(uname -m)
sdk_path=$(xcrun --sdk iphonesimulator --show-sdk-path)
engine_dir="$FLUTTER_ROOT/bin/cache/artifacts/engine/ios/Flutter.xcframework/ios-arm64_x86_64-simulator"
vendor_dir="$package_dir/ios/Frameworks/AlicomFusionAuth.xcframework/ios-arm64_x86_64-simulator"
xcrun --sdk iphonesimulator clang -fobjc-arc -fmodules \
  -target "$architecture-apple-ios15.0-simulator" -isysroot "$sdk_path" \
  -fmodules-cache-path="$test_dir/modules" -F "$engine_dir" -F "$vendor_dir" \
  -framework Foundation -framework UIKit -framework SafariServices \
  -framework Flutter -framework AlicomFusionAuth \
  -Wall -Wextra -Wno-unused-parameter -Werror \
  "-Wl,-rpath,$engine_dir" "-Wl,-rpath,$vendor_dir" \
  "$package_dir/test/native/session_tests.m" \
  "$package_dir/ios/Classes/AFSDKCleanup.m" \
  "$package_dir/ios/Classes/AFLoginCard.m" -o "$test_dir/session_tests"
xcrun simctl spawn "$simulator_id" "$test_dir/session_tests"

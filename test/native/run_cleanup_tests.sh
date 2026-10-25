#!/bin/sh
set -eu
package_dir=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
test_dir=$(mktemp -d /private/tmp/aliyun-fusion-cleanup.XXXXXX)
trap 'rm -rf "$test_dir"' EXIT
xcrun --sdk macosx clang -fobjc-arc -fmodules \
  -fmodules-cache-path="$test_dir/modules" -framework Foundation \
  -Wall -Wextra -Wno-unused-parameter -Werror \
  "$package_dir/test/native/cleanup_tests.m" \
  "$package_dir/ios/Classes/AFSDKCleanup.m" -o "$test_dir/cleanup_tests"
"$test_dir/cleanup_tests"

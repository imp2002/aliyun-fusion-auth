#!/bin/sh
set -eu
package_dir=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
test_dir=$(mktemp -d "${TMPDIR:-/tmp}/aliyun-fusion-events.XXXXXX")
trap 'rm -rf "$test_dir"' EXIT
"${JAVAC:-javac}" -Xlint:all -Werror -d "$test_dir" \
  "$package_dir/android/src/main/java/dev/aliyunfusionauth/flutter/FusionAuthEventPolicy.java" \
  "$package_dir/test/native/FusionAuthEventPolicyTest.java"
"${JAVA:-java}" -cp "$test_dir" dev.aliyunfusionauth.flutter.FusionAuthEventPolicyTest

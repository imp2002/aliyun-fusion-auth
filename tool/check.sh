#!/bin/sh
set -eu
package_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$package_dir"

if command -v clang-format >/dev/null 2>&1; then
  formatter_bin=$(command -v clang-format)
elif command -v xcrun >/dev/null 2>&1; then
  formatter_bin=$(xcrun --find clang-format)
else
  printf '%s\n' 'clang-format is required to check native source formatting.' >&2
  exit 1
fi

for script in tool/*.sh test/native/*.sh; do
  sh -n "$script"
done
"$formatter_bin" --dry-run --Werror \
  ios/Classes/*.m ios/Classes/*.h test/native/*.m \
  android/src/main/java/dev/aliyunfusionauth/flutter/*.java test/native/*.java
"${FLUTTER_BIN:-flutter}" pub get
"${DART_BIN:-dart}" format --output=none --set-exit-if-changed lib test example/lib
"${FLUTTER_BIN:-flutter}" analyze --fatal-infos
"${FLUTTER_BIN:-flutter}" test
sh test/native/run_android_event_tests.sh
if [ "$(uname -s)" = Darwin ]; then
  sh test/native/run_cleanup_tests.sh
fi

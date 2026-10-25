# 开发与代码检查

简体中文 | [English](development.en.md)

包的 Dart API 最低支持 Dart 3.3 / Flutter 3.19。独立示例采用新版平台模板，
需要 Dart 3.13.5 / Flutter 3.47.6 或更新版本。当前完整检查使用后者。

## 代码风格

- Dart 使用 `dart format`、官方 `flutter_lints`，开启严格类型转换、推断和原始泛型检查。
- `flutter_lints 4.x` 与包声明的 Dart 最低版本兼容；升级 lint 时同时核对 SDK 约束。
- Objective-C 使用 2 空格缩进，Java 使用 4 空格缩进，原生代码列宽为 100。
  格式以根目录 `.clang-format` 为准（验证工具为 Apple clang-format 21.0.0），
  仅格式化桥接代码与测试，不修改厂商 SDK。
- 认证结果只返回待服务端核验的凭证。生产代码不打印 Token、手机号或原始供应商错误。
- 错误码和 SDK 事件应体现实际流程语义；区分页面内部导航与认证结束。

在包目录运行：

```sh
dart format lib test example/lib
clang-format -i ios/Classes/*.m ios/Classes/*.h test/native/*.m \
  android/src/main/java/dev/aliyunfusionauth/flutter/*.java test/native/*.java
sh tool/check.sh
```

macOS 上可使用 `xcrun clang-format`。检查脚本自动寻找它；其他平台需将
`clang-format` 加入 PATH。检查同时需要 Flutter、Dart 和 JDK（本地验证使用 JDK 17）。
可以通过 `FLUTTER_BIN`、`DART_BIN`、`JAVAC`、`JAVA` 指定可执行文件路径。

脚本依次检查 shell 语法、格式、静态分析、Dart 测试及 Android 事件分类测试。
macOS 上还会执行不依赖模拟器的 iOS 清理适配测试。它不会发布软件包。

## 平台与发布检查

启动 iOS 模拟器后，另外运行真实 SDK 运行时与会话测试：

```sh
FLUTTER_ROOT=/path/to/flutter sh test/native/run_session_tests.sh booted
```

在 `example` 目录运行 `flutter build ios --release --no-codesign` 验证 iOS 链接和资源。
在配置好 Android SDK 的环境中运行 `flutter build apk --release`；纯 Java 测试不能替代 APK 构建。

发布前在包目录运行 `flutter pub publish --dry-run` 并检查文件清单。
真实运营商认证、短信回退和服务端核验的检查范围见 [验证记录](testing.md)。
涉及 SDK 升级时，还须重审 [iOS 清理适配](../ios/README.md) 和
[Android SDK 集成](../android/SDK.md) 中记录的实现依赖。

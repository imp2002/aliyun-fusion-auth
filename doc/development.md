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

## GitHub CI 与自动发版

`.github/workflows/ci.yml` 在推送 `main`、创建或更新 PR 时运行，也支持在 Actions 页面手动触发。
CI 使用 `.fvmrc` 固定的 Flutter 3.47.6、JDK 17 和 clang-format 21.1.8，运行现有检查、
发布版本校验的回归测试及 `flutter pub publish --dry-run`；iOS 清理测试单独在 macOS 上运行。
CI 不替代下面的真机构建与认证联调。

`.github/workflows/release.yml` 在推送 `v版本号` 标签时触发。标签必须指向 `main` 已包含的提交，
且与 `pubspec.yaml` 中的版本一致。版本号只在 `pubspec.yaml` 中维护，Android Gradle 和
iOS podspec 自动读取它。所有 CI 检查通过后，流水线先发布到 pub.dev，再创建 GitHub Release；
带 `-beta.1` 等后缀的版本会标记为预发布。

若 `CHANGELOG.md` 已有该版本的非空条目，发布时使用手写说明；否则从上一个版本标签以来的
Git 提交记录生成说明。CI 将已提交的源码导出到临时目录，并在待发布包中补全更新日志，
随后校验或发布这个包；仓库文件保持由维护者管理，无需为发版同步修改原生配置或两份更新日志。

pub.dev 需在包的 [Admin 页面](https://pub.dev/packages/aliyun_fusion_auth/admin) 启用 GitHub Actions 自动发布，
仓库设为 `imp2002/aliyun-fusion-auth`，标签模式设为 `v{{version}}`。流水线通过官方
`dart-lang/setup-dart` 使用 OIDC 临时凭证，无需添加 pub.dev Token 或其他发布 Secret。
配置说明见 [官方自动发布文档](https://dart.dev/tools/pub/automated-publishing)。

发布下一个版本（例如 `0.1.8`）：

1. 将 `pubspec.yaml` 的 `version` 改为 `0.1.8` 并提交到 `main`。如需自定义说明，可选更新 `CHANGELOG.md`。
2. 等待 `main` 的 CI 通过。
3. 执行 `git tag v0.1.8`，再执行 `git push origin v0.1.8`。
4. 在 Actions 的 Release 流水线中确认 pub.dev 发布和 GitHub Release 均完成。

已经发布到 pub.dev 的版本不能覆盖；当前 `0.1.7` 已发布，不要用旧版本测试发布流程。
如果 pub.dev 发布成功而 GitHub Release 创建失败，在 Actions 中选择 **Re-run failed jobs**，
只重试失败的作业，避免重复上传已经发布的包。

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

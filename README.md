# aliyun_fusion_auth

简体中文 | [English](README.en.md)

阿里云融合认证 Flutter 插件，使用原生 SDK 的认证页面，向 Dart 返回供业务服务端核验的 `verifyToken`。支持登录/注册和重置密码。

这是面向 Android 和 iOS 的第三方独立 Flutter 插件。项目提供统一的认证 API、原生会话管理及服务端凭证交接，许可范围见 [NOTICE](NOTICE)。

## 当前范围

| 项目 | 0.1.7 |
| --- | --- |
| Android 原生 SDK | 1.2.16；Android API 21+，compileSdk 36 |
| iOS 原生 SDK | 1.2.15 发行包，内含 Framework 标识为 1.2.14；iOS 15.0+；CocoaPods |
| Flutter / Dart | Flutter 3.19+ / Dart 3.3+，实际构建还需满足所用 Flutter 的平台要求 |
| 独立示例工具链 | Flutter 3.47.6+ / Dart 3.13.5+；示例使用新版平台工程模板 |
| 登录与注册 | `FusionAuthScene.login`，场景 `100001` |
| 重置密码 | `FusionAuthScene.resetPassword`，场景 `100003`；必须提供目标手机号 |
| 认证界面 | 原生号码授权页；可选复用应用短信表单；应用名及协议可配置 |
| 成功结果 | 不透明的 `verifyToken`；不是登录态，也不是已核验手机号 |

已收到 iOS 真机认证及服务端登录成功的反馈；0.1.7 的融合短信表单接入及页面切换仍需真机验证。iOS 包含真机和模拟器 XCFramework 切片；模拟器编译通过不代表运营商认证可用。上线前按 [验证清单](doc/testing.md) 在真机和业务服务端完成联调。

插件默认不捆绑或初始化 UMCommon / UMDevice，不提供依赖这些组件的设备风险或手机号评分能力。使用这类方案节点前需自行完成相应集成、告知与同意；否则应在阿里云方案中关闭依赖它们的节点。

## 安装与平台配置

```yaml
dependencies:
  aliyun_fusion_auth: ^0.1.7
```

需要调试插件源码时，可临时将依赖改为指向本地包目录：

```yaml
dependencies:
  aliyun_fusion_auth:
    path: ../aliyun-fusion-auth
```

运行 `flutter pub get`。在阿里云号码认证控制台分别创建 Android 和 iOS 融合认证方案，配置需要的认证节点及场景。Android 包名、安装包签名，iOS Bundle ID，以及每个平台的 SchemeCode 必须与实际安装的应用对应。调试签名与发布签名应分别核对。

iOS 在应用 `ios/Podfile` 中将部署目标设为至少 `15.0`，并保持 Xcode 的 Runner 部署目标一致。SDK、资源 bundle 和隐私清单通过插件的 CocoaPods 配置集成，不要再手动重复添加同一 SDK。详细说明见 [iOS 集成说明](ios/README.md)。Android 需要可构建 compileSdk 36 的 Android SDK/Gradle 环境；库所需权限与 SDK Activity 通过 Manifest 合并引入。

客户端不需要也不得配置 Alibaba Cloud AccessKey。服务端集成是必需部分，见 [服务端接入](doc/server-integration.md)。

## Flutter 调用

以下函数在用户明确同意应用协议与隐私政策后调用。`authToken` 和 `schemeCode` 来自业务服务端为当前平台创建的认证尝试；`termsUrl`、`privacyUrl` 必须是应用自己的 HTTPS 页面。协议标题默认使用“用户协议”和“隐私政策”；如通过 `termsTitle` / `privacyTitle` 自定义，两者必须非空且互不相同。

```dart
import 'package:aliyun_fusion_auth/aliyun_fusion_auth.dart';

Future<FusionAuthResult> collectPhoneProof({
  required String authToken,
  required String schemeCode,
  required String appName,
  required Uri termsUrl,
  required Uri privacyUrl,
  required bool userAcceptedPrivacy,
}) {
  return AliyunFusionAuth.authenticate(
    FusionAuthConfig(
      authToken: authToken,
      schemeCode: schemeCode,
      appName: appName,
      termsUrl: termsUrl,
      privacyUrl: privacyUrl,
      privacyAccepted: userAcceptedPrivacy,
      scene: FusionAuthScene.login,
    ),
  );
}
```

获取 `result.verifyToken` 后，经 HTTPS 提交给业务服务端，与服务端创建的认证尝试关联。只有服务端调用 `VerifyWithFusionAuthToken` 验证通过并完成业务检查后，才能创建登录态、注册账号或重置密码。不要在客户端根据原生成功回调直接登录，也不要把 Token 放入日志、分析事件或 URL。

重置密码时使用：

```dart
final result = await AliyunFusionAuth.authenticate(
  FusionAuthConfig(
    authToken: authTokenFromYourServer,
    schemeCode: schemeCodeFromYourServer,
    appName: yourAppName,
    termsUrl: yourTermsUrl,
    privacyUrl: yourPrivacyUrl,
    privacyAccepted: userAcceptedPrivacy,
    scene: FusionAuthScene.resetPassword,
    phoneNumber: targetPhoneNumber,
  ),
);
// 将 result.verifyToken 及服务端的 attemptId 交给自己的后端。
// 服务端必须比较阿里云核验出的手机号与该尝试绑定的目标手机号。
```

`phoneNumber` 仅用于界面预填或认证目标，当前格式要求为中国大陆 11 位手机号。它不是归属权证明。登录场景也可选择提供，但任何必须匹配的目标都应由服务端保存并核对。

## 直接展示号码登录页

在用户已明确同意应用隐私政策后，可以在进入登录页时调用 `authenticate()`，让 SDK 的号码授权页直接作为登录界面，无需额外放置一个打开授权页的“一键登录”按钮。号码由 SDK 在原生页面展示为脱敏号码；插件不向 Flutter 提供独立的预取号码接口。运营商授权仍需用户在原生页面明确确认，本机认证不可用会按控制台方案走短信等兜底方式。

设置 `FusionAuthConfig(alternateLoginLabel: '密码登录', ...)`，可以在原生号码授权页提供密码登录入口。点击后，插件等待原生页面关闭及会话清理完成，再抛出 `PlatformException(code: 'alternative_login')`；此时应用可导航到密码页，不应提交认证凭证。省略此参数则保持默认页面行为；配置时不能使用空白文字。

应用应保存真实的隐私同意状态。仅在首次进入登录页时自动拉起一次；用户关闭原生页、返回密码页或认证最终失败后，应恢复应用页面并提供手动重试，避免循环弹出。首次未同意时先展示应用协议，不得把 `privacyAccepted` 固定写成 `true`。

## 卡片与融合认证换号

登录场景可配置 `phoneInputLabel: '换号'`，仅自定义换号按钮文案。点击换号后，SDK 继续当前融合认证场景，负责手机号与验证码输入、短信发送与重发以及验证凭证生成；运营商节点失败也会继续控制台编排的后续节点。成功后仍返回 `verifyToken`，由业务后端调用 `VerifyWithFusionAuthToken` 核验。该选项不能用于重置密码场景。

当前修正取消了 0.1.1 中换号时清理会话并返回 `phone_input` 的行为。接入方不应再根据换号操作转入旧短信登录接口；初始化错误或场景最终失败时，可提示用户手动重试或选择其他登录方式。

iOS 可同时配置 `loginCard: FusionAuthLoginCard(...)`：`frame` 是 Flutter 全局逻辑坐标中的卡片矩形，另外传入背景色、主色、文字色、次要文字色和可选 `textScale`（1–1.5）。`title` 是一键登录按钮的文案，默认“本机号码一键登录”；号码在卡片中水平居中，不重复展示标题，并通过 SDK 的 `sloganIsHidden` 隐藏服务商提示。宽度至少 240、高度至少 400，所有坐标必须有限且非负。应在布局稳定且卡片完整可见时取矩形；小屏或放大字体无法容纳时可省略卡片，继续使用 SDK 默认授权页面。

这是通过 SDK 公开 UI 配置定制的原生授权卡片，不是将手机号读取到 Flutter。卡片透明遮罩下保留应用背景，号码右侧显示“换号”，仍由 SDK 展示脱敏号码、处理一键登录和未勾选的运营商协议。`alternateLoginLabel` 可保留底部密码入口。Android 同样保留 SDK 的换号和短信认证流程，继续使用 SDK 页面布局，不应用 iOS 卡片样式。

可选 `emailLoginLabel: '邮箱验证码登录'` 在原生号码页提供邮箱入口，清理后返回 `email_login`；应用自行显示邮箱表单并通过后端发送、校验验证码。该选项仅用于登录场景。iOS 使用 `loginCard` 时，邮箱入口位于密码入口右侧，以细竖线分隔，按钮宽度按文案测量；区域沿用纯色背景和紧凑按钮，协议位于底部。未勾选时按钮保持正常颜色，点击仅提示阅读并勾选下方协议；公开 SDK 复选框事件在勾选后切换到 SDK 登录按钮，SDK 保留最终授权校验。协议内容加粗并左对齐。Android 邮箱入口位于现有原生导航区。

## 取消、异常与重试

```dart
import 'package:flutter/services.dart';
import 'package:aliyun_fusion_auth/aliyun_fusion_auth.dart';

Future<void> cancelPhoneProof() => AliyunFusionAuth.cancel();

Future<FusionAuthResult?> tryAuthenticate(FusionAuthConfig config) async {
  try {
    return await AliyunFusionAuth.authenticate(config);
  } on PlatformException catch (error) {
    if (error.code == 'cancelled') return null;
    rethrow; // 由应用展示适当提示；不要记录完整参数或原始 Token。
  }
}
```

同一时刻只能有一个认证流程。`cancel()` 在空闲状态调用也安全；它关闭当前认证，不会退出业务账号。原生 SDK 负责配置方案内的运营商认证、短信或图形验证页面。可恢复的节点错误由原生流程处理；最终失败会完成 Dart Future 并抛出 `PlatformException`。

| 错误码 | 应用处理 |
| --- | --- |
| `cancelled` | 用户取消；恢复当前页面即可 |
| `email_login` | 原生清理后进入应用邮箱验证表单 |
| `alternative_login` | 用户选择其他登录方式；原生清理完成后导航到对应页面 |
| `privacy_not_accepted` | 先取得明确同意，再发起认证 |
| `busy` | 等待或取消当前认证，不要重复点击创建流程 |
| `invalid_arguments` | 检查 SchemeCode、Token、协议链接、应用名和手机号 |
| `unsupported_platform` | 当前只支持 Android / iOS |
| `auth_token_expired` / `token_expired` | 从服务端获取新 Token，重新开始；不同原生平台返回码不同 |
| `auth_timeout` / `timeout` | 本次尝试已结束，检查网络后重新获取 Token |
| `invalid_result` | 未取得有效凭证，本次不能进入业务成功流程 |
| `unsupported_sdk_version` / `sdk_cleanup_unavailable` | iOS SDK 与固定版本的清理适配不匹配；检查是否重复或手工替换了原生 SDK，修正集成后重新运行 |
| 其他 SDK 错误 | 以失败处理，允许用户重试；可记录脱敏后的错误码与 request ID |

认证最多等待五分钟，随后最多等待三秒取消清理。过期时插件结束本次流程，不在同步原生回调中等待网络续期。不支持换绑手机号等需要中间服务端核验的场景 `100002`，也不暴露 `100004` / `100005`。

## 示例

[example](example/lib/main.dart) 是原生认证交互演示。在示例工程中配置你自己的包标识/签名和控制台方案，然后运行 `flutter run`。运行时输入服务端签发的短期 SDK Token、SchemeCode、应用名和协议链接。Token 输入被遮挡，仅在内存中使用，提交后清空；结果只提示取得凭证，不展示或打印 Token，也不会创建业务登录态。

生产应用应从自己的后端获取 Token，并立即提交返回凭证。示例不内置任何可用账号、SchemeCode、签名或密钥，也不通过 `--dart-define` 嵌入认证 Token。

维护代码时运行 `sh tool/check.sh`，格式规则、工具链与平台检查步骤见 [开发说明](doc/development.md)。

## 文档

- [Android SDK 集成](android/SDK.md)
- [iOS 集成](ios/README.md)
- [服务端接入](doc/server-integration.md)
- [开发与代码检查](doc/development.md)
- [发布前与接入验证](doc/testing.md)
- [更新日志](CHANGELOG.md)

## 许可

Flutter 桥接源代码遵循 Apache-2.0，见 [LICENSE](LICENSE)。随包分发的阿里云 SDK、运营商组件与资源遵循各自供应商条款，**不因桥接代码的开源许可而重新授权**，详见 [NOTICE](NOTICE)。使用本包仍需开通并遵守相关阿里云服务条款。

登录页需要在未勾选时先取号，可显式设置 `deferConsentToNative: true`，并将实际勾选值传入 `privacyAccepted`。这只允许登录场景先展示号码页，不自动勾选协议；一键登录、短信发送和提交仍由 SDK 检查协议。注册/改密调用方仍应在提交前检查自己的勾选状态。默认不启用此选项，原有显式授权行为不变。

### 使用应用现有短信表单

登录配置 `appSms: true` 后，换号/回落到短信节点会隐藏 SDK 短信页面并抛出 `app_sms_ready`，`AliyunFusionAuth.smsSessionId` 返回仍存活的会话 ID。此结果只是切换输入界面，不是认证成功；不会自动发送短信。调用方使用自己的输入框，在用户勾选协议并明确点击时调用 `sendSmsCode(sessionId:, phone:, privacyAccepted:)`；只有 SDK 确认发送成功才完成。`submitSmsCode(sessionId:, phone:, code:, privacyAccepted:)` 为每次提交生成新的融合凭证，交给后端核验。后端拒绝后可继续输入重试，成功或离开流程时必须 `await cancel()`。

会话 ID、实际勾选状态及最后成功发送号码必须匹配。单次短信操作 30 秒超时，整个会话约 5 分钟过期；超时不自动重发。若需从应用手机号表单直接开始，另外设置 `startWithSms: true` 准备短信节点，再显式发送。上述选项仅支持登录场景，默认关闭，其他接入保留原生 SDK 短信界面。需要完整重建原生 App。

### 取号与短信切换状态

`authenticate(config, onStageChanged: ...)` 可监听 `FusionAuthStage.numberReady`（号码授权页已展示）和 `FusionAuthStage.smsSwitching`（正在转入短信）。号码展示后应停止应用取号动画，并保持认证请求等待用户操作；短信切换时可先显示应用表单，但必须等 `app_sms_ready` 后才能发送。通知按请求隔离，重复或逆序事件不会使界面退回取号。

回调可以返回 Future；插件在关闭原生短信界面前等待它完成。iOS 内嵌号码卡片可等待 Flutter 的 `endOfFrame`，确保底层表单已绘制；Android 的 Flutter Activity 可能尚在后台，不能在回调中等待恢复后的帧。回调不得等待认证结果或短信请求，以免阻塞交接。状态事件不表示用户已授权或登录成功。

原生号码页协议统一使用 13 号字（iOS 卡片按 `textScale` 缩放），前缀与各协议名称同字号，运营商协议及应用协议名称均带《书名号》。使用 SDK 公开样式配置，保留协议链接与授权行为，不影响应用自己的 Flutter 协议组件。

## 一键登录期间保留 iOS 页面

登录场景可设置 `retainNumberPage: true`。用户勾选并点击后，原按钮显示“登录中”并拦截重复操作；`authenticate` 返回的 `numberPageRetained` 表示页面仍由当前请求持有。此时继续将凭证交给业务服务端核验，页面和号码、协议保持显示。

跳转前调用 `snapshotNumberPage()` 获取原生页面的 PNG 和 Flutter 坐标，在当前登录路由中显示并等待绘制，然后等待 `AliyunFusionAuth.cancel()` 完成，最后再进入首页。不要等首页出现后才在登录页 `dispose` 里关闭原生卡片，否则它会短暂浮在首页上。快照只在内存中使用，解码图像在失败或路由销毁时释放，不写磁盘或图片缓存。失败时先绘制回退界面，再等待 `cancel()` 清理完成。保留期间不能启动另一个认证请求，不能在收到凭证后立即取消。取消、引擎分离和会话超时会释放视图、动画和 SDK；本选项不改变 Android 或融合短信会话。

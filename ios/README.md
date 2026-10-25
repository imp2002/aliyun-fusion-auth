# iOS 集成

简体中文 | [English](README.en.md)

本 Flutter 插件封装了阿里云提供的 **1.2.15 发行包**中的原始 XCFramework。内含的两个 framework 切片在 `Info.plist` 和 `getSDKVersion` 中实际均报告 **1.2.14**；厂商文件未被重新标记或修改。framework 包含 arm64 真机切片、arm64/x86_64 模拟器切片、隐私清单，以及 `ATAuthSDK.bundle` 和 `AlicomCaptcha4.bundle` 资源。CocoaPods 会选择对应切片并嵌入厂商动态 framework。最低支持 iOS 15.0。

桥接代码采用 Apache-2.0 许可证。阿里云二进制文件、头文件和资源仍遵循厂商原有条款，桥接代码的许可证不改变它们的许可。详见包根目录的 [LICENSE](../LICENSE) 和 [NOTICE](../NOTICE)。

## Method Channel

通道名称：`aliyun_fusion_auth`。插件类名：`AliyunFusionAuthPlugin`。

`authenticate` 需要以下参数映射：

| 参数 | 要求 |
| --- | --- |
| `authToken` | 从服务端获取的非空 SDK 授权 Token |
| `schemeCode` | 为宿主 App 的 Bundle ID 配置的非空 iOS 方案标识 |
| `sceneId` | 登录/注册使用 `100001`，重置密码使用 `100003` |
| `phoneNumber` | `100003` 必填，`100001` 可选 |
| `appName` | 非空的 App 显示名称 |
| `termsTitle` | 非空的用户协议标题，且与隐私政策标题不同 |
| `termsUrl` | 带有主机名、不包含内嵌凭据的 HTTPS 绝对地址 |
| `privacyTitle` | 非空的隐私政策标题 |
| `privacyUrl` | 带有主机名、不包含内嵌凭据的 HTTPS 绝对地址 |
| `privacyAccepted` | 布尔值 `true`，表示 App 已取得用户同意 |

原生层会在初始化 SDK 前检查这些值。用户同意参数缺失、为 false 或不是布尔值时，返回 `privacy_not_accepted`。配置无效时返回 `invalid_arguments`。桥接层未硬编码 App 名称、Bundle ID、方案标识、协议地址或云端凭据，不会记录或持久化 Token，并关闭了 SDK 诊断日志。

认证页面布局由 SDK 提供。每次调用都会应用传入的 App 名称和协议标题、地址。运营商协议仍由 SDK 管理；桥接层添加 App 自身协议，并保持 SDK 协议复选框默认不勾选。调用方必须在调用本 API 前取得 App 隐私授权；仅设置参数并不会提供征求用户同意的页面。

原生认证成功后返回 `{ "verifyToken": "..." }`。它只是一个不透明的凭证。服务端必须调用阿里云 `VerifyWithFusionAuthToken`，核对返回的手机号和预期操作，再决定是否执行登录、注册或重置密码。不能将原生回调直接视为账户已认证。云端 AccessKey 只能保存在服务端。

`cancel` 无需参数。它停止并销毁当前原生会话，并将待完成的认证以 `cancelled` 结束，除非某个最终结果已开始清理。它返回的 Future 会等待 SDK 和界面清理；没有活动会话时立即成功。重复发起的取消请求也会各自完成一次。每次认证调用都持有独立的 delegate，延迟到达的回调无法结束后续认证。FlutterEngine 分离时也会销毁会话。

## 与随包 SDK 绑定的清理适配器

随包 SDK 的公开 `destroy` 方法会在异步清理完成前返回。它先将工作加入每个实例的串行 `inputQueue`，随后还可能在运营商页面关闭回调中再次清理进程级共享配置。即使是内部 `AlicomFusionBusiness.destroy:` 的完成回调，也会在最终共享状态清理**之前**执行。如果立即释放认证会话，或仅等待其输入队列完成，旧认证就可能清掉新认证刚初始化的状态。

`AFSDKCleanup` 仅适配随包提供的这一厂商实现。它会在创建认证处理器前检查运行时版本及所需方法签名，然后获取该实例的 business 对象和输入队列，并通过公开的 Objective-C runtime API，仅为该实例的运营商 business 对象创建子类。它不会替换厂商全局类的方法，也不使用 Apple 私有 API。

适配器在主队列上串行执行运营商取消调用，并等待每个厂商回调返回。串行化是必要的，因为其中一条运营商动画路径只保存一个页面关闭完成回调，并发关闭可能覆盖它。没有已展示界面的分支已确认不执行任何操作，也不会调用完成回调。调用公开 `destroy` 后，适配器先到达输入队列屏障，再进入主队列，以覆盖该任务块安排的图形验证码和短信页面清理，随后等待所有已追踪的运营商取消操作。重复回调会被忽略，避免再次执行厂商清理。最后，桥接层等待 UIKit 页面关闭或转场实际完成。进程级会话占用机制会阻止多个 FlutterEngine 的认证重叠，直到以上步骤成功结束。

此适配器依赖厂商内部实现，更换随包二进制文件时必须重新审查，即使替换文件报告相同版本也不例外。运行时版本和 ABI 检查会在不受支持的 SDK 开始认证前返回 `unsupported_sdk_version`。初始化后的对象结构不符合预期时返回 `sdk_cleanup_unavailable`。无法确认清理成功时返回 `sdk_cleanup_failed`，或在十秒后返回 `sdk_cleanup_timeout`；超时本身不代表共享状态已可安全复用。在实际确认清理完成之前，进程级会话仍保持占用，新认证会返回 `busy`。如果厂商回调始终没有到达，这种异常情况需要重启进程才能恢复。

未经修改的厂商可执行文件 SHA-256：

| XCFramework 切片 | SHA-256 |
| --- | --- |
| `ios-arm64` | `a72b393f5bca11b294bc8b5ba7bb22222ad8d1127f2f910b2ce22168411e6b36` |
| `ios-arm64_x86_64-simulator` | `42338568ac066f3c623fa0a599cee42e07a5e3b149bec992ca1a0c95618082c2` |

arm64 真机二进制文件中的相关执行位置为：串行队列创建 `0x28238`；销毁任务入队 `0x29d40`；调用方完成回调 `0x29ee0`；之后的共享状态销毁 `0x2a00c`；运营商页面关闭完成回调 `0x16de4`。这些地址仅描述随包可执行文件，不是稳定 API。


## 登录卡片与融合认证换号

可选 `alternateLoginLabel` 配置密码等其他登录入口；清理完成后返回 `alternative_login`。登录场景可选 `phoneInputLabel` 自定义换号按钮文案。按钮调用 SDK 公开的 `otherPhoneLogin` 方法；换号、运营商节点失败和进入短信页都保持在当前融合认证流程中，由 SDK 完成短信发送、验证码输入及凭证生成；凭证须交给服务端核验，原生回调本身不代表验证码已通过验证。

`loginCard` 使用 `AFLoginCard` 和公开 `AlicomFusionNumberAuthModel` 配置原生卡片矩形、主题色、居中号码、号码右侧换号和底部密码入口；`title` 仅作为登录按钮文案，并隐藏单独标题和服务商提示，参数及尺寸限制见主 README。卡片不会导出脱敏号码，不改变 SDK 的登录按钮和协议授权机制。切换到密码或邮箱登录时，客户端必须等待原生清理完成再导航，并忽略清理后迟到的认证结果。

## 错误与降级

- SDK 上报可恢复的短信节点错误时，保留原生页面供用户修正；验证码填写完成后可能直接生成凭证，由服务端 `VerifyWithFusionAuthToken` 判断验证码是否正确。运营商认证失败后，会进入方案配置的下一个认证节点。
- 初始化超时为 65 秒；整个原生认证流程的超时为 295 秒。
- SDK 请求刷新 Token 时，以 `auth_token_expired` 结束本次认证。重试前请从服务端获取新的授权 Token。SDK 的同步刷新回调不会等待 Dart 或网络请求。
- 仅开放登录/注册和重置密码。收到意外的中途验证回调时，以 `unsupported_intermediate_verification` 拒绝；未经服务端验证，桥接层不会确认中间凭证。
- 错误详情提供 SDK 错误码和请求 ID，不包含原始运营商响应或 Token。

## 可选依赖与测试

本包不包含也不初始化 UMCommon 和 UMDevice。根据[阿里云 iOS 集成文档](https://help.aliyun.com/zh/pnvs/developer-reference/the-ios-client-access-3)，这些是用于设备风险和手机号评分的可选插件。除非自行集成兼容的友盟 framework 并完成初始化，否则请关闭依赖这些插件的方案节点。所提供 SDK 发行包中的旧版友盟二进制文件不支持 arm64 模拟器。

本包已包含运营商认证、短信认证和图形验证码资源。模拟器可用于检查构建、桥接参数校验、取消操作以及所支持的界面行为。运营商认证需要装有 SIM 卡且可使用蜂窝数据的真机。请在自己的阿里云方案中配置两个受支持场景及所需的短信、图形验证码降级流程，再结合服务端验证完整流程。插件不会代为创建阿里云方案或注册 App 的 Bundle ID。

在安装了 Xcode 的 macOS 上，从包根目录运行原生回归检查：

```sh
sh test/native/run_cleanup_tests.sh
FLUTTER_ROOT=/path/to/flutter sh test/native/run_session_tests.sh booted
```

第一条命令使用模拟厂商类、真实 Objective-C runtime 和实际适配器，通过 50 项断言，覆盖无界面、一次/两次取消请求、主队列执行顺序、延迟或重复回调、按实例拦截以及仅完成一次等情况。第二条命令需要已启动的 iOS Simulator，以及 Flutter SDK 已缓存的 iOS 构建产物。它对随包 framework 执行 93 项断言，覆盖运行时 `getSDKVersion = 1.2.14`、ABI 检查通过、同步构造的实例对象结构、真实的无界面销毁、重复结束/取消、跨 FlutterEngine 互斥，以及 Flutter 结果的延后返回与唯一性。它使用空 Token 和空方案标识，且不安装认证 delegate，不会启动认证或发送短信。这些检查不验证真实运营商动画、网络认证、降级界面或线上阿里云方案；请在 iPhone 真机上验证这些行为。

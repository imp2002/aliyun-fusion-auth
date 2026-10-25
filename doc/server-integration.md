# 服务端接入

简体中文 | [English](server-integration.en.md)

插件只完成客户端原生认证。应用服务端负责向阿里云取得 SDK 鉴权 Token、核验最终凭证，以及决定是否授予业务权限。以下 `/auth/fusion/*` 为建议的**业务接口**，不是插件自动创建的接口，也不是阿里云 OpenAPI 地址。可以新增这些接口，与已有短信接口并行保留。

## 两种 Token

| 名称 | 来源 | 去向 |
| --- | --- | --- |
| `authToken` | 服务端调用 `GetFusionAuthToken` 的成功响应 | `FusionAuthConfig.authToken`，供原生 SDK 鉴权 |
| `verifyToken` | `AliyunFusionAuth.authenticate()` 成功结果 | 服务端调用 `VerifyWithFusionAuthToken`，核验实际号码 |

两者用途不同，不能互换。SchemeCode 是平台方案标识，不是 AccessKey。AccessKey、临时云凭据及请求签名逻辑只应位于服务端，推荐使用云角色或官方 SDK 的凭据链。

## 1. 创建认证尝试

客户端向自己的后端发起 HTTPS 请求，例如：

```http
POST /auth/fusion/attempts
Content-Type: application/json
```

```json
{
  "platform": "iOS",
  "purpose": "login"
}
```

重置密码的请求增加用户输入的目标手机号。服务端应校验、规范化该目标，并把它与 `purpose`、平台及有效期一起保存在本次尝试中，后续不能让客户端随意改写。

服务端根据受控配置选择 SchemeCode 和应用标识，不应透传客户端提交的任意包名、Bundle ID、签名或 SchemeCode。调用阿里云 **Dypnsapi / 2017-05-25 / GetFusionAuthToken**：

```json
{
  "Platform": "iOS",
  "SchemeCode": "<server-configured iOS scheme>",
  "BundleId": "<your registered bundle identifier>",
  "DurationSeconds": 900
}
```

Android 对应参数：

```json
{
  "Platform": "Android",
  "SchemeCode": "<server-configured Android scheme>",
  "PackageName": "<your registered application ID>",
  "PackageSign": "<signature registered for the installed build>",
  "DurationSeconds": 900
}
```

`DurationSeconds` 的接口范围为 900–43200 秒。通过官方服务端 SDK 发起带凭据签名的调用，不要把这些示意参数当成可匿名请求的普通 REST JSON。接口完整定义见 [GetFusionAuthToken 官方文档](https://help.aliyun.com/en/pnvs/developer-reference/api-dypnsapi-2017-05-25-getfusionauthtoken)。

服务端确认请求成功且返回的 SDK Token 非空，再将它与随机的 `attemptId` 返回客户端。例如业务响应可以定义为：

```json
{
  "attemptId": "<server-generated one-use attempt ID>",
  "authToken": "<short-lived SDK token>",
  "schemeCode": "<scheme selected by the server>",
  "expiresAt": "<server-defined attempt expiry>"
}
```

`expiresAt` 是业务尝试的有效期，不必等于阿里云 SDK Token 的完整有效期。以上字段由业务服务端适配，不能假设阿里云原始响应结构与此相同。SDK Token 过期或原生流程终止后，应重新创建尝试并获取新 Token。

## 2. 运行客户端认证

把服务端响应中的 `authToken`、`schemeCode` 传给 `FusionAuthConfig`，选择和 `purpose` 对应的场景。重置密码传入同一目标 `phoneNumber`。应用须先展示自己的协议、隐私政策并取得同意，才调用 `authenticate()`。

成功后只通过 HTTPS 将凭证提交给自己的服务端，不要放在 URL 查询参数中：

```http
POST /auth/fusion/attempts/<attemptId>/verify
Content-Type: application/json
```

```json
{
  "verifyToken": "<opaque token returned by the native SDK>"
}
```

客户端不必提供一个“认证成功”的布尔值，更不能自行声称已核验的手机号。业务服务端应忽略这类不可信断言。

## 3. 向阿里云核验并完成业务操作

服务端调用 **Dypnsapi / 2017-05-25 / VerifyWithFusionAuthToken**，必需参数为：

```json
{
  "VerifyToken": "<submitted verification token>"
}
```

必须同时检查 API 调用成功、`Code == "OK"`、`Success == true`、`Model.VerifyResult == "PASS"`，并取得合法的 `Model.PhoneNumber`。`UNKNOWN`、空号码、网络错误和任何其他失败结果均不能授予业务权限。字段定义见 [VerifyWithFusionAuthToken 官方文档](https://help.aliyun.com/zh/pnvs/developer-reference/api-dypnsapi-2017-05-25-verifywithfusionauthtoken)。

下面为与框架无关的伪代码。`aliyun.call` 表示配置好服务器凭据的官方 SDK 调用；存储、事务和业务函数需要应用实现：

```text
verifyAttempt(attemptId, submittedVerifyToken, caller):
    attempt = atomicallyClaimUnexpiredAttempt(attemptId, caller)
    reject unless attempt exists and is eligible for this operation
    proofHash = SHA256(submittedVerifyToken)
    reject if proofHash was already claimed or consumed
    atomicallyClaimProof(proofHash)

    response = aliyun.call("VerifyWithFusionAuthToken", {
        "VerifyToken": submittedVerifyToken
    })
    reject unless response.Success == true and response.Code == "OK"
    reject unless response.Model.VerifyResult == "PASS"
    phone = normalizeAndValidate(response.Model.PhoneNumber)

    if attempt.purpose == "resetPassword":
        reject unless phone == attempt.savedTargetPhone
        result = issueShortLivedSingleUsePasswordResetGrant(phone, attempt)
    else if attempt.purpose == "login":
        result = createApplicationSessionForVerifiedPhone(phone)
    else:
        reject

    atomicallyConsumeAttemptAndProof(attempt, proofHash, result)
    return result
```

对初始化和核验端点设置频率限制，约束请求体大小，并限制同时进行的尝试。让业务 `attemptId` 有短有效期并绑定调用上下文、操作和目标；使用原子状态转换阻止并发重复兑换，对 `verifyToken` 的摘要做跨尝试去重。失败、超时和重试行为应明确设计，避免重复发放登录态或重置授权。阿里云凭证本身的限制不能替代业务层防重放。

登录应以服务端核验返回的手机号查找账号；重置密码必须和预先保存的目标严格匹配。不要把 `phoneNumber` 预填参数当成号码已匹配的保证。重置授权应为短期、单次且仅允许修改该账号密码，完成后失效。

不要在客户端或服务端日志、错误监控、埋点中记录原始 Token、云凭据或完整手机号。排障时记录脱敏状态、SDK 错误码与阿里云 `RequestId` 即可。不要在本示例之外假定插件已经替你实现上述服务端校验。

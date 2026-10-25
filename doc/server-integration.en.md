# Server integration

[简体中文](server-integration.md) | English

The plugin handles native client authentication only. Your application server is responsible for obtaining an SDK authentication token from Alibaba Cloud, verifying the final credential, and deciding whether to authorize the requested operation. The `/auth/fusion/*` routes below are suggested **application endpoints**. They are neither endpoints created automatically by the plugin nor Alibaba Cloud OpenAPI URLs. You can add them alongside your existing SMS endpoints.

## Two distinct tokens

| Name | Source | Destination |
| --- | --- | --- |
| `authToken` | A successful server-side `GetFusionAuthToken` response | `FusionAuthConfig.authToken`, for native SDK authentication |
| `verifyToken` | A successful `AliyunFusionAuth.authenticate()` result | A server-side `VerifyWithFusionAuthToken` call, to verify the actual phone number |

These tokens serve different purposes and are not interchangeable. SchemeCode identifies a platform-specific authentication scheme; it is not an AccessKey. AccessKeys, temporary cloud credentials, and request-signing logic belong on the server only. Prefer cloud roles or the official SDK's credential chain.

## 1. Create an authentication attempt

The client sends an HTTPS request to your backend, for example:

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

For a password reset, also include the target phone number entered by the user. The server should validate and normalize that number, then store it with the attempt's `purpose`, platform, and expiration. The client must not be able to change the stored target later.

The server selects the SchemeCode and application identity from controlled configuration. Do not forward arbitrary package names, Bundle IDs, signatures, or SchemeCodes supplied by the client. Call Alibaba Cloud **Dypnsapi / 2017-05-25 / GetFusionAuthToken**:

```json
{
  "Platform": "iOS",
  "SchemeCode": "<server-configured iOS scheme>",
  "BundleId": "<your registered bundle identifier>",
  "DurationSeconds": 900
}
```

For Android, use these parameters:

```json
{
  "Platform": "Android",
  "SchemeCode": "<server-configured Android scheme>",
  "PackageName": "<your registered application ID>",
  "PackageSign": "<signature registered for the installed build>",
  "DurationSeconds": 900
}
```

The API allows `DurationSeconds` values from 900 to 43200 seconds. Use the official server SDK to make a credential-signed request. These example parameters are not an ordinary REST JSON payload that can be submitted anonymously. See the [official GetFusionAuthToken documentation](https://help.aliyun.com/en/pnvs/developer-reference/api-dypnsapi-2017-05-25-getfusionauthtoken) for the complete API definition.

After confirming that the request succeeded and returned a nonempty SDK token, the server returns the token and a random `attemptId` to the client. For example, your application response could be:

```json
{
  "attemptId": "<server-generated one-use attempt ID>",
  "authToken": "<short-lived SDK token>",
  "schemeCode": "<scheme selected by the server>",
  "expiresAt": "<server-defined attempt expiry>"
}
```

`expiresAt` is the expiration of the application attempt; it does not have to match the full validity period of the Alibaba Cloud SDK token. Your application server adapts the response to these fields. Do not assume the raw Alibaba Cloud response has the same structure. After an SDK token expires or a native authentication flow ends, create a new attempt and obtain a new token.

## 2. Run client authentication

Pass the server's `authToken` and `schemeCode` to `FusionAuthConfig`, and select the scene corresponding to `purpose`. For a password reset, pass the same target `phoneNumber`. The app must present its own terms and privacy policy and obtain consent before calling `authenticate()`.

On success, submit the credential to your server over HTTPS only. Do not put it in URL query parameters:

```http
POST /auth/fusion/attempts/<attemptId>/verify
Content-Type: application/json
```

```json
{
  "verifyToken": "<opaque token returned by the native SDK>"
}
```

The client does not need to send an “authentication succeeded” boolean and must not assert that a phone number has been verified. Your application server should ignore such untrusted assertions.

## 3. Verify with Alibaba Cloud and complete the operation

The server calls **Dypnsapi / 2017-05-25 / VerifyWithFusionAuthToken** with this required parameter:

```json
{
  "VerifyToken": "<submitted verification token>"
}
```

Require a successful API call, `Code == "OK"`, `Success == true`, and `Model.VerifyResult == "PASS"`, and obtain a valid `Model.PhoneNumber`. An `UNKNOWN` result, an empty phone number, a network error, or any other failure must not authorize the requested operation. See the [official VerifyWithFusionAuthToken documentation](https://help.aliyun.com/zh/pnvs/developer-reference/api-dypnsapi-2017-05-25-verifywithfusionauthtoken) for field definitions.

The following pseudocode is independent of any framework. `aliyun.call` represents an official SDK call configured with server credentials. Your application must implement storage, transactions, and business functions:

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

Apply rate limits to the initialization and verification endpoints, bound request body sizes, and limit concurrent attempts. Give each application `attemptId` a short lifetime and bind it to the caller context, operation, and target. Use atomic state transitions to prevent concurrent redemption, and deduplicate `verifyToken` hashes across attempts. Define failure, timeout, and retry behavior explicitly to avoid issuing multiple login sessions or password-reset grants. Restrictions on Alibaba Cloud credentials do not replace replay protection in your application.

For login, find the account using the phone number returned by server-side verification. For password reset, require an exact match with the previously stored target. Do not treat the `phoneNumber` prefill parameter as a guarantee that the numbers match. A reset grant should be short-lived, single-use, restricted to changing that account's password, and invalidated after use.

Do not record raw tokens, cloud credentials, or full phone numbers in client or server logs, error monitoring, or analytics. For troubleshooting, record redacted status information, SDK error codes, and the Alibaba Cloud `RequestId`. Do not assume that the plugin implements any of the server-side checks described here for you.

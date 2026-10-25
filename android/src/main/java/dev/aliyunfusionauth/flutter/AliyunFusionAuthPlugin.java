package dev.aliyunfusionauth.flutter;

import android.app.Activity;
import android.content.Context;
import android.content.ContextWrapper;
import android.content.Intent;
import android.os.Handler;
import android.os.Looper;
import android.text.SpannableString;
import android.text.Spanned;
import android.text.TextUtils;
import android.text.method.LinkMovementMethod;
import android.text.style.ClickableSpan;
import android.util.TypedValue;
import android.view.Gravity;
import android.view.View;
import android.widget.RelativeLayout;
import android.widget.TextView;

import com.alicom.fusion.auth.AlicomFusionAuthCallBack;
import com.alicom.fusion.auth.AlicomFusionAuthUICallBack;
import com.alicom.fusion.auth.AlicomFusionBusiness;
import com.alicom.fusion.auth.AlicomFusionLog;
import com.alicom.fusion.auth.HalfWayVerifyResult;
import com.alicom.fusion.auth.config.AlicomFusionSceneUtil;
import com.alicom.fusion.auth.error.AlicomFusionEvent;
import com.alicom.fusion.auth.numberauth.FusionNumberAuthModel;
import com.alicom.fusion.auth.smsauth.AlicomFusionInputView;
import com.alicom.fusion.auth.smsauth.AlicomFusionVerifyCodeView;
import com.alicom.fusion.auth.token.AlicomFusionAuthToken;
import com.alicom.fusion.auth.upsms.AlicomFusionUpSMSView;
import com.mobile.auth.gatewayauth.AuthRegisterViewConfig;
import com.mobile.auth.gatewayauth.Constant;

import java.util.Collections;
import java.util.HashMap;
import java.util.Map;
import java.util.UUID;
import java.net.URI;
import java.net.URISyntaxException;

import io.flutter.embedding.engine.plugins.FlutterPlugin;
import io.flutter.embedding.engine.plugins.activity.ActivityAware;
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding;
import io.flutter.plugin.common.MethodCall;
import io.flutter.plugin.common.MethodChannel;

/** A short-lived SDK session; only the server can turn its proof into a login. */
public final class AliyunFusionAuthPlugin
        implements FlutterPlugin, MethodChannel.MethodCallHandler, ActivityAware {
    private static final long AUTH_TIMEOUT_MS = 45_000;
    private static final long SESSION_TIMEOUT_MS = 290_000;
    // The vendor SDK keeps process-wide state, including the current scene.
    // Flutter engines must not initialize independent concurrent SDK sessions.
    private static Session activeSession;
    private final Handler main = new Handler(Looper.getMainLooper());
    private MethodChannel channel;
    private Context context;
    private Activity activity;
    private Session session;

    private static final class Session {
        final MethodChannel.Result result;
        final String sceneId;
        String phoneNumber;
        final String appName;
        final String termsTitle;
        final String termsUrl;
        final String privacyTitle;
        final String privacyUrl;
        final String alternateLoginLabel;
        final String phoneInputLabel;
        final String emailLoginLabel;
        AlicomFusionBusiness business;
        Runnable authTimeout;
        Runnable sessionTimeout;
        Runnable sdkReadyCheck;
        boolean sceneStarted;
        boolean switchingNumber;
        boolean appSms;
        boolean startWithSms;
        boolean originalReplied;
        boolean smsReady;
        boolean smsHandoffScheduled;
        String stageRequestId;
        String smsSessionId;
        String smsOperation;
        String smsRequestedPhone;
        String smsSentPhone;
        AlicomFusionVerifyCodeView smsView;
        Activity smsActivity;
        MethodChannel.Result smsReply;
        Runnable smsTimeout;

        Session(MethodChannel.Result result, String sceneId, String phoneNumber, String appName,
                String termsTitle, String termsUrl, String privacyTitle, String privacyUrl,
                String alternateLoginLabel, String phoneInputLabel, String emailLoginLabel) {
            this.result = result;
            this.sceneId = sceneId;
            this.phoneNumber = phoneNumber;
            this.appName = appName;
            this.termsTitle = termsTitle;
            this.termsUrl = termsUrl;
            this.privacyTitle = privacyTitle;
            this.privacyUrl = privacyUrl;
            this.alternateLoginLabel = alternateLoginLabel;
            this.phoneInputLabel = phoneInputLabel;
            this.emailLoginLabel = emailLoginLabel;
        }
    }

    @Override
    public void onAttachedToEngine(FlutterPluginBinding binding) {
        context = binding.getApplicationContext();
        channel = new MethodChannel(binding.getBinaryMessenger(), "aliyun_fusion_auth");
        channel.setMethodCallHandler(this);
        // SDK construction and initialization intentionally happen only in authenticate.
    }

    @Override
    public void onMethodCall(MethodCall call, MethodChannel.Result result) {
        if ("authenticate".equals(call.method)) {
            authenticate(call, result);
        } else if ("cancel".equals(call.method)) {
            fail(session, "cancelled", "已取消手机号认证", null);
            result.success(null);
        } else if ("sendSmsCode".equals(call.method) || "submitSmsCode".equals(call.method)) {
            handleSmsCommand(call, result);
        } else {
            result.notImplemented();
        }
    }

    private void authenticate(MethodCall call, MethodChannel.Result result) {
        if (session != null || activeSession != null) {
            result.error("busy", "手机号认证正在进行中", null);
            return;
        }
        boolean nativeConsent = Boolean.TRUE.equals(call.argument("deferConsentToNative"))
                && "100001".equals(argument(call, "sceneId"));
        if (!Boolean.TRUE.equals(call.argument("privacyAccepted")) && !nativeConsent) {
            result.error("privacy_not_accepted", "请先阅读并勾选同意下方协议", null);
            return;
        }
        if (activity == null || activity.isFinishing() || activity.isDestroyed()) {
            result.error("no_activity", "当前页面无法发起手机号认证，请重试", null);
            return;
        }
        String authToken = argument(call, "authToken");
        String schemeCode = argument(call, "schemeCode");
        String sceneId = argument(call, "sceneId");
        String phoneNumber = argument(call, "phoneNumber");
        String appName = argument(call, "appName");
        String termsTitle = argument(call, "termsTitle");
        String termsUrl = argument(call, "termsUrl");
        String privacyTitle = argument(call, "privacyTitle");
        String privacyUrl = argument(call, "privacyUrl");
        Object alternateLoginValue = call.argument("alternateLoginLabel");
        String alternateLoginLabel = argument(call, "alternateLoginLabel");
        Object phoneInputValue = call.argument("phoneInputLabel");
        String phoneInputLabel = argument(call, "phoneInputLabel");
        Object emailLoginValue = call.argument("emailLoginLabel");
        String emailLoginLabel = argument(call, "emailLoginLabel");
        if (authToken.isEmpty() || schemeCode.isEmpty() || appName.isEmpty() || termsTitle.isEmpty()
                || privacyTitle.isEmpty() || !isHttpsUrl(termsUrl) || !isHttpsUrl(privacyUrl)
                || (alternateLoginValue != null
                        && (!(alternateLoginValue instanceof String)
                                || alternateLoginLabel.isEmpty()))
                || (Boolean.TRUE.equals(call.argument("appSms"))
                        && !("100001".equals(sceneId) || "100003".equals(sceneId)))
                || (Boolean.TRUE.equals(call.argument("startWithSms"))
                        && !Boolean.TRUE.equals(call.argument("appSms")))
                || !("100001".equals(sceneId) || "100003".equals(sceneId))
                || (phoneInputValue != null
                        && (!(phoneInputValue instanceof String) || phoneInputLabel.isEmpty()
                                || !"100001".equals(sceneId)))
                || (emailLoginValue != null
                        && (!(emailLoginValue instanceof String) || emailLoginLabel.isEmpty()
                                || !"100001".equals(sceneId)))
                || ("100003".equals(sceneId) && !phoneNumber.matches("1[3-9][0-9]{9}"))) {
            result.error("invalid_arguments", "手机号认证参数不完整，请重新发起认证", null);
            return;
        }
        Session current = new Session(result, sceneId, phoneNumber, appName, termsTitle, termsUrl,
                privacyTitle, privacyUrl, alternateLoginLabel, phoneInputLabel, emailLoginLabel);
        current.appSms = Boolean.TRUE.equals(call.argument("appSms"))
                && ("100001".equals(sceneId) || "100003".equals(sceneId));
        current.startWithSms = current.appSms && Boolean.TRUE.equals(call.argument("startWithSms"));
        current.stageRequestId = argument(call, "stageRequestId");
        session = current;
        activeSession = current;
        current.authTimeout = () -> fail(current, "timeout", "手机号认证初始化超时，请重试", null);
        current.sessionTimeout = () -> fail(current, "timeout", "手机号认证已超时，请重试", null);
        main.postDelayed(current.authTimeout, AUTH_TIMEOUT_MS);
        main.postDelayed(current.sessionTimeout, SESSION_TIMEOUT_MS);
        initializeWhenReady(current, schemeCode, authToken);
    }

    private void initializeWhenReady(Session current, String schemeCode, String authToken) {
        if (session != current)
            return;
        try {
            // SDK 1.2.16's constructor spins while isHasFinish() is false. Its
            // SMS activities set this flag from onDestroy, so entering that spin
            // on the main thread immediately after cancellation can block the
            // very callback needed to finish cleanup. Observe the pinned SDK's
            // actual completion flag without blocking Android's main looper.
            // The existing auth timeout and cancel() also cover this wait.
            if (!AlicomFusionSceneUtil.getInstance().isHasFinish()) {
                current.sdkReadyCheck = () -> initializeWhenReady(current, schemeCode, authToken);
                main.postDelayed(current.sdkReadyCheck, 50);
                return;
            }
            current.sdkReadyCheck = null;
            AlicomFusionLog.setLogEnable(false);
            // Do not bundle or automatically initialize optional Umeng components.
            // Hosts that use Umeng risk nodes must supply and initialize them after
            // obtaining their own consent, as described in the SDK documentation.
            AlicomFusionBusiness.useSDKSupplyUMSDK(false, "");
            current.business = new AlicomFusionBusiness();
            AlicomFusionAuthToken token = new AlicomFusionAuthToken();
            token.setAuthToken(authToken);
            current.business.initWithToken(context, schemeCode, token);
            // initWithToken constructs the SDK's internal proxy; registering a
            // callback before initialization throws inside this SDK version.
            current.business.setAlicomFusionAuthCallBack(callback(current));
            AlicomFusionLog.setLogEnable(false);
            current.business.setProtocolAction("com.fusion.auth");
            current.business.adapterPageShape(true);
        } catch (RuntimeException | LinkageError error) {
            fail(current, "sdk_init_failed", "手机号认证初始化失败，请稍后重试", null);
        }
    }

    private AlicomFusionAuthCallBack callback(Session current) {
        return new AlicomFusionAuthCallBack() {
            @Override
            public AlicomFusionAuthToken onSDKTokenUpdate() {
                // Never block an SDK callback waiting for Dart/network. A fresh request
                // obtains a new short-lived server token and constructs a new session.
                main.post(() -> {
                    fail(current, "token_expired", "认证凭证已过期，请重新发起认证", null);
                });
                return new AlicomFusionAuthToken();
            }

            @Override
            public void onSDKTokenAuthSuccess() {
                main.post(() -> {
                    if (session != current || current.sceneStarted)
                        return;
                    main.removeCallbacks(current.authTimeout);
                    if (activity == null || activity.isFinishing() || activity.isDestroyed()) {
                        fail(current, "cancelled", "已取消手机号认证", null);
                        return;
                    }
                    current.sceneStarted = true;
                    try {
                        current.business.startSceneWithTemplateId(
                                activity, current.sceneId, uiCallback(current));
                    } catch (RuntimeException | LinkageError error) {
                        fail(current, "sdk_start_failed", "无法打开手机号认证页面，请重试", null);
                    }
                });
            }

            @Override
            public void onSDKTokenAuthFailure(
                    AlicomFusionAuthToken token, AlicomFusionEvent event) {
                main.post(() -> {
                    fail(current, "token_auth_failed", "认证凭证校验失败，请重新发起认证", event);
                });
            }

            @Override
            public void onVerifySuccess(String token, String nodeName, AlicomFusionEvent event) {
                main.post(() -> {
                    if (session != current)
                        return;
                    if (current.smsReady) {
                        if ("verify".equals(current.smsOperation)) {
                            if (TextUtils.isEmpty(token))
                                smsError(current, "invalid_result", "未取得认证凭证，请重试");
                            else
                                resolveSms(current, Collections.singletonMap("verifyToken", token));
                        }
                        return;
                    }
                    if (TextUtils.isEmpty(token)) {
                        fail(current, "invalid_result", "未取得手机号认证结果，请重试", event);
                    } else {
                        release(current);
                        if (!current.originalReplied) {
                            current.originalReplied = true;
                            current.result.success(Collections.singletonMap("verifyToken", token));
                        }
                    }
                });
            }

            @Override
            public void onHalfWayVerifySuccess(String nodeName, String token,
                    AlicomFusionEvent event, HalfWayVerifyResult result) {
                // Half-way verification belongs to the unsupported change-number scene;
                // never accept an intermediate proof as a completed authentication.
                main.post(() -> {
                    fail(current, "unsupported_scene", "当前认证场景暂不支持，请重新发起认证",
                            event);
                });
            }

            @Override
            public void onVerifyFailed(AlicomFusionEvent event, String nodeName) {
                main.post(() -> {
                    if (session != current)
                        return;
                    if (isCancellation(current, event)) {
                        fail(current, "cancelled", "已取消手机号认证", event);
                        return;
                    }
                    if (current.smsReady) {
                        smsError(current, "sms_failed", "短信认证失败，请稍后重试");
                        return;
                    }
                    // Carrier failures must advance the configured fusion flow, e.g.
                    // to SMS. Only onTemplateFinish represents an exhausted flow.
                    try {
                        current.business.continueSceneWithTemplateId(current.sceneId, false);
                    } catch (RuntimeException error) {
                        fail(current, "verification_failed", "手机号认证失败，请稍后重试", event);
                    }
                });
            }

            @Override
            public void onTemplateFinish(AlicomFusionEvent event) {
                main.post(() -> {
                    boolean cancelled = isCancellation(current, event);
                    fail(current, cancelled ? "cancelled" : "verification_failed",
                            cancelled ? "已取消手机号认证" : "手机号认证未完成，请重新发起认证",
                            event);
                });
            }

            @Override
            public void onAuthEvent(AlicomFusionEvent event) {
                // Dispatch outside the SDK event notification to avoid reentrant SDK
                // calls. Switching to another number (410009) is not cancellation.
                main.post(() -> {
                    if (session != current || event == null)
                        return;
                    if (current.smsReady && "send".equals(current.smsOperation)
                            && "500007".equals(event.getErrorCode())) {
                        // SDK reports success before updating its send token, and
                        // may still emit failure for a malformed response. Drain
                        // that callback turn before acknowledging the app send.
                        main.post(() -> {
                            if (session == current && "send".equals(current.smsOperation)) {
                                current.smsSentPhone = current.smsRequestedPhone;
                                resolveSms(current, null);
                            }
                        });
                    } else if ("410009".equals(event.getErrorCode())) {
                        current.switchingNumber = true;
                        if (current.appSms)
                            notifyStage(current, "smsSwitching", null);
                    } else if ("400003".equals(event.getErrorCode()) && !current.startWithSms) {
                        notifyStage(current, "numberReady", null);
                    } else if (FusionAuthEventPolicy.cancelsFromAuthEvent(event.getErrorCode(),
                                       event.getInnerCode(), current.switchingNumber)) {
                        fail(current, "cancelled", "已取消手机号认证", event);
                    }
                });
            }

            @Override
            public String onGetPhoneNumberForVerification(String nodeId, AlicomFusionEvent event) {
                return current.phoneNumber;
            }

            @Override
            public void onVerifyInterrupt(AlicomFusionEvent event) {
                // Loading, invalid input and an unchecked agreement pause a node;
                // the SDK UI remains available so the user can correct the input.
                main.post(() -> {
                    if (session != current)
                        return;
                    if (isCancellation(current, event)) {
                        fail(current, "cancelled", "已取消手机号认证", event);
                    } else if (current.smsReady && event != null
                            && !"900003".equals(event.getErrorCode())
                            && !"900004".equals(event.getErrorCode())) {
                        smsError(current, "sms_failed", "请检查手机号或验证码后重试");
                    }
                });
            }
        };
    }

    private AlicomFusionAuthUICallBack uiCallback(Session current) {
        return new AlicomFusionAuthUICallBack() {
            @Override
            public void onPhoneNumberVerifyUICustomView(
                    String templateId, String nodeId, FusionNumberAuthModel model) {
                if (session != current || context == null)
                    return;
                if (current.appSms && current.startWithSms) {
                    current.switchingNumber = true;
                    main.post(() -> {
                        if (session == current)
                            model.otherPhoneLogin();
                    });
                    return;
                }
                model.getBuilder()
                        .setNavText(current.alternateLoginLabel.isEmpty()
                                        ? current.appName + " · 手机号认证"
                                        : current.appName)
                        .setNavTextSizeDp(17)
                        .setNavTextColor(0xFF17191D)
                        .setNavColor(0xFFFFFFFF)
                        .setStatusBarColor(0xFFFFFFFF)
                        .setLogBtnText("100001".equals(current.sceneId) ? "本机号码一键登录"
                                                                          : "本机号码一键认证")
                        .setLogBtnTextSizeDp(16)
                        .setLogBtnTextColor(0xFFFFFFFF)
                        .setLogBtnHeight(50)
                        .setLogBtnMarginLeftAndRight(30)
                        .setSloganHidden(true)
                        .setLogoHidden(true)
                        .setNumberLayoutGravity(Gravity.CENTER_HORIZONTAL)
                        .setNumberFieldOffsetX(0)
                        .setNumberSizeDp(20)
                        .setNumberColor(0xFF17191D)
                        // iOS renders "+86 156****9798" as one centered
                        // label; Android draws the country prefix and the
                        // masked number as sibling views in one row. A 20dp
                        // number keeps both on one line without overlap.
                        // Vertical rhythm mirrors the iOS login card:
                        // number at 18, button at 80, entries at 142,
                        // agreement pinned to the bottom. Offsets are dp and
                        // measured below the nav bar, so the extra top margin
                        // keeps the number clear of the title.
                        .setNumFieldOffsetY(64)
                        .setLogBtnOffsetY(126)
                        .setSwitchOffsetY(190)
                        .setSwitchAccTextSizeDp(13)
                        .setSwitchAccHidden("100003".equals(current.sceneId))
                        // Reset scene renders the SDK's default "更多登录方式"
                        // as the switch entry; it duplicates the custom
                        // title-bar entries and is hidden there. Login keeps
                        // "使用其他手机号认证" for the SMS fallback.
                        // Agreement checkbox right under the button, mirroring
                        // the app's own form order.
                        .setPrivacyOffsetY("100003".equals(current.sceneId) ? 150 : 240)
                        .setSwitchAccText(current.phoneInputLabel.isEmpty()
                                        ? "使用其他手机号认证"
                                        : current.phoneInputLabel)
                        .setAppPrivacyOne(protocolTitle(current.termsTitle), current.termsUrl)
                        .setAppPrivacyTwo(protocolTitle(current.privacyTitle), current.privacyUrl)
                        .setVendorPrivacyPrefix("《")
                        .setVendorPrivacySuffix("》")
                        .setPrivacyTextSizeDp(13)
                        .setPrivacyBefore("我已阅读并同意")
                        .setPrivacyState(false)
                        .setCheckboxHidden(false)
                        .setPrivacyAlertIsNeedShow(true)
                        .setPrivacyAlertTitleContent("请先阅读并勾选同意下方协议")
                        .setPrivacyAlertTitleTextSize(15)
                        .setPrivacyAlertCornerRadiusArray(new int[] {16, 16, 16, 16})
                        .setPrivacyAlertTitleBackgroundColor(0xFFFFFFFF)
                        .setPrivacyAlertContentBackgroundColor(0xFFFFFFFF)
                        .setPrivacyAlertMaskAlpha(0.4f)
                        .setPrivacyAlertContentAlignment(Gravity.CENTER)
                        .setPrivacyAlertCloseBtnShow(false)
                        .setPrivacyAlertBtnTextSize(15)
                        .setPrivacyAlertBtnTextColor(0xFFFFFFFF)
                        .setPrivacyAlertBtnWidth(120)
                        .setPrivacyAlertBtnHeigth(44)
                        .setPrivacyAlertBtnHorizontalMargin(24)
                        .setPrivacyAlertBtnVerticalMargin(24)
                        .setPrivacyAlertWidth(Math.min(420,
                                Math.max(0,
                                        (int) (context.getResources()
                                                        .getDisplayMetrics()
                                                        .widthPixels
                                                / context.getResources()
                                                        .getDisplayMetrics()
                                                        .density)
                                                - 48)))
                        .setProtocolAction("com.fusion.auth")
                        .setPackageName(context.getPackageName());
                if (!current.alternateLoginLabel.isEmpty() || !current.emailLoginLabel.isEmpty()) {
                    configureAlternateLogin(model, current);
                }
            }

            @Override
            public void onSMSCodeVerifyUICustomView(String templateId, String nodeId,
                    boolean autoInput, AlicomFusionVerifyCodeView view) {
                if (current.appSms) {
                    view.getRootRl().setVisibility(View.INVISIBLE);
                    main.post(() -> handoffSms(current, view));
                    return;
                }
                main.post(() -> {
                    if (session != current)
                        return;
                    if (view.getTitleContentTV() != null) {
                        view.getTitleContentTV().setText(current.appName + " · 手机号认证");
                    }
                    AlicomFusionInputView input = view.getInputView();
                    if (!autoInput && input != null && input.getInputNumberET() != null
                            && !current.phoneNumber.isEmpty()
                            && TextUtils.isEmpty(input.getInputNumberET().getText())) {
                        // The default login strategy disables SDK auto-fill;
                        // populate the editable field without replacing user input.
                        input.getInputNumberET().setText(current.phoneNumber);
                        input.getInputNumberET().setSelection(current.phoneNumber.length());
                    }
                    if (input != null && input.getAgreePrivacy() != null) {
                        input.getAgreePrivacy().setChecked(false);
                    }
                    if (input != null && input.getPrivacyTV() != null) {
                        configurePrivacy(input.getPrivacyTV(), current);
                    }
                });
            }

            @Override
            public void onSMSSendVerifyUICustomView(String templateId, String nodeId,
                    AlicomFusionUpSMSView view, String receivePhoneNumber, String verifyCode) {
                main.post(() -> {
                    if (session == current && view.getTitleContentTV() != null) {
                        view.getTitleContentTV().setText(current.appName + " · 手机号认证");
                    }
                });
            }
        };
    }

    private void handoffSms(Session current, AlicomFusionVerifyCodeView view) {
        if (session != current || current.smsReady || current.smsHandoffScheduled)
            return;
        current.smsHandoffScheduled = true;
        notifyStage(current, "smsSwitching", () -> completeSmsHandoff(current, view));
    }

    private void notifyStage(Session current, String stage, Runnable completion) {
        if (session != current)
            return;
        if (channel == null || TextUtils.isEmpty(current.stageRequestId)) {
            if (completion != null)
                completion.run();
            return;
        }
        Map<String, Object> args = new HashMap<>();
        args.put("requestId", current.stageRequestId);
        args.put("stage", stage);
        channel.invokeMethod("authStageChanged", args, new MethodChannel.Result() {
            private void done() {
                if (completion != null)
                    main.post(() -> {
                        if (session == current)
                            completion.run();
                    });
            }
            @Override
            public void success(Object value) {
                done();
            }
            @Override
            public void error(String code, String message, Object details) {
                done();
            }
            @Override
            public void notImplemented() {
                done();
            }
        });
    }

    private void completeSmsHandoff(Session current, AlicomFusionVerifyCodeView view) {
        if (session != current || current.smsReady)
            return;
        Context viewContext = view.getRootRl().getContext();
        while (viewContext instanceof ContextWrapper && !(viewContext instanceof Activity)) {
            Context base = ((ContextWrapper) viewContext).getBaseContext();
            if (base == viewContext)
                break;
            viewContext = base;
        }
        if (!(viewContext instanceof Activity) || activity == null || activity.isFinishing()) {
            fail(current, "sms_ui_unavailable", "无法返回短信输入页面，请重试", null);
            return;
        }
        current.smsView = view;
        current.smsActivity = (Activity) viewContext;
        // Keep the SDK Activity alive behind the existing Flutter Activity: its
        // onDestroy releases the SMS manager needed by the public custom UI APIs.
        if (current.smsActivity != activity) {
            current.smsActivity.setVisible(false);
            Intent intent = new Intent(activity, activity.getClass());
            intent.addFlags(Intent.FLAG_ACTIVITY_REORDER_TO_FRONT | Intent.FLAG_ACTIVITY_SINGLE_TOP
                    | Intent.FLAG_ACTIVITY_NO_ANIMATION);
            activity.startActivity(intent);
            current.smsActivity.overridePendingTransition(0, 0);
        }
        current.smsReady = true;
        current.smsSessionId = UUID.randomUUID().toString();
        current.originalReplied = true;
        current.result.error("app_sms_ready", "请输入手机号",
                Collections.singletonMap("sessionId", current.smsSessionId));
    }

    private void handleSmsCommand(MethodCall call, MethodChannel.Result result) {
        Session current = session;
        if (current == null || !current.smsReady || current.smsView == null
                || !current.smsSessionId.equals(argument(call, "sessionId"))) {
            result.error("sms_session_expired", "短信认证已过期，请重新获取验证码", null);
            return;
        }
        if (!Boolean.TRUE.equals(call.argument("privacyAccepted"))) {
            result.error("privacy_not_accepted", "请先阅读并勾选同意下方协议", null);
            return;
        }
        boolean sending = "sendSmsCode".equals(call.method);
        String phone = argument(call, "phone");
        String code = argument(call, "code");
        if (!phone.matches("1[3-9][0-9]{9}")
                || (!sending
                        && (!code.matches("[0-9]{4,8}") || !phone.equals(current.smsSentPhone)))) {
            result.error("invalid_arguments", "请为当前手机号获取验证码后再提交", null);
            return;
        }
        if (current.smsReply != null) {
            result.error("busy", "短信认证正在进行，请稍候", null);
            return;
        }
        current.smsReply = result;
        current.smsOperation = sending ? "send" : "verify";
        if (sending)
            current.smsSentPhone = null;
        current.smsRequestedPhone = phone;
        current.phoneNumber = phone;
        current.smsTimeout = () -> fail(current, "timeout", "短信认证超时，请重新获取验证码", null);
        main.postDelayed(current.smsTimeout, 30_000);
        try {
            AlicomFusionInputView input = current.smsView.getInputView();
            if (input != null) {
                if (input.getAgreePrivacy() != null)
                    input.getAgreePrivacy().setChecked(true);
                if (input.getInputNumberET() != null)
                    input.getInputNumberET().setText(phone);
            }
            if (sending)
                current.smsView.verifyCodeBtnClick(phone);
            else
                current.smsView.submitVerifyCodeBtnClick(phone, code);
        } catch (RuntimeException | LinkageError error) {
            fail(current, "sms_failed", "短信认证失败，请重新获取验证码", null);
        }
    }

    private MethodChannel.Result takeSmsReply(Session current) {
        MethodChannel.Result reply = current.smsReply;
        current.smsReply = null;
        current.smsOperation = null;
        current.smsRequestedPhone = null;
        if (current.smsTimeout != null)
            main.removeCallbacks(current.smsTimeout);
        current.smsTimeout = null;
        return reply;
    }

    private void resolveSms(Session current, Object value) {
        MethodChannel.Result reply = takeSmsReply(current);
        if (reply != null)
            reply.success(value);
    }

    private void smsError(Session current, String code, String message) {
        MethodChannel.Result reply = takeSmsReply(current);
        if (reply != null)
            reply.error(code, message, null);
    }

    private void configureAlternateLogin(FusionNumberAuthModel model, Session current) {
        Context viewContext = activity != null ? activity : context;
        TextView measure = new TextView(viewContext);
        measure.setTextSize(TypedValue.COMPLEX_UNIT_SP, 14);
        int emailWidth = current.emailLoginLabel.isEmpty()
                ? 0
                : (int) Math.ceil(measure.getPaint().measureText(current.emailLoginLabel))
                        + Math.round(24 * viewContext.getResources().getDisplayMetrics().density);
        if (!current.alternateLoginLabel.isEmpty())
            configureLoginEntry(
                    model, current, current.alternateLoginLabel, "alternative_login", emailWidth);
        if (!current.emailLoginLabel.isEmpty())
            configureLoginEntry(model, current, current.emailLoginLabel, "email_login", 0);
    }

    private void configureLoginEntry(FusionNumberAuthModel model, Session current, String label,
            String resultCode, int endOffset) {
        Context viewContext = activity != null ? activity : context;
        TextView button = new TextView(viewContext);
        float density = viewContext.getResources().getDisplayMetrics().density;
        int padding = Math.round(12 * density);
        RelativeLayout.LayoutParams params = new RelativeLayout.LayoutParams(
                RelativeLayout.LayoutParams.WRAP_CONTENT, RelativeLayout.LayoutParams.MATCH_PARENT);
        params.addRule(RelativeLayout.ALIGN_PARENT_END);
        params.setMarginEnd(Math.round(8 * density) + endOffset);
        button.setLayoutParams(params);
        button.setGravity(Gravity.CENTER);
        button.setPadding(padding, 0, padding, 0);
        button.setMinHeight(Math.round(48 * density));
        button.setText(label);
        button.setTextSize(TypedValue.COMPLEX_UNIT_SP, 14);
        button.setTextColor(FusionNumberAuthModel.DEFAULT_NAV_TEXT_COLOR);
        button.setClickable(true);
        button.setFocusable(true);
        button.setTextColor(0xFF0092FF); // App theme blue (os_color).
        TypedValue background = new TypedValue();
        if (viewContext.getTheme().resolveAttribute(
                    android.R.attr.selectableItemBackgroundBorderless, background, true)
                && background.resourceId != 0) {
            button.setBackgroundResource(background.resourceId);
        }
        // Keep the SDK's other-phone/SMS fallback intact. A separate navigation
        // action ends this session before Flutter opens another login method.
        model.addAuthRegistViewConfig("aliyun_fusion_auth_" + resultCode,
                new AuthRegisterViewConfig.Builder()
                        .setView(button)
                        .setRootViewId(AuthRegisterViewConfig.RootViewId.ROOT_VIEW_ID_TITLE_BAR)
                        .setCustomInterface(ignored
                                -> main.post(()
                                                     -> fail(current, resultCode,
                                                             "已选择其他登录方式", null)))
                        .build());
    }

    private void configurePrivacy(TextView view, Session current) {
        String prefix = "我已阅读并同意";
        String text = prefix + current.termsTitle + "和" + current.privacyTitle;
        SpannableString agreement = new SpannableString(text);
        addProtocolLink(agreement, prefix.length(), current.termsTitle, current.termsUrl);
        addProtocolLink(agreement, prefix.length() + current.termsTitle.length() + 1,
                current.privacyTitle, current.privacyUrl);
        view.setText(agreement);
        view.setMovementMethod(LinkMovementMethod.getInstance());
    }

    private void addProtocolLink(SpannableString text, int start, String name, String url) {
        text.setSpan(new ClickableSpan() {
            @Override
            public void onClick(View widget) {
                Intent intent = new Intent(widget.getContext(), FusionAuthProtocolActivity.class);
                intent.putExtra(Constant.PROTOCOL_WEB_VIEW_URL, url);
                intent.putExtra(Constant.PROTOCOL_WEB_VIEW_NAME, name);
                widget.getContext().startActivity(intent);
            }
        }, start, start + name.length(), Spanned.SPAN_EXCLUSIVE_EXCLUSIVE);
    }

    private static String protocolTitle(String title) {
        return title.startsWith("《") && title.endsWith("》") ? title : "《" + title + "》";
    }

    private static String argument(MethodCall call, String name) {
        Object value = call.argument(name);
        return value instanceof String ? ((String) value).trim() : "";
    }

    private static boolean isHttpsUrl(String value) {
        try {
            URI uri = new URI(value);
            return "https".equalsIgnoreCase(uri.getScheme()) && !TextUtils.isEmpty(uri.getHost())
                    && uri.getUserInfo() == null;
        } catch (URISyntaxException error) {
            return false;
        }
    }

    private static boolean isCancellation(Session current, AlicomFusionEvent event) {
        return event != null
                && FusionAuthEventPolicy.isCancellation(
                        event.getErrorCode(), event.getInnerCode(), current.switchingNumber);
    }

    private void fail(Session current, String code, String message, AlicomFusionEvent event) {
        if (current == null || session != current)
            return;
        Map<String, String> details = new HashMap<>();
        if (event != null) {
            // Do not expose vendor messages, carrier payloads, tokens or phone numbers.
            details.put("sdkCode", event.getErrorCode());
            details.put("requestId", event.getRequestId());
        }
        smsError(current, code, message);
        release(current);
        if (!current.originalReplied) {
            current.originalReplied = true;
            current.result.error(code, message, details);
        }
    }

    private void release(Session current) {
        session = null; // Ignore callbacks emitted while the SDK closes its activities.
        main.removeCallbacks(current.authTimeout);
        main.removeCallbacks(current.sessionTimeout);
        if (current.sdkReadyCheck != null) {
            main.removeCallbacks(current.sdkReadyCheck);
            current.sdkReadyCheck = null;
        }
        if (current.smsTimeout != null)
            main.removeCallbacks(current.smsTimeout);
        FusionAuthProtocolActivity.closeOpenPage();
        if (current.business != null) {
            try {
                if (current.sceneStarted)
                    current.business.stopSceneWithTemplateId(current.sceneId);
            } catch (RuntimeException | LinkageError ignored) {
                // A running node may reject stop; destory releases it regardless.
            }
            try {
                current.business.destory();
            } catch (RuntimeException | LinkageError ignored) {
                // Completion must still reach Dart even if the SDK is already closed.
            }
            current.business = null;
        }
        if (current.smsActivity != null && !current.smsActivity.isFinishing())
            current.smsActivity.finish();
        current.smsActivity = null;
        current.smsView = null;
        current.smsSessionId = null;
        if (activeSession == current)
            activeSession = null;
    }

    @Override
    public void onAttachedToActivity(ActivityPluginBinding binding) {
        activity = binding.getActivity();
    }

    @Override
    public void onReattachedToActivityForConfigChanges(ActivityPluginBinding binding) {
        activity = binding.getActivity();
    }

    @Override
    public void onDetachedFromActivityForConfigChanges() {
        onDetachedFromActivity();
    }

    @Override
    public void onDetachedFromActivity() {
        fail(session, "cancelled", "已取消手机号认证", null);
        activity = null;
    }

    @Override
    public void onDetachedFromEngine(FlutterPluginBinding binding) {
        fail(session, "cancelled", "已取消手机号认证", null);
        channel.setMethodCallHandler(null);
        channel = null;
        context = null;
    }
}

package dev.aliyunfusionauth.flutter;

import android.app.Activity;
import android.app.Dialog;
import android.content.Context;
import android.content.ContextWrapper;
import android.content.Intent;
import android.content.res.Configuration;
import android.graphics.Color;
import android.graphics.Rect;
import android.graphics.Typeface;
import android.graphics.drawable.ColorDrawable;
import android.graphics.drawable.GradientDrawable;
import android.os.Handler;
import android.os.Looper;
import android.text.Spannable;
import android.text.SpannableString;
import android.text.SpannableStringBuilder;
import android.text.Spanned;
import android.text.TextUtils;
import android.text.method.LinkMovementMethod;
import android.text.style.ClickableSpan;
import android.util.TypedValue;
import android.view.Gravity;
import android.view.MotionEvent;
import android.view.View;
import android.view.ViewGroup;
import android.view.Window;
import android.view.WindowManager;
import android.widget.CompoundButton;
import android.widget.Toast;
import android.widget.ImageView;
import android.widget.LinearLayout;
import android.widget.TextView;

import androidx.appcompat.content.res.AppCompatResources;

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
import com.mobile.auth.gatewayauth.AuthRegisterXmlConfig;
import com.mobile.auth.gatewayauth.AuthUIControlClickListener;
import com.mobile.auth.gatewayauth.Constant;
import com.mobile.auth.gatewayauth.PhoneNumberAuthHelper;
import com.mobile.auth.gatewayauth.PreLoginResultListener;
import com.mobile.auth.gatewayauth.TokenResultListener;
import com.mobile.auth.gatewayauth.ui.AbstractPnsViewDelegate;

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
        final String greeting;
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
                String alternateLoginLabel, String phoneInputLabel, String emailLoginLabel,
                String greeting) {
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
            this.greeting = greeting;
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
        } else if ("probeHeadless".equals(call.method)) {
            probeHeadless(call, result);
        } else if ("capabilities".equals(call.method)) {
            Map<String, Object> capabilities = new HashMap<>();
            // The bundled AAR currently exposes Activity presentation only.
            capabilities.put("flutterHosted", false);
            capabilities.put("reason", "vendor_view_api_unavailable");
            result.success(capabilities);
        } else if ("cancel".equals(call.method)) {
            fail(session, "cancelled", "已取消手机号认证", null);
            result.success(null);
        } else if ("sendSmsCode".equals(call.method) || "submitSmsCode".equals(call.method)) {
            handleSmsCommand(call, result);
        } else {
            result.notImplemented();
        }
    }

    /**
     * Probes the vendor pre-login API without starting the fusion scene. This
     * is intentionally diagnostic: it never returns a carrier token or proof
     * and never changes the production authenticate path.
     */
    private void probeHeadless(MethodCall call, MethodChannel.Result result) {
        if (activity == null || activity.isFinishing()) {
            result.error("no_activity", "Android Activity is unavailable", null);
            return;
        }
        final long timeoutMs =
                Math.max(5_000L, Math.min(60_000L, number(call.argument("timeoutMs"), 15_000L)));
        final Map<String, Object> response = new HashMap<>();
        response.put("startedActivity", false);
        response.put("returnedCarrierToken", false);
        response.put("returnedFusionProof", false);
        response.put("method", "accelerateLoginPage");
        final boolean[] replied = {false};
        Runnable timeout = () -> {
            if (replied[0])
                return;
            replied[0] = true;
            response.put("supported", false);
            response.put("reason", "prelogin_timeout");
            result.success(response);
        };
        main.postDelayed(timeout, timeoutMs);
        try {
            final PhoneNumberAuthHelper helper = PhoneNumberAuthHelper.getInstance(
                    activity.getApplicationContext(), new TokenResultListener() {
                        @Override
                        public void onTokenSuccess(String token) {
                            if (replied[0])
                                return;
                            replied[0] = true;
                            main.removeCallbacks(timeout);
                            response.put("returnedCarrierToken", token != null && !token.isEmpty());
                            response.put("supported", false);
                            response.put("reason", "unexpected_auth_callback");
                            result.success(response);
                        }

                        @Override
                        public void onTokenFailed(String code) {
                            if (replied[0])
                                return;
                            replied[0] = true;
                            main.removeCallbacks(timeout);
                            response.put("supported", false);
                            response.put("reason", "auth_callback_failed");
                            result.success(response);
                        }
                    });
            helper.accelerateLoginPage(
                    PhoneNumberAuthHelper.SERVICE_TYPE_LOGIN, new PreLoginResultListener() {
                        @Override
                        public void onTokenSuccess(String token) {
                            if (replied[0])
                                return;
                            replied[0] = true;
                            main.removeCallbacks(timeout);
                            response.put("returnedCarrierToken", token != null && !token.isEmpty());
                            response.put("supported", false);
                            response.put("reason", "prelogin_only");
                            result.success(response);
                        }

                        @Override
                        public void onTokenFailed(String code, String message) {
                            if (replied[0])
                                return;
                            replied[0] = true;
                            main.removeCallbacks(timeout);
                            response.put("supported", false);
                            response.put("reason", "prelogin_failed");
                            result.success(response);
                        }
                    });
        } catch (Throwable error) {
            if (replied[0])
                return;
            replied[0] = true;
            main.removeCallbacks(timeout);
            response.put("supported", false);
            response.put("reason", "prelogin_exception");
            result.success(response);
        }
    }

    private void authenticate(MethodCall call, MethodChannel.Result result) {
        if (session != null || activeSession != null) {
            result.error("busy", "手机号认证正在进行中", null);
            return;
        }
        String presentation = argument(call, "presentation");
        if ("flutterHosted".equals(presentation)) {
            result.error("unsupported_hosted_mode",
                    "当前 Android 融合认证 SDK 未提供可嵌入 Flutter 的授权视图", null);
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
        String greeting = argument(call, "greeting");
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
                privacyTitle, privacyUrl, alternateLoginLabel, phoneInputLabel, emailLoginLabel,
                greeting);
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
                configureNumberPage(model, current);
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

    private GradientDrawable loginButtonBackground() {
        GradientDrawable background = new GradientDrawable();
        background.setColor(Color.rgb(0, 146, 255));
        background.setCornerRadius(
                14 * (context == null ? 1f : context.getResources().getDisplayMetrics().density));
        return background;
    }

    // Vertical rhythm of the content block, in dp relative to the top of the
    // masked number. The SDK only accepts fixed offsets, so the block's screen
    // position is computed from the screen height before the page is created
    // (see numberPageLayout); the overlay then follows the vendor views'
    // measured bounds (see alignOverlay).
    // Space the removed greeting used; kept so the other views stay put.
    private static final int BLOCK_TOP_ABOVE_NUMBER_DP = 64;
    private static final int LOGIN_BELOW_NUMBER_DP = 56;
    private static final int LOGIN_HEIGHT_DP = 50;
    private static final int OTHER_BELOW_LOGIN_DP = 16;
    private static final int PRIVACY_BELOW_NUMBER_DP = 190;
    // Block top to the bottom of a two-line agreement.
    private static final int BLOCK_HEIGHT_DP = BLOCK_TOP_ABOVE_NUMBER_DP + 230;
    // Block centre as a fraction of the screen height; slightly above the
    // middle reads as centred and leaves room for the keyboard-free bottom.
    private static final float BLOCK_CENTER_RATIO = 0.45f;
    private static final int CLOSE_ROW_DP = 60;
    private static final int BOTTOM_RESERVE_DP = 64;
    // The SDK body starts below the status bar plus a reserved title area,
    // even with the nav bar hidden (about 100dp in total on a measured
    // device). An error here shifts the vendor views uniformly; the overlay
    // still follows them because it reads their real bounds.
    private static final int RESERVED_TITLE_DP = 56;

    /** SDK offsets for one page, computed before the vendor page is created. */
    private static final class NumberPageLayout {
        final int bodyTopDp;
        final int numberOffsetDp;
        final int loginOffsetDp;
        final int privacyOffsetDp;

        NumberPageLayout(int bodyTopDp, int numberOffsetDp) {
            this.bodyTopDp = bodyTopDp;
            this.numberOffsetDp = numberOffsetDp;
            this.loginOffsetDp = numberOffsetDp + LOGIN_BELOW_NUMBER_DP;
            this.privacyOffsetDp = numberOffsetDp + PRIVACY_BELOW_NUMBER_DP;
        }
    }

    private static NumberPageLayout numberPageLayout(Context context) {
        android.util.DisplayMetrics metrics = context.getResources().getDisplayMetrics();
        float density = metrics.density;
        int screenDp = Math.round(metrics.heightPixels / density);
        int statusDp = 24;
        int statusId =
                context.getResources().getIdentifier("status_bar_height", "dimen", "android");
        if (statusId != 0)
            statusDp = Math.round(context.getResources().getDimensionPixelSize(statusId) / density);
        int bodyTopDp = statusDp + RESERVED_TITLE_DP;
        // Number top on screen that puts the block centre at the target ratio,
        // kept below the close button row and above the bottom reserve.
        int numberTop = Math.round(
                screenDp * BLOCK_CENTER_RATIO - BLOCK_HEIGHT_DP / 2f + BLOCK_TOP_ABOVE_NUMBER_DP);
        int minNumberTop = statusDp + CLOSE_ROW_DP + BLOCK_TOP_ABOVE_NUMBER_DP;
        int maxNumberTop =
                screenDp - BOTTOM_RESERVE_DP - BLOCK_HEIGHT_DP + BLOCK_TOP_ABOVE_NUMBER_DP;
        numberTop = Math.max(minNumberTop, Math.min(numberTop, maxNumberTop));
        return new NumberPageLayout(bodyTopDp, Math.max(0, numberTop - bodyTopDp));
    }

    /**
     * The SDK must keep drawing the masked number, login button and carrier
     * agreement. Everything else is hidden and replaced by an app-owned XML
     * overlay registered through the vendor's public addAuthRegisterXmlConfig.
     */
    private void configureNumberPage(FusionNumberAuthModel model, Session current) {
        Context viewContext = activity != null ? activity : context;
        NumberPageLayout layout = numberPageLayout(viewContext);
        boolean isDark = isDarkMode(viewContext);
        // Light mode: dark text on white background
        // Dark mode: light text on dark background
        int backgroundColor = isDark ? 0xFF111214 : 0xFFFFFFFF;
        int numberColor = isDark ? 0xFFF6F6F6 : 0xFF17191D;
        int privacyTextColor = isDark ? 0xFFCCCCCC : 0xFF68707D;
        model.getBuilder()
                .setNavHidden(true)
                .setStatusBarColor(backgroundColor)
                .setLightColor(isDark)
                .setBottomNavColor(backgroundColor)
                .setLogoHidden(true)
                .setSloganHidden(true)
                // The overlay draws "其他手机号登录"; hide the
                // vendor "登录" title, switch footer and account switch so
                // nothing is duplicated or overlaps.
                .hiddenLoginText(true)
                .hiddenSwtichLogin(true)
                .setSwitchAccHidden(true)
                .hiddenNumberCountry(false)
                .setNumberLayoutGravity(Gravity.CENTER_HORIZONTAL)
                .setNumberFieldOffsetX(0)
                .setNumFieldOffsetY(layout.numberOffsetDp)
                // "+86" is resized to match at runtime (matchCountryCodeSize).
                .setNumberSizeDp(20)
                .setNumberColor(numberColor)
                .setLogBtnText("100001".equals(current.sceneId) ? "本机号码一键登录"
                                                                  : "本机号码一键认证")
                .setLogBtnTextSizeDp(16)
                .setLogBtnTextColor(0xFFFFFFFF)
                .setLogBtnBackgroundDrawable(loginButtonBackground())
                .setLogBtnHeight(50)
                .setLogBtnMarginLeftAndRight(30)
                .setLogBtnLayoutGravity(Gravity.CENTER_HORIZONTAL)
                .setLogBtnOffsetY(layout.loginOffsetDp)
                // The app shows its own themed consent dialog instead.
                .setLogBtnToastHidden(true)
                .setPrivacyAlertIsNeedShow(false)
                .setAppPrivacyOne(protocolTitle(current.termsTitle), current.termsUrl)
                .setAppPrivacyTwo(protocolTitle(current.privacyTitle), current.privacyUrl)
                .setVendorPrivacyPrefix("《")
                .setVendorPrivacySuffix("》")
                .setAppPrivacyColor(privacyTextColor, 0xFF0092FF)
                .setPrivacyOneColor(0xFF0092FF)
                .setPrivacyTwoColor(0xFF0092FF)
                .setPrivacyOperatorColor(0xFF0092FF)
                .setPrivacyTextSizeDp(13)
                .setPrivacyBefore("我已阅读并同意")
                .setPrivacyState(false)
                .setCheckboxHidden(false)
                .setCheckBoxWidth(18)
                .setCheckBoxHeight(18)
                .setCheckedImgDrawable(AppCompatResources.getDrawable(
                        viewContext, R.drawable.aliyun_fusion_auth_checkbox_checked))
                .setUncheckedImgDrawable(AppCompatResources.getDrawable(
                        viewContext, R.drawable.aliyun_fusion_auth_checkbox_unchecked))
                .setProtocolLayoutGravity(Gravity.CENTER_HORIZONTAL)
                .setPrivacyMargin(30)
                .setPrivacyOffsetY(layout.privacyOffsetDp)
                .setProtocolAction("com.fusion.auth")
                .setPackageName(context.getPackageName());

        model.addAuthRegisterXmlConfig(new AuthRegisterXmlConfig.Builder()
                        .setLayout(R.layout.aliyun_fusion_auth_number_page,
                                new AbstractPnsViewDelegate() {
                                    @Override
                                    public void onViewCreated(View view) {
                                        bindNumberPage(view, model, current, layout);
                                    }
                                })
                        .build());

        // Show toast when user tries to login without checking the consent checkbox
        model.setUiClickListener(new AuthUIControlClickListener() {
            @Override
            public void onClick(String code, Context ctx, String jsonStr) {
                android.util.Log.d(
                        "AliyunFusionAuth", "UI click: code=" + code + ", json=" + jsonStr);
                // code 700002 = login button clicked without consent
                if ("700002".equals(code)) {
                    Toast.makeText(ctx, "请先阅读并勾选协议", Toast.LENGTH_SHORT).show();
                }
            }
        });
    }

    private void bindNumberPage(
            View root, FusionNumberAuthModel model, Session current, NumberPageLayout layout) {
        // Update theme-dependent colors initially
        updateThemeColors(root);

        TextView otherNumber = root.findViewById(R.id.aliyun_fusion_auth_other_number);
        if (otherNumber != null) {
            otherNumber.setTextColor(0xFF0092FF);
            otherNumber.setOnClickListener(ignored -> {
                if (session != current)
                    return;
                if (!current.alternateLoginLabel.isEmpty()) {
                    // Close the vendor page and let Flutter open the app's own
                    // password/email login page.
                    fail(current, "alternative_login", "已选择其他登录方式", null);
                } else {
                    // Without an app login page, keep the SDK's SMS fallback.
                    current.switchingNumber = true;
                    model.otherPhoneLogin();
                }
            });
        }
        root.getViewTreeObserver().addOnGlobalLayoutListener(() -> {
            alignOverlay(root, layout);
            // Update background color on every layout (responds to theme changes)
            boolean isDark = isDarkMode(root.getContext());
            int backgroundColor = isDark ? 0xFF111214 : 0xFFFFFFFF;
            root.setBackgroundColor(backgroundColor);
        });
        View closeButton = root.findViewById(R.id.aliyun_fusion_auth_close);
        if (closeButton != null) {
            closeButton.setOnClickListener(
                    ignored -> fail(current, "cancelled", "已取消手机号认证", null));
        }
    }

    /**
     * Updates background and phone number colors based on current theme.
     */
    private void updateThemeColors(View root) {
        boolean isDark = isDarkMode(root.getContext());

        // Set page background color
        int backgroundColor = isDark ? 0xFF111214 : 0xFFFFFFFF;
        root.setBackgroundColor(backgroundColor);

        // Phone number color is updated in alignOverlay (runs on every layout)
    }

    /**
     * Places the overlay from the vendor views' real bounds, because the SDK
     * body starts below a reserved title area whose height depends on the
     * device. Runs on every layout pass; translation and alpha do not
     * request another layout.
     */
    private static void alignOverlay(View root, NumberPageLayout layout) {
        View page = root.getRootView();
        float density = root.getResources().getDisplayMetrics().density;
        // hiddenSwtichLogin/hiddenLoginText do not remove these vendor views
        // from fusion_custom_body; the overlay replaces both.
        hideVendorView(page, com.alicom.fusion.auth.R.id.tv_otherNumber);
        hideVendorView(page, com.alicom.fusion.auth.R.id.tv_logintext);

        int[] rootLocation = new int[2];
        root.getLocationOnScreen(rootLocation);
        Rect visible = new Rect();
        root.getWindowVisibleDisplayFrame(visible);
        int statusInset = Math.max(0, visible.top - rootLocation[1]);
        root.findViewById(R.id.aliyun_fusion_auth_close).setTranslationY(statusInset);

        matchCountryCodeSize(page);

        // Update phone number color based on current theme (runs on every layout)
        View numberContainer = page.findViewById(com.alicom.fusion.auth.R.id.authsdk_number_view);
        if (numberContainer != null) {
            boolean isDark = isDarkMode(page.getContext());
            int numberColor = isDark ? 0xFFF6F6F6 : 0xFF17191D;
            // The container is a RelativeLayout, find TextView children
            if (numberContainer instanceof android.view.ViewGroup) {
                android.view.ViewGroup group = (android.view.ViewGroup) numberContainer;
                for (int i = 0; i < group.getChildCount(); i++) {
                    View child = group.getChildAt(i);
                    if (child instanceof TextView) {
                        ((TextView) child).setTextColor(numberColor);
                    }
                }
            }
        }

        // Fallback uses the same estimate that produced the SDK offsets.
        int bodyTop = Math.round(layout.bodyTopDp * density);
        int numberTop = numberContainer != null && numberContainer.getHeight() > 0
                ? vendorTop(
                          page, com.alicom.fusion.auth.R.id.authsdk_number_view, rootLocation[1], 0)
                : bodyTop + Math.round(layout.numberOffsetDp * density);

        // Place phone icon above the masked number
        View phoneIcon = root.findViewById(R.id.aliyun_fusion_auth_phone_icon);
        if (phoneIcon != null) {
            int iconAboveNumber = numberTop - Math.round(80 * density);
            placeOverlayView(phoneIcon, iconAboveNumber);
        }

        View login = page.findViewById(com.alicom.fusion.auth.R.id.authsdk_login_view);
        int loginBottom = login != null && login.getHeight() > 0
                ? vendorTop(
                          page, com.alicom.fusion.auth.R.id.authsdk_login_view, rootLocation[1], 0)
                        + login.getHeight()
                : bodyTop + Math.round((layout.loginOffsetDp + LOGIN_HEIGHT_DP) * density);

        placeOverlayView(root.findViewById(R.id.aliyun_fusion_auth_other_number),
                loginBottom + Math.round(OTHER_BELOW_LOGIN_DP * density));
    }

    /**
     * The vendor draws "+86" as a separate TextView with its own size and no
     * resource id; give it the masked number's size and typeface. Guarded so
     * the relayout it triggers does not repeat.
     */
    /**
     * Hides the +86 country code prefix, leaving only the masked phone number.
     */
    private static void matchCountryCodeSize(View page) {
        TextView country = findCountryCode(page);
        if (country != null) {
            country.setVisibility(View.GONE);
            android.util.Log.d("AliyunFusionAuth", "Hidden +86 country code");
        }
    }

    private static TextView findCountryCode(View view) {
        if (view instanceof TextView
                && "+86".equals(((TextView) view).getText().toString().trim())) {
            return (TextView) view;
        }
        if (view instanceof ViewGroup) {
            ViewGroup group = (ViewGroup) view;
            for (int i = 0; i < group.getChildCount(); i++) {
                TextView found = findCountryCode(group.getChildAt(i));
                if (found != null) {
                    return found;
                }
            }
        }
        return null;
    }

    private static void hideVendorView(View page, int id) {
        View view = page.findViewById(id);
        if (view != null && view.getVisibility() != View.GONE)
            view.setVisibility(View.GONE);
    }

    /** Top of a vendor view relative to the overlay root, or the fallback. */
    private static int vendorTop(View page, int id, int rootScreenTop, int fallback) {
        View view = page.findViewById(id);
        if (view == null || view.getHeight() == 0)
            return fallback;
        int[] location = new int[2];
        view.getLocationOnScreen(location);
        return location[1] - rootScreenTop;
    }

    private static void placeOverlayView(View view, int top) {
        view.setTranslationY(top - view.getTop());
        view.setAlpha(1f);
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

    /** Carrier agreements required next to the masked number, by SDK carrier name. */
    private static String[] carrierProtocol(String carrierName) {
        if ("CMCC".equals(carrierName)) {
            return new String[] {"《中国移动认证服务条款》",
                    "https://wap.cmpassport.com/resources/html/contract.html"};
        }
        if ("CUCC".equals(carrierName)) {
            return new String[] {
                    "《中国联通认证服务协议》", "https://ms.zzx9.cn/html/oauth/protocol2.html"};
        }
        if ("CTCC".equals(carrierName)) {
            return new String[] {"《中国电信天翼账号服务条款》",
                    "https://e.189.cn/sdk/agreement/detail.do?hidetop=true"};
        }
        return null;
    }

    private static Activity findActivity(Context context) {
        while (context instanceof ContextWrapper && !(context instanceof Activity)) {
            Context base = ((ContextWrapper) context).getBaseContext();
            if (base == context)
                break;
            context = base;
        }
        return context instanceof Activity ? (Activity) context : null;
    }

    private static boolean isDarkMode(Context context) {
        int uiMode = context.getResources().getConfiguration().uiMode;
        return (uiMode & Configuration.UI_MODE_NIGHT_MASK) == Configuration.UI_MODE_NIGHT_YES;
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

    private void addProtocolLink(Spannable text, int start, String name, String url) {
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

    private static long number(Object value, long fallback) {
        if (value instanceof Number) {
            return ((Number) value).longValue();
        }
        if (value instanceof String) {
            try {
                return Long.parseLong(((String) value).trim());
            } catch (NumberFormatException ignored) {
                // Use the bounded default below.
            }
        }
        return fallback;
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

package dev.aliyunfusionauth.flutter;

import android.app.Activity;
import android.graphics.Color;
import android.net.Uri;
import android.os.Bundle;
import android.view.Gravity;
import android.view.ViewGroup;
import android.webkit.WebResourceRequest;
import android.webkit.WebSettings;
import android.webkit.WebView;
import android.webkit.WebViewClient;
import android.widget.Button;
import android.widget.LinearLayout;
import android.widget.TextView;

import com.mobile.auth.gatewayauth.Constant;

import java.lang.ref.WeakReference;

/** Internal protocol page required by the fusion SDK's com.fusion.auth intent. */
public final class FusionAuthProtocolActivity extends Activity {
    private static WeakReference<FusionAuthProtocolActivity> openPage = new WeakReference<>(null);
    private WebView webView;

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        openPage = new WeakReference<>(this);
        String url = getIntent().getStringExtra(Constant.PROTOCOL_WEB_VIEW_URL);
        String name = getIntent().getStringExtra(Constant.PROTOCOL_WEB_VIEW_NAME);
        if (!isWebUrl(url)) {
            finish();
            return;
        }

        LinearLayout content = new LinearLayout(this);
        content.setOrientation(LinearLayout.VERTICAL);
        content.setBackgroundColor(Color.WHITE);
        content.setFitsSystemWindows(true);
        LinearLayout toolbar = new LinearLayout(this);
        toolbar.setGravity(Gravity.CENTER_VERTICAL);
        Button back = new Button(this);
        back.setText("返回");
        back.setOnClickListener(view -> finish());
        toolbar.addView(back);
        TextView title = new TextView(this);
        title.setText(name == null ? "协议详情" : name);
        title.setTextColor(Color.BLACK);
        title.setTextSize(18);
        toolbar.addView(
                title, new LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1));
        content.addView(toolbar);

        webView = new WebView(this);
        WebSettings settings = webView.getSettings();
        settings.setJavaScriptEnabled(true);
        settings.setDomStorageEnabled(true);
        settings.setAllowFileAccess(false);
        settings.setAllowContentAccess(false);
        settings.setMixedContentMode(WebSettings.MIXED_CONTENT_NEVER_ALLOW);
        settings.setUseWideViewPort(true);
        settings.setLoadWithOverviewMode(true);
        webView.setWebViewClient(new WebViewClient() {
            @Override
            public boolean shouldOverrideUrlLoading(WebView view, WebResourceRequest request) {
                return !isWebUrl(request.getUrl().toString());
            }

            @Override
            public boolean shouldOverrideUrlLoading(WebView view, String targetUrl) {
                return !isWebUrl(targetUrl);
            }
        });
        content.addView(
                webView, new LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, 0, 1));
        setContentView(content);
        webView.loadUrl(url);
    }

    private static boolean isWebUrl(String url) {
        if (url == null)
            return false;
        Uri uri = Uri.parse(url);
        return "https".equalsIgnoreCase(uri.getScheme()) && uri.getHost() != null;
    }

    static void closeOpenPage() {
        FusionAuthProtocolActivity page = openPage.get();
        if (page != null && !page.isFinishing())
            page.finish();
        openPage.clear();
    }

    @Override
    protected void onDestroy() {
        if (openPage.get() == this)
            openPage.clear();
        if (webView != null) {
            webView.stopLoading();
            webView.destroy();
            webView = null;
        }
        super.onDestroy();
    }
}

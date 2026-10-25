# Fusion SDK uses reflection and native entry points; preserve vendor APIs.
-keep class com.alicom.fusion.auth.** { *; }
-keep class com.mobile.auth.gatewayauth.** { *; }
-keep class androidx.core.content.ContextCompat { *; }
-keep class androidx.appcompat.app.AppCompatActivity { *; }
-keep public class * extends android.widget.ImageView { *; }
-keep class androidx.activity.OnBackPressedDispatcher { *; }
-keep class androidx.activity.OnBackPressedCallback { *; }
-keep class androidx.lifecycle.LifecycleOwner { *; }
# The main SDK probes these optional components before use; this package does
# not ship them. Host apps adding Umeng must also use its own consumer rules.
-dontwarn com.umeng.**
-dontwarn com.zx.sdk.**
-keepclassmembers class * {
    public <init>(org.json.JSONObject);
}
-keepclassmembers enum * {
    public static **[] values();
    public static ** valueOf(java.lang.String);
}

// SDK event semantics are pinned to the bundled Fusion Authentication SDK 1.2.16.
package dev.aliyunfusionauth.flutter;

/** Separates navigation inside an authentication screen from a terminal cancellation. */
final class FusionAuthEventPolicy {
    private FusionAuthEventPolicy() {}

    static boolean cancelsFromAuthEvent(String code, String innerCode, boolean switchingNumber) {
        // SMS back first emits 510004 even when it only returns from the code
        // form to phone entry. Actual exit also emits 510001/template-finish.
        return !"510004".equals(code) && isCancellation(code, innerCode, switchingNumber);
    }

    static boolean isCancellation(String code, String innerCode, boolean switchingNumber) {
        // Carrier dismissal while switching numbers continues the SMS fallback.
        if ("400005".equals(code)
                && (switchingNumber || "700001".equals(innerCode) || "1700001".equals(innerCode))) {
            return false;
        }
        return "400005".equals(code) || "410010".equals(code) || "510001".equals(code)
                || "510004".equals(code) || "610001".equals(code) || "610004".equals(code)
                || "110010".equals(code) || "1700000".equals(code);
    }
}

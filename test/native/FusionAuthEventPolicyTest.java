package dev.aliyunfusionauth.flutter;

/** Runs without Android classes so navigation regressions can be checked on any JDK. */
public final class FusionAuthEventPolicyTest {
    private static int checks;

    public static void main(String[] args) {
        check(!FusionAuthEventPolicy.cancelsFromAuthEvent("510004", null, false),
                "SMS back to phone entry must leave authentication running");
        check(FusionAuthEventPolicy.isCancellation("510004", null, false),
                "SMS template finish must still resolve cancellation");

        for (String code : new String[] {
                     "400005", "410010", "510001", "610001", "610004", "110010", "1700000"}) {
            check(FusionAuthEventPolicy.cancelsFromAuthEvent(code, null, false),
                    "A terminal exit must cancel: " + code);
            check(FusionAuthEventPolicy.isCancellation(code, null, false),
                    "A completed exit must be classified as cancellation: " + code);
        }

        for (String innerCode : new String[] {"700001", "1700001"}) {
            check(!FusionAuthEventPolicy.cancelsFromAuthEvent("400005", innerCode, false),
                    "Switching phones must allow SMS fallback");
        }
        check(!FusionAuthEventPolicy.isCancellation("400005", null, true),
                "Carrier close after an explicit phone switch must continue");
        for (String code : new String[] {"410009", "unknown", null}) {
            check(!FusionAuthEventPolicy.cancelsFromAuthEvent(code, null, false),
                    "Nonterminal events must not cancel");
        }
        System.out.println("PASS: " + checks + " Android event assertions");
    }

    private static void check(boolean condition, String message) {
        if (!condition) {
            throw new AssertionError(message);
        }
        checks++;
    }
}

package com.joymasher.moonrider;

import android.webkit.ConsoleMessage;
import android.webkit.WebChromeClient;

/** Forwards WebView JS console output to logcat under the "MoonriderJS" tag. */
public class LoggingChromeClient extends WebChromeClient {
    @Override
    public boolean onConsoleMessage(ConsoleMessage m) {
        android.util.Log.d("MoonriderJS",
                m.message() + " @" + m.sourceId() + ":" + m.lineNumber());
        return true;
    }
}

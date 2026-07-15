package com.joymasher.moonrider;

import android.app.Activity;
import android.view.WindowManager;
import android.webkit.JavascriptInterface;

/**
 * Bridge exposed to the WebView JS as window.MRAndroid.
 * Top-level (not an inner class) to avoid a d8 8.2.2 + JDK 21 NPE on
 * InnerClasses/EnclosingMethod attributes.
 */
public class NativeBridge {
    private final Activity activity;

    NativeBridge(Activity activity) {
        this.activity = activity;
    }

    @JavascriptInterface
    public void setKeepAwake(final boolean on) {
        activity.runOnUiThread(new KeepAwakeTask(activity, on));
    }

    @JavascriptInterface
    public void quit() {
        activity.runOnUiThread(new QuitTask(activity));
    }

    /** Named top-level-style Runnable to finish the Activity (d8 reason). */
    static final class QuitTask implements Runnable {
        private final Activity activity;
        QuitTask(Activity activity) { this.activity = activity; }
        @Override
        public void run() {
            activity.finish();
        }
    }

    /** Named top-level-style Runnable for the same d8 reason. */
    static final class KeepAwakeTask implements Runnable {
        private final Activity activity;
        private final boolean on;

        KeepAwakeTask(Activity activity, boolean on) {
            this.activity = activity;
            this.on = on;
        }

        @Override
        public void run() {
            if (on) {
                activity.getWindow().addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON);
            } else {
                activity.getWindow().clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON);
            }
        }
    }
}

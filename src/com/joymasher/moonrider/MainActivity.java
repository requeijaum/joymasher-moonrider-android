package com.joymasher.moonrider;

import android.annotation.SuppressLint;
import android.app.Activity;
import android.os.Build;
import android.os.Bundle;
import android.view.KeyEvent;
import android.view.View;
import android.view.WindowManager;
import android.webkit.WebSettings;
import android.webkit.WebView;

/**
 * Moonrider Android launcher.
 *
 * Loads the Construct 2 build packaged under assets/www via a full-screen,
 * hardware-accelerated WebView. The WebView's built-in Chromium engine handles
 * audio (.ogg), WebGL/canvas rendering and the Gamepad API natively, so none of
 * the muOS/WPE workarounds (audio ghost, native mixer, evdev bridge) are needed.
 *
 * Hardware gamepads arrive through the standard Gamepad API inside the WebView.
 * When no gamepad is present, an on-screen touch overlay (touch-controls.js)
 * synthesizes the game's native keyboard input.
 */
public class MainActivity extends Activity {

    private WebView webView;

    @SuppressLint("SetJavaScriptEnabled")
    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);

        // Keep the screen awake during play.
        getWindow().addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON);

        webView = new WebView(this);
        WebSettings s = webView.getSettings();
        s.setJavaScriptEnabled(true);
        s.setDomStorageEnabled(true);          // localStorage -> save games
        s.setDatabaseEnabled(true);
        s.setAllowFileAccess(true);
        s.setAllowContentAccess(true);
        s.setAllowFileAccessFromFileURLs(true);
        // Universal file access is intentionally NOT enabled: the game is fully
        // offline and served from file:///android_asset. Leaving it off shrinks
        // the attack surface of the JS bridge (window.MRAndroid).
        s.setMediaPlaybackRequiresUserGesture(false);  // let intro audio autoplay
        s.setCacheMode(WebSettings.LOAD_NO_CACHE);
        s.setDefaultTextEncodingName("utf-8");
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
            s.setMixedContentMode(WebSettings.MIXED_CONTENT_ALWAYS_ALLOW);
        }

        // Route JS console to logcat for debugging.
        webView.setWebChromeClient(new LoggingChromeClient());

        // Hardware acceleration is on by default at the app level; ensure the
        // view layer is hardware-backed for WebGL/canvas performance.
        webView.setLayerType(View.LAYER_TYPE_HARDWARE, null);
        webView.addJavascriptInterface(new NativeBridge(this), "MRAndroid");
        setContentView(webView);

        webView.loadUrl("file:///android_asset/www/index.html");
    }

    /** Immersive sticky full-screen: hide status & navigation bars. */
    @Override
    public void onWindowFocusChanged(boolean hasFocus) {
        super.onWindowFocusChanged(hasFocus);
        if (hasFocus) applyImmersive();
    }

    private void applyImmersive() {
        View decor = getWindow().getDecorView();
        int flags = View.SYSTEM_UI_FLAG_LAYOUT_STABLE
                | View.SYSTEM_UI_FLAG_LAYOUT_HIDE_NAVIGATION
                | View.SYSTEM_UI_FLAG_LAYOUT_FULLSCREEN
                | View.SYSTEM_UI_FLAG_HIDE_NAVIGATION
                | View.SYSTEM_UI_FLAG_FULLSCREEN
                | View.SYSTEM_UI_FLAG_IMMERSIVE_STICKY;
        decor.setSystemUiVisibility(flags);
    }

    @Override
    protected void onPause() {
        super.onPause();
        if (webView != null) webView.onPause();
    }

    @Override
    protected void onResume() {
        super.onResume();
        if (webView != null) webView.onResume();
        applyImmersive();
    }

    /**
     * Back handling: the game manages its own in-menu navigation, so a single
     * Back is swallowed. But double-tapping Back within 2s exits the app — a
     * safety valve so the user is never trapped if the JS "Quit" button or the
     * options overlay ever fails to load.
     */
    private long lastBackPress = 0L;

    @Override
    public boolean onKeyDown(int keyCode, KeyEvent event) {
        if (keyCode == KeyEvent.KEYCODE_BACK && webView != null) {
            long now = System.currentTimeMillis();
            if (now - lastBackPress < 2000L) {
                finish();
                return true;
            }
            lastBackPress = now;
            android.widget.Toast.makeText(this,
                "Pressione Voltar novamente para sair", android.widget.Toast.LENGTH_SHORT).show();
            return true;
        }
        return super.onKeyDown(keyCode, event);
    }

    @Override
    protected void onDestroy() {
        if (webView != null) {
            webView.destroy();
            webView = null;
        }
        super.onDestroy();
    }
}

/*
 * Moonrider Android - live settings engine
 *
 * Loaded BEFORE c2runtime.js so it can wrap browser APIs the engine will use:
 *   - requestAnimationFrame  -> FPS cap (30/60/90/120/uncapped)
 *   - AudioContext           -> master volume + mono/stereo downmix
 *
 * Everything applies LIVE (no reload). Settings persist in localStorage under
 * the "mrOpts" key. The options UI (options-menu.js) reads/writes MRSettings.
 *
 * Native game resolution: 428x240 (from data.js pm[10],pm[11]).
 */
(function () {
    "use strict";

    var NATIVE_W = 428, NATIVE_H = 240;
    var LS_KEY = "mrOpts";

    var defaults = {
        fpsCap: 0,          // 0 = uncapped, else 30/60/90/120
        // scaleMode: "off" (engine letterbox) | "auto" (max integer fit) |
        //            50|100|200|300|400|500 (explicit percent of native res)
        scaleMode: "off",
        smoothing: false,   // canvas image smoothing (false = crisp pixels)
        volume: 100,        // 0..100 master volume
        mono: false,        // downmix to mono
        showFps: false,
        keepAwake: true,
        haptics: true,
        showTouch: true,    // show on-screen overlay even with a gamepad
        crt: false,         // CRT scanline overlay
        brightness: 100     // 0..150 screen brightness (CSS filter)
    };

    var opts = load();

    function load() {
        try {
            var raw = localStorage.getItem(LS_KEY);
            if (raw) {
                var o = JSON.parse(raw);
                // migrate old boolean integerScale -> scaleMode
                if (!("scaleMode" in o) && ("integerScale" in o))
                    o.scaleMode = o.integerScale ? "auto" : "off";
                var merged = {};
                for (var k in defaults) merged[k] = (k in o) ? o[k] : defaults[k];
                return merged;
            }
        } catch (e) {}
        var copy = {};
        for (var k2 in defaults) copy[k2] = defaults[k2];
        return copy;
    }

    function save() {
        try { localStorage.setItem(LS_KEY, JSON.stringify(opts)); } catch (e) {}
    }

    /* ------------------------------------------------------------------ *
     *  1. FPS cap  -- wrap requestAnimationFrame with a timestamp gate.
     *
     *  CRITICAL: the gate timestamp must be PER animation loop, not a single
     *  global. C2's render loop, the FPS meter and any other rAF consumer each
     *  re-request their own frame; a shared "lastFrame" makes them fight over
     *  the gate (one loop resets it, starving the other) which can freeze the
     *  render loop. We key the last-accepted timestamp off the callback via a
     *  Map, so every independent loop is throttled on its own clock.
     * ------------------------------------------------------------------ */
    var rafNative = window.requestAnimationFrame.bind(window);
    var lastByCb = new WeakMap();

    window.requestAnimationFrame = function (cb) {
        if (!opts.fpsCap) return rafNative(cb);
        var minDelta = 1000 / opts.fpsCap;
        return rafNative(function step(ts) {
            var last = lastByCb.has(cb) ? lastByCb.get(cb) : -1e9;
            if (ts - last >= minDelta - 0.5) {
                lastByCb.set(cb, ts);
                cb(ts);
            } else {
                // Not yet time: reschedule THIS gate (not via the public wrapper,
                // to avoid re-reading the cap mid-wait and to keep 1 pending raf).
                rafNative(step);
            }
        });
    };

    /* ------------------------------------------------------------------ *
     *  2. Audio  -- insert a master GainNode (+ optional mono merger)
     *               between the game and the real AudioContext.destination
     * ------------------------------------------------------------------ */
    var AC = window.AudioContext || window.webkitAudioContext;
    var audioChains = []; // AudioContext instances we've wired

    if (AC) {
        // "destination" lives on BaseAudioContext.prototype in modern Chromium,
        // not AudioContext.prototype. Walk the prototype chain to find the
        // descriptor with a getter.
        var proto = AC.prototype, realDestDesc = null;
        while (proto) {
            var d = Object.getOwnPropertyDescriptor(proto, "destination");
            if (d && d.get) { realDestDesc = d; break; }
            proto = Object.getPrototypeOf(proto);
        }
        if (realDestDesc && proto) {
            Object.defineProperty(proto, "destination", {
                configurable: true,
                get: function () {
                    var real = realDestDesc.get.call(this);
                    if (!this.__mrGain) {
                        var gain = this.createGain();
                        gain.gain.value = opts.volume / 100;
                        this.__mrRealDest = real;
                        this.__mrGain = gain;
                        this.__mrMono = false;
                        rewire(this);
                        audioChains.push(this);
                    }
                    return this.__mrGain;
                }
            });
        }
    }

    function rewire(ctx) {
        try { ctx.__mrGain.disconnect(); } catch (e) {}
        try { if (ctx.__mrMerger) ctx.__mrMerger.disconnect(); } catch (e) {}
        try { if (ctx.__mrSplitter) ctx.__mrSplitter.disconnect(); } catch (e) {}
        if (opts.mono) {
            // gain -> splitter -> merger (L+R into both) -> realDest
            var splitter = ctx.createChannelSplitter(2);
            var merger = ctx.createChannelMerger(2);
            ctx.__mrGain.connect(splitter);
            // average the two channels into a mono signal on both outputs
            splitter.connect(merger, 0, 0);
            splitter.connect(merger, 0, 1);
            splitter.connect(merger, 1, 0);
            splitter.connect(merger, 1, 1);
            merger.connect(ctx.__mrRealDest);
            ctx.__mrSplitter = splitter;
            ctx.__mrMerger = merger;
        } else {
            ctx.__mrGain.connect(ctx.__mrRealDest);
            ctx.__mrSplitter = null;
            ctx.__mrMerger = null;
        }
    }

    function applyAudio() {
        for (var i = 0; i < audioChains.length; i++) {
            var ctx = audioChains[i];
            if (ctx.__mrGain) ctx.__mrGain.gain.value = opts.volume / 100;
            if (!!ctx.__mrMono !== !!opts.mono) {
                ctx.__mrMono = !!opts.mono;
                rewire(ctx);
            }
        }
    }

    /* ------------------------------------------------------------------ *
     *  3. Canvas: integer scaling + pixel smoothing (applied via observer,
     *     because the engine rewrites #c2canvasdiv CSS on every resize)
     * ------------------------------------------------------------------ */
    var canvas = null, canvasdiv = null, reapplyScheduled = false;

    function getEls() {
        if (!canvas) canvas = document.getElementById("c2canvas");
        if (!canvasdiv) canvasdiv = document.getElementById("c2canvasdiv");
    }

    function applyCanvas() {
        getEls();
        if (!canvas) return;

        // pixel smoothing
        var rendering = opts.smoothing ? "auto" : "pixelated";
        canvas.style.imageRendering = rendering;
        canvas.style.setProperty("image-rendering", rendering);

        var mode = opts.scaleMode;
        if (mode && mode !== "off" && canvasdiv) {
            var vw = window.innerWidth, vh = window.innerHeight;
            var scale;
            if (mode === "auto") {
                // largest integer multiple of native res that still fits
                scale = Math.max(1, Math.floor(Math.min(vw / NATIVE_W, vh / NATIVE_H)));
            } else {
                // explicit percent: 50 -> 0.5, 100 -> 1, 200 -> 2, ...
                scale = (parseFloat(mode) || 100) / 100;
            }
            var w = Math.round(NATIVE_W * scale), h = Math.round(NATIVE_H * scale);
            // center; allow negative offset (larger than screen) so it stays centered
            var offx = Math.round((vw - w) / 2), offy = Math.round((vh - h) / 2);
            canvasdiv.style.setProperty("width",  w + "px", "important");
            canvasdiv.style.setProperty("height", h + "px", "important");
            canvasdiv.style.setProperty("margin-left", offx + "px", "important");
            canvasdiv.style.setProperty("margin-top",  offy + "px", "important");
            canvasdiv.style.setProperty("overflow", "hidden", "important");
            canvas.style.setProperty("width",  w + "px", "important");
            canvas.style.setProperty("height", h + "px", "important");
        } else if (canvasdiv) {
            // release our forced sizing; let the engine's letterbox take over
            canvasdiv.style.removeProperty("width");
            canvasdiv.style.removeProperty("height");
            canvasdiv.style.removeProperty("margin-left");
            canvasdiv.style.removeProperty("margin-top");
            canvasdiv.style.removeProperty("overflow");
            canvas.style.removeProperty("width");
            canvas.style.removeProperty("height");
        }
    }

    function scheduleReapply() {
        if (reapplyScheduled) return;
        reapplyScheduled = true;
        setTimeout(function () {
            reapplyScheduled = false;
            applyCanvas();
        }, 30);
    }

    function startObserver() {
        getEls();
        if (!canvasdiv) { setTimeout(startObserver, 200); return; }
        // Re-assert integer scaling whenever the engine touches the canvas CSS.
        var mo = new MutationObserver(function () {
            if (opts.scaleMode && opts.scaleMode !== "off") scheduleReapply();
        });
        mo.observe(canvasdiv, { attributes: true, attributeFilter: ["style"] });
        mo.observe(canvas, { attributes: true, attributeFilter: ["style"] });
        window.addEventListener("resize", scheduleReapply);
        applyCanvas();
    }

    /* ------------------------------------------------------------------ *
     *  4. Extras: keep-awake handled natively; FPS meter; haptics helper
     * ------------------------------------------------------------------ */
    var fpsEl = null, frames = 0, fpsAccum = 0, lastFpsTs = 0;
    function gameCanvas() {
        if (!canvas) canvas = document.getElementById("c2canvas");
        return canvas;
    }
    function fpsTick(ts) {
        // Use NATIVE raf so the meter samples real presented frames and never
        // interferes with the FPS-cap gate (which keys off the callback ref).
        if (!opts.showFps) { if (fpsEl) fpsEl.style.display = "none"; rafNative(fpsTick); return; }
        if (!fpsEl) {
            fpsEl = document.createElement("div");
            fpsEl.id = "mr-fps";
            fpsEl.style.cssText = "position:fixed;top:4px;left:50%;transform:translateX(-50%);" +
                "z-index:10001;color:#0f0;font:bold 13px monospace;background:rgba(0,0,0,.5);" +
                "padding:1px 6px;border-radius:6px;pointer-events:none;";
            document.body.appendChild(fpsEl);
        }
        fpsEl.style.display = "block";
        frames++;
        if (ts - lastFpsTs >= 500) {
            var dispFps = Math.round(frames * 1000 / (ts - lastFpsTs));
            // Prefer C2's own game-loop fps (the number the cap actually limits);
            // fall back to the display refresh count.
            var c = gameCanvas();
            var gameFps = (c && c.c2runtime && typeof c.c2runtime.fps === "number")
                ? c.c2runtime.fps : null;
            fpsEl.textContent = (gameFps != null)
                ? (gameFps + " fps")
                : (dispFps + " fps");
            frames = 0; lastFpsTs = ts;
        }
        rafNative(fpsTick);
    }
    function startFps() { lastFpsTs = performance.now(); rafNative(fpsTick); }

    function haptic(ms) {
        if (opts.haptics && navigator.vibrate) {
            try { navigator.vibrate(ms || 12); } catch (e) {}
        }
    }

    function applyTouchVisibility() {
        // Cooperate with touch-controls.js gamepad auto-hide via a global flag.
        window.MR_forceTouch = !!opts.showTouch;
        if (window.MR_refreshTouch) window.MR_refreshTouch();
    }

    /* CRT scanline overlay + brightness (pure CSS, engine untouched) */
    var crtEl = null;
    function applyVisualFx() {
        getEls();
        // brightness via filter on the canvas div (falls back to canvas)
        var target = document.getElementById("c2canvasdiv") || canvas;
        if (target) {
            var b = Math.max(0, Math.min(150, opts.brightness)) / 100;
            target.style.filter = (b === 1) ? "" : "brightness(" + b + ")";
        }
        // CRT scanlines
        if (opts.crt) {
            if (!crtEl) {
                crtEl = document.createElement("div");
                crtEl.id = "mr-crt";
                crtEl.style.cssText = "position:fixed;inset:0;z-index:9999;pointer-events:none;" +
                    "background:repeating-linear-gradient(to bottom," +
                    "rgba(0,0,0,0) 0px,rgba(0,0,0,0) 1px,rgba(0,0,0,.28) 2px,rgba(0,0,0,.28) 3px);" +
                    "mix-blend-mode:multiply;";
                document.body.appendChild(crtEl);
            }
            crtEl.style.display = "block";
        } else if (crtEl) {
            crtEl.style.display = "none";
        }
    }

    /* ------------------------------------------------------------------ *
     *  Public API
     * ------------------------------------------------------------------ */
    window.MRSettings = {
        get: function (k) { return k ? opts[k] : opts; },
        defaults: defaults,
        set: function (k, v) {
            opts[k] = v;
            save();
            switch (k) {
                case "volume":
                case "mono": applyAudio(); break;
                case "scaleMode":
                case "smoothing": applyCanvas(); break;
                case "showTouch": applyTouchVisibility(); break;
                case "crt":
                case "brightness": applyVisualFx(); break;
                // fpsCap: picked up on the next rAF automatically
            }
            return opts[k];
        },
        haptic: haptic,
        NATIVE_W: NATIVE_W, NATIVE_H: NATIVE_H
    };

    function init() {
        startObserver();
        startFps();
        applyTouchVisibility();
        applyVisualFx();
        // resume any suspended AudioContext on first interaction (autoplay policy)
        var resume = function () {
            for (var i = 0; i < audioChains.length; i++) {
                if (audioChains[i].state === "suspended") {
                    try { audioChains[i].resume(); } catch (e) {}
                }
            }
        };
        document.addEventListener("touchstart", resume, true);
        document.addEventListener("mousedown", resume, true);
    }

    if (document.readyState === "loading")
        document.addEventListener("DOMContentLoaded", init);
    else
        init();
})();

/*
 * Moonrider Android - on-screen touch controls
 *
 * Construct 2 default keyboard map (from data.js varConKB_DEFAULT / _MENU):
 *   Up=38  Down=40  Left=37  Right=39
 *   Z=90   X=88   S=83   A=65   C=67   Y=89
 *   Enter=13 (menu confirm)
 *
 * We synthesize real keydown/keyup KeyboardEvents so the C2 Keyboard plugin
 * picks them up exactly like a physical key. No engine patching required.
 *
 * The overlay auto-hides whenever a hardware gamepad is connected (handheld /
 * BT controller), and re-appears if all gamepads disconnect.
 */
(function () {
    "use strict";

    // button id -> keyCode  (from data.js varConKB_DEFAULT, button order
    // btA,btB,btX,btY,btL1,btR1: 90,88,83,65,67,89 ; menu confirm = Enter 13)
    var MAP = {
        "tc-up": 38, "tc-down": 40, "tc-left": 37, "tc-right": 39,
        "tc-a": 90,   // Z  - btA (jump / confirm)
        "tc-b": 88,   // X  - btB (attack / back)
        "tc-x": 83,   // S  - btX (special)
        "tc-y": 65,   // A  - btY
        "tc-l1": 67,  // C  - btL1
        "tc-r1": 89,  // Y  - btR1
        "tc-l2": 81,  // Q  - btL2 (no KB default in-game; remap if needed)
        "tc-r2": 69,  // E  - btR2 (no KB default in-game; remap if needed)
        "tc-start": 13,  // Enter - start / confirm menu
        "tc-select": 16  // Shift - select
    };

    // keyCode -> DOM code / key string (best-effort, C2 mostly reads .which/.keyCode)
    function keyInfo(kc) {
        switch (kc) {
            case 38: return ["ArrowUp", "ArrowUp"];
            case 40: return ["ArrowDown", "ArrowDown"];
            case 37: return ["ArrowLeft", "ArrowLeft"];
            case 39: return ["ArrowRight", "ArrowRight"];
            case 13: return ["Enter", "Enter"];
            case 90: return ["KeyZ", "z"];
            case 88: return ["KeyX", "x"];
            case 83: return ["KeyS", "s"];
            case 65: return ["KeyA", "a"];
            case 67: return ["KeyC", "c"];
            case 89: return ["KeyY", "y"];
            case 81: return ["KeyQ", "q"];
            case 69: return ["KeyE", "e"];
            case 16: return ["ShiftLeft", "Shift"];
            default: return ["", ""];
        }
    }

    function fireKey(type, kc) {
        var info = keyInfo(kc);
        var ev;
        try {
            ev = new KeyboardEvent(type, {
                bubbles: true, cancelable: true,
                key: info[1], code: info[0],
                keyCode: kc, which: kc, charCode: 0
            });
        } catch (e) {
            ev = document.createEvent("Event");
            ev.initEvent(type, true, true);
        }
        // Some engines read keyCode/which off the event object directly; force them
        // in case the constructor ignored them (older WebView quirk).
        try {
            Object.defineProperty(ev, "keyCode", { get: function () { return kc; } });
            Object.defineProperty(ev, "which",   { get: function () { return kc; } });
        } catch (e) {}
        document.dispatchEvent(ev);
    }

    var down = {}; // kc -> true, to avoid repeats

    function press(kc) {
        if (down[kc]) return;
        down[kc] = true;
        fireKey("keydown", kc);
    }
    function release(kc) {
        if (!down[kc]) return;
        down[kc] = false;
        fireKey("keyup", kc);
    }

    function bindButton(el, kc) {
        function on(e) {
            e.preventDefault();
            el.classList.add("pressed");
            press(kc);
            if (window.MRSettings && window.MRSettings.haptic) window.MRSettings.haptic(12);
        }
        function off(e) {
            if (e) e.preventDefault();
            el.classList.remove("pressed");
            release(kc);
        }
        el.addEventListener("touchstart", on, { passive: false });
        el.addEventListener("touchend", off, { passive: false });
        el.addEventListener("touchcancel", off, { passive: false });
        // Mouse fallback (desktop WebView / testing)
        el.addEventListener("mousedown", on);
        el.addEventListener("mouseup", off);
        el.addEventListener("mouseleave", function (e) { if (down[kc]) off(e); });
    }

    function setup() {
        var root = document.getElementById("touch-controls");
        if (!root) return;
        Object.keys(MAP).forEach(function (id) {
            var el = document.getElementById(id);
            if (el) bindButton(el, MAP[id]);
        });

        // Gamepad presence detection -> show/hide overlay
        function anyGamepad() {
            var gps = (navigator.getGamepads && navigator.getGamepads()) || [];
            for (var i = 0; i < gps.length; i++) {
                if (gps[i] && gps[i].connected) return true;
            }
            return false;
        }
        function refresh() {
            // MR_forceTouch (from options menu) keeps the overlay visible even
            // when a gamepad is connected.
            if (window.MR_forceTouch) { root.classList.add("visible"); return; }
            if (anyGamepad()) root.classList.remove("visible");
            else root.classList.add("visible");
        }
        window.MR_refreshTouch = refresh;
        window.addEventListener("gamepadconnected", refresh);
        window.addEventListener("gamepaddisconnected", refresh);
        // Poll a few times at startup: some devices report the pad late.
        var n = 0;
        var iv = setInterval(function () {
            refresh();
            if (++n > 10) clearInterval(iv);
        }, 500);
        refresh();
    }

    if (document.readyState === "loading")
        document.addEventListener("DOMContentLoaded", setup);
    else
        setup();
})();

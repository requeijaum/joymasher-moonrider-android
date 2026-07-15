/*
 * Moonrider Android - options menu UI
 *
 * A gear button (top-right corner) opens a panel of live options backed by
 * window.MRSettings (settings.js). All changes apply immediately.
 */
(function () {
    "use strict";

    function S() { return window.MRSettings; }

    var css = ""
        + "#mr-gear{position:fixed;top:6px;right:6px;z-index:10002;width:40px;height:40px;"
        + "border-radius:50%;background:rgba(0,0,0,.55);border:2px solid rgba(255,255,255,.4);"
        + "color:#fff;font-size:20px;display:flex;align-items:center;justify-content:center;"
        + "pointer-events:auto;-webkit-user-select:none;user-select:none;}"
        + "#mr-overlay{position:fixed;inset:0;z-index:10003;background:rgba(0,0,0,.72);"
        + "display:none;align-items:center;justify-content:center;"
        + "font-family:sans-serif;color:#eee;}"
        + "#mr-overlay.open{display:flex;}"
        + "#mr-panel{background:#15171c;border:1px solid #333;border-radius:12px;"
        + "width:min(560px,92vw);max-height:88vh;overflow-y:auto;padding:14px 16px;"
        + "box-shadow:0 8px 40px rgba(0,0,0,.6);}"
        + "#mr-panel h2{margin:0 0 10px;font-size:18px;display:flex;justify-content:space-between;align-items:center;}"
        + "#mr-panel h2 span.x{cursor:pointer;font-size:22px;padding:0 6px;}"
        + ".mr-row{display:flex;align-items:center;justify-content:space-between;"
        + "padding:9px 2px;border-bottom:1px solid #23262d;gap:10px;}"
        + ".mr-row .lbl{font-size:14px;}"
        + ".mr-row .sub{font-size:11px;color:#8b93a1;margin-top:2px;}"
        + ".mr-seg{display:flex;flex-wrap:wrap;gap:4px;}"
        + ".mr-seg button{background:#2a2e37;color:#cfd4dd;border:1px solid #3a3f4a;"
        + "border-radius:7px;padding:6px 10px;font-size:13px;cursor:pointer;min-width:40px;}"
        + ".mr-seg button.on{background:#4a72ff;color:#fff;border-color:#4a72ff;}"
        + ".mr-seg button.mr-more{font-weight:bold;letter-spacing:1px;}"
        + ".mr-custom{width:88px;background:#0e1014;color:#fff;border:1px solid #4a72ff;"
        + "border-radius:7px;padding:6px 8px;font-size:13px;text-align:center;}"
        + ".mr-toggle{width:52px;height:30px;border-radius:15px;background:#3a3f4a;position:relative;"
        + "cursor:pointer;transition:background .12s;flex:0 0 auto;}"
        + ".mr-toggle.on{background:#4a72ff;}"
        + ".mr-toggle .knob{position:absolute;top:3px;left:3px;width:24px;height:24px;border-radius:50%;"
        + "background:#fff;transition:left .12s;}"
        + ".mr-toggle.on .knob{left:25px;}"
        + "#mr-vol{flex:1;max-width:200px;}"
        + ".mr-foot{margin-top:12px;display:flex;justify-content:space-between;align-items:center;gap:10px;}"
        + ".mr-foot button{background:#2a2e37;color:#cfd4dd;border:1px solid #3a3f4a;"
        + "border-radius:7px;padding:8px 14px;font-size:13px;cursor:pointer;}"
        + ".mr-quit{width:100%;background:#5a1f24!important;border-color:#7a2a30!important;color:#ffd9dc!important;}"
        + "#mr-panel .mr-note{font-size:11px;color:#8b93a1;margin-top:8px;line-height:1.4;}";

    function el(tag, attrs, kids) {
        var e = document.createElement(tag);
        if (attrs) for (var k in attrs) {
            if (k === "text") e.textContent = attrs[k];
            else e.setAttribute(k, attrs[k]);
        }
        (kids || []).forEach(function (c) { e.appendChild(c); });
        return e;
    }

    function segRow(label, sub, choices, getVal, setVal, customCfg) {
        var seg = el("div", { "class": "mr-seg" });
        var btns = [];
        function syncActive() {
            btns.forEach(function (x) { x.el.classList.toggle("on", x.value === getVal()); });
            // the custom "(...)" chip highlights when the current value is not a preset
            if (customBtn) {
                var isPreset = choices.some(function (c) { return c.value === getVal(); });
                customBtn.classList.toggle("on", !isPreset);
                if (!isPreset && customCfg) customBtn.textContent = customCfg.fmt(getVal());
                else if (customCfg) customBtn.textContent = "\u2026";
            }
        }
        choices.forEach(function (c) {
            var b = el("button", { text: c.label });
            b.addEventListener("click", function () { setVal(c.value); syncActive(); });
            btns.push({ el: b, value: c.value });
            seg.appendChild(b);
        });

        // Optional "(...)" chip -> inline numeric input for a custom value.
        var customBtn = null;
        if (customCfg) {
            customBtn = el("button", { "class": "mr-more", text: "\u2026" });
            customBtn.addEventListener("click", function () {
                var inp = el("input", { type: "number", "class": "mr-custom" });
                inp.min = String(customCfg.min); inp.max = String(customCfg.max);
                inp.step = String(customCfg.step || 1);
                inp.value = String(customCfg.toNum(getVal()) || customCfg.def);
                seg.replaceChild(inp, customBtn);
                inp.focus(); inp.select();
                function commit() {
                    var n = parseFloat(inp.value);
                    if (!isNaN(n)) {
                        n = Math.max(customCfg.min, Math.min(customCfg.max, n));
                        setVal(customCfg.toVal(n));
                    }
                    if (inp.parentNode === seg) seg.replaceChild(customBtn, inp);
                    syncActive();
                }
                inp.addEventListener("blur", commit);
                inp.addEventListener("keydown", function (e) {
                    if (e.key === "Enter") inp.blur();
                    else if (e.key === "Escape") { inp.value = ""; inp.blur(); }
                });
            });
            seg.appendChild(customBtn);
        }

        syncActive();
        var left = el("div", {}, [el("div", { "class": "lbl", text: label })]);
        if (sub) left.appendChild(el("div", { "class": "sub", text: sub }));
        return el("div", { "class": "mr-row" }, [left, seg]);
    }

    function toggleRow(label, sub, getVal, setVal) {
        var t = el("div", { "class": "mr-toggle" }, [el("div", { "class": "knob" })]);
        function refresh() { t.classList.toggle("on", !!getVal()); }
        t.addEventListener("click", function () { setVal(!getVal()); refresh(); });
        refresh();
        var left = el("div", {}, [el("div", { "class": "lbl", text: label })]);
        if (sub) left.appendChild(el("div", { "class": "sub", text: sub }));
        return el("div", { "class": "mr-row" }, [left, t]);
    }

    function build() {
        var style = el("style"); style.textContent = css; document.head.appendChild(style);

        var gear = el("div", { id: "mr-gear", text: "\u2699" });
        var overlay = el("div", { id: "mr-overlay" });
        var panel = el("div", { id: "mr-panel" });

        var closeX = el("span", { "class": "x", text: "\u00d7" });
        panel.appendChild(el("h2", {}, [document.createTextNode("Op\u00e7\u00f5es"), closeX]));

        // FPS cap
        panel.appendChild(segRow("Trava de FPS", "Limite de quadros por segundo",
            [{ label: "30", value: 30 }, { label: "60", value: 60 }, { label: "90", value: 90 },
             { label: "120", value: 120 }, { label: "Sem", value: 0 }],
            function () { return S().get("fpsCap"); },
            function (v) { S().set("fpsCap", v); },
            { min: 10, max: 240, step: 1, def: 60,
              toNum: function (v) { return v || 60; },
              toVal: function (n) { return Math.round(n); },
              fmt: function (v) { return v + "\u2009fps"; } }));

        // Scale mode (integer + percent + custom)
        panel.appendChild(segRow("Escala", "Tamanho da imagem (base 428\u00d7240)",
            [{ label: "Off", value: "off" }, { label: "Auto", value: "auto" },
             { label: "50%", value: 50 }, { label: "100%", value: 100 },
             { label: "200%", value: 200 }, { label: "300%", value: 300 },
             { label: "400%", value: 400 }, { label: "500%", value: 500 }],
            function () { return S().get("scaleMode"); },
            function (v) { S().set("scaleMode", v); },
            { min: 25, max: 1000, step: 5, def: 100,
              toNum: function (v) { return (typeof v === "number") ? v : 100; },
              toVal: function (n) { return Math.round(n); },
              fmt: function (v) { return v + "%"; } }));

        // Pixel smoothing
        panel.appendChild(toggleRow("Suaviza\u00e7\u00e3o de pixels", "Off = pixel art n\u00edtido (nearest)",
            function () { return S().get("smoothing"); },
            function (v) { S().set("smoothing", v); }));

        // Volume
        var vol = el("input", { id: "mr-vol", type: "range", min: "0", max: "100", step: "5" });
        vol.value = String(S().get("volume"));
        var volVal = el("span", { "class": "sub", text: S().get("volume") + "%" });
        vol.addEventListener("input", function () {
            S().set("volume", parseInt(vol.value, 10));
            volVal.textContent = vol.value + "%";
        });
        panel.appendChild(el("div", { "class": "mr-row" }, [
            el("div", {}, [el("div", { "class": "lbl", text: "Volume" }), volVal]), vol]));

        // Audio channels
        panel.appendChild(segRow("\u00c1udio", "Sa\u00edda de som",
            [{ label: "Est\u00e9reo", value: false }, { label: "Mono", value: true }],
            function () { return S().get("mono"); },
            function (v) { S().set("mono", v); }));

        // Show FPS meter
        panel.appendChild(toggleRow("Mostrar FPS", "Contador no topo da tela",
            function () { return S().get("showFps"); },
            function (v) { S().set("showFps", v); }));

        // Keep awake
        panel.appendChild(toggleRow("Manter tela acesa", "Impede o desligamento durante o jogo",
            function () { return S().get("keepAwake"); },
            function (v) { S().set("keepAwake", v); if (window.MRAndroid && window.MRAndroid.setKeepAwake) window.MRAndroid.setKeepAwake(v); }));

        // Haptics
        panel.appendChild(toggleRow("Vibra\u00e7\u00e3o", "Feedback t\u00e1til nos bot\u00f5es touch",
            function () { return S().get("haptics"); },
            function (v) { S().set("haptics", v); }));

        // Always show touch overlay
        panel.appendChild(toggleRow("For\u00e7ar overlay touch", "Mostrar bot\u00f5es mesmo com gamepad",
            function () { return S().get("showTouch"); },
            function (v) { S().set("showTouch", v); }));

        // CRT scanlines
        panel.appendChild(toggleRow("Filtro CRT", "Scanlines estilo tubo (retr\u00f4)",
            function () { return S().get("crt"); },
            function (v) { S().set("crt", v); }));

        // Brightness
        var bri = el("input", { id: "mr-bri", type: "range", min: "50", max: "150", step: "5" });
        bri.value = String(S().get("brightness"));
        var briVal = el("span", { "class": "sub", text: S().get("brightness") + "%" });
        bri.addEventListener("input", function () {
            S().set("brightness", parseInt(bri.value, 10));
            briVal.textContent = bri.value + "%";
        });
        panel.appendChild(el("div", { "class": "mr-row" }, [
            el("div", {}, [el("div", { "class": "lbl", text: "Brilho" }), briVal]), bri]));

        var reset = el("button", { text: "Restaurar padr\u00f5es" });
        reset.addEventListener("click", function () {
            var d = S().defaults;
            for (var k in d) S().set(k, d[k]);
            overlay.classList.remove("open");
            setTimeout(function () { open(); }, 60); // rebuild reflecting defaults
        });
        var resume = el("button", { text: "Voltar ao jogo" });
        resume.addEventListener("click", close);
        panel.appendChild(el("div", { "class": "mr-foot" }, [reset, resume]));

        // Quit: the game's own "Quit" menu entry calls an NW.js/Electron API
        // that doesn't exist in a WebView, so it does nothing. This closes the
        // Activity via the native bridge instead.
        var quit = el("button", { "class": "mr-quit", text: "Sair do jogo" });
        quit.addEventListener("click", function () {
            // Two-tap confirm (window.confirm may be blocked in a bare WebView).
            if (quit.dataset.armed === "1") {
                doQuit();
                return;
            }
            quit.dataset.armed = "1";
            quit.textContent = "Confirmar sa\u00edda? (toque de novo)";
            setTimeout(function () {
                quit.dataset.armed = "0";
                quit.textContent = "Sair do jogo";
            }, 2500);
        });
        panel.appendChild(el("div", { "class": "mr-foot" }, [quit]));

        panel.appendChild(el("div", { "class": "mr-note",
            text: "Todas as op\u00e7\u00f5es s\u00e3o aplicadas ao vivo e salvas automaticamente. L2/R2 usam Q/E por padr\u00e3o \u2014 remape\u00e1veis no menu do jogo." }));

        overlay.appendChild(panel);

        function rebuildPanel() {
            // Re-open regenerates control states from current settings.
            document.body.removeChild(overlay);
            build();
            open();
        }

        gear.addEventListener("click", open);
        closeX.addEventListener("click", close);
        overlay.addEventListener("click", function (e) { if (e.target === overlay) close(); });

        document.body.appendChild(gear);
        document.body.appendChild(overlay);

        window.__mrOpenOptions = open;
    }

    function open() {
        var o = document.getElementById("mr-overlay");
        if (o) o.classList.add("open");
        // pause the game while the menu is open
        if (window.cr_setSuspended) window.cr_setSuspended(true);
    }
    function close() {
        var o = document.getElementById("mr-overlay");
        if (o) o.classList.remove("open");
        if (window.cr_setSuspended) window.cr_setSuspended(false);
    }
    function doQuit() {
        if (window.MRAndroid && window.MRAndroid.quit) {
            window.MRAndroid.quit();
        } else {
            // Fallbacks if the native bridge is unavailable.
            try { window.close(); } catch (e) {}
            try { window.open("", "_self"); window.close(); } catch (e) {}
        }
    }

    if (document.readyState === "loading")
        document.addEventListener("DOMContentLoaded", build);
    else
        build();
})();

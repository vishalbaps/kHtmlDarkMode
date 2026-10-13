/*
 * k_html_dark_mode — the in-page pass.
 *
 * SOURCE OF TRUTH. `dart run tool/generate_script.dart` embeds this file into
 * lib/src/generated/script_source.g.dart. Edit here, then regenerate; a test
 * fails if the two differ.
 *
 * Why it runs in the page: only there is the CSS cascade resolved.
 * getComputedStyle is the sole way to learn which rule won and what background
 * an element actually sits on. Rewriting source text cannot answer either.
 *
 * The colour maths therefore exists twice — here and in lib/src/engine.dart.
 * Every tuning constant and the page background are passed in from Dart, and
 * both implementations are held to test/golden/vectors.json.
 *
 * Defines one function, kdmDarkMode(OPTIONS). The Dart side wraps it in an
 * IIFE and calls it, so nothing leaks into the page's globals except the
 * documented window.kdmReport. Called with { exportsOnly: true } it returns the
 * pure colour functions without touching the DOM: that is how the conformance
 * suite tests the real shipped code rather than a copy.
 *
 * The generator rejects three consecutive single quotes, a closing script
 * tag and an HTML comment opener anywhere in this file.
 */
function kdmDarkMode(OPTIONS) {
  'use strict';

  var CFG = OPTIONS.config;
  var PAGE_RGB = OPTIONS.page;
  var IS_DARK = !!OPTIONS.isDark;
  var FONT_SCALE = typeof OPTIONS.fontScale === 'number' ? OPTIONS.fontScale : 1;
  var VERSION = OPTIONS.version || '';
  var FIT_TO_WIDTH = !!OPTIONS.fitToWidth;
  var TRACE = !!OPTIONS.trace;

  /* ---------------------------------------------------------------- colour */

  function lin(v) { return v <= 0.04045 ? v / 12.92 : Math.pow((v + 0.055) / 1.055, 2.4); }
  function gam(v) {
    if (v <= 0) return 0;
    return v <= 0.0031308 ? 12.92 * v : 1.055 * Math.pow(v, 1 / 2.4) - 0.055;
  }
  function cbrt(v) { return v <= 0 ? 0 : Math.pow(v, 1 / 3); }

  function toOkLab(c) {
    var r = lin(c[0]), g = lin(c[1]), b = lin(c[2]);
    var l = 0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b;
    var m = 0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b;
    var s = 0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b;
    var l_ = cbrt(l), m_ = cbrt(m), s_ = cbrt(s);
    return [
      0.2104542553 * l_ + 0.7936177850 * m_ - 0.0040720468 * s_,
      1.9779984951 * l_ - 2.4285922050 * m_ + 0.4505937099 * s_,
      0.0259040371 * l_ + 0.7827717662 * m_ - 0.8086757660 * s_
    ];
  }

  function fromOkLab(L, A, B) {
    var l_ = L + 0.3963377774 * A + 0.2158037573 * B;
    var m_ = L - 0.1055613458 * A - 0.0638541728 * B;
    var s_ = L - 0.0894841775 * A - 1.2914855480 * B;
    var l = l_ * l_ * l_, m = m_ * m_ * m_, s = s_ * s_ * s_;
    return [
      gam(4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s),
      gam(-1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s),
      gam(-0.0041960863 * l - 0.7034186147 * m + 1.7076147010 * s)
    ];
  }

  function okL(c) { return toOkLab(c)[0]; }
  function okC(c) { var o = toOkLab(c); return Math.sqrt(o[1] * o[1] + o[2] * o[2]); }
  function okH(c) {
    var o = toOkLab(c);
    var d = Math.atan2(o[2], o[1]) * 180 / Math.PI;
    return d < 0 ? d + 360 : d;
  }

  function inGamut(c) {
    for (var i = 0; i < 3; i++) if (c[i] < -0.001 || c[i] > 1.001) return false;
    return true;
  }

  function clamp01(v) { return v < 0 ? 0 : (v > 1 ? 1 : v); }

  /* Mirrors KdmColor.fromOkLch: reduce chroma until inside sRGB, then quantise
     to 8 bits so contrast is measured on the value actually emitted. */
  function q(c) {
    return [Math.round(clamp01(c[0]) * 255) / 255,
            Math.round(clamp01(c[1]) * 255) / 255,
            Math.round(clamp01(c[2]) * 255) / 255];
  }

  function fromOkLch(L, C, H) {
    var rad = H * Math.PI / 180, chroma = C;
    for (var i = 0; i < 48; i++) {
      var c = fromOkLab(L, chroma * Math.cos(rad), chroma * Math.sin(rad));
      if (inGamut(c)) return q(c);
      chroma *= 0.94;
    }
    return q(fromOkLab(L, 0, 0));
  }

  function luminance(c) { return 0.2126 * lin(c[0]) + 0.7152 * lin(c[1]) + 0.0722 * lin(c[2]); }

  function contrast(x, y) {
    var a = luminance(x), b = luminance(y);
    var hi = a > b ? a : b, lo = a > b ? b : a;
    return (hi + 0.05) / (lo + 0.05);
  }

  function over(fg, alpha, bg) {
    return q([
      fg[0] * alpha + bg[0] * (1 - alpha),
      fg[1] * alpha + bg[1] * (1 - alpha),
      fg[2] * alpha + bg[2] * (1 - alpha)
    ]);
  }

  function css(c) {
    function h(v) {
      var s = Math.round(clamp01(v) * 255).toString(16).toUpperCase();
      return s.length < 2 ? '0' + s : s;
    }
    return '#' + h(c[0]) + h(c[1]) + h(c[2]);
  }

  function rgba(c, alpha) {
    return 'rgba(' + Math.round(c[0] * 255) + ',' + Math.round(c[1] * 255) + ',' +
           Math.round(c[2] * 255) + ',' + alpha + ')';
  }

  /* Parses what getComputedStyle returns: rgb()/rgba(), plus hex and the
     keywords that can appear in an author stylesheet. Returns [r,g,b,a] in 0..1
     or null when the value must be left alone. */
  function parseColor(v) {
    if (!v) return null;
    var s = String(v).trim().toLowerCase();
    if (!s || s === 'transparent' || s === 'inherit' || s === 'currentcolor' ||
        s === 'initial' || s === 'unset' || s === 'none') return null;
    if (s.indexOf('var(') === 0 || s.indexOf('url(') !== -1) return null;

    var m = s.match(/^rgba?\(\s*([\d.]+)[\s,]+([\d.]+)[\s,]+([\d.]+)(?:[\s,/]+([\d.%]+))?\s*\)$/);
    if (m) {
      var a = 1;
      if (m[4] !== undefined) {
        a = m[4].indexOf('%') !== -1 ? parseFloat(m[4]) / 100 : parseFloat(m[4]);
      }
      return [+m[1] / 255, +m[2] / 255, +m[3] / 255, a];
    }
    if (s.charAt(0) === '#') {
      var hex = s.slice(1);
      if (hex.length === 3 || hex.length === 4) {
        hex = hex.split('').map(function (ch) { return ch + ch; }).join('');
      }
      if (hex.length !== 6 && hex.length !== 8) return null;
      if (!/^[0-9a-f]+$/.test(hex)) return null;
      var p = [];
      for (var i = 0; i < hex.length; i += 2) p.push(parseInt(hex.substr(i, 2), 16) / 255);
      return [p[0], p[1], p[2], p.length === 4 ? p[3] : 1];
    }
    return null;
  }

  /* ---------------------------------------------------------------- engine */

  function sameColour(a, b) {
    if (!a || !b) return false;
    for (var i = 0; i < 3; i++) {
      if (Math.round(a[i] * 255) !== Math.round(b[i] * 255)) return false;
    }
    return true;
  }

  /* Mirrors KdmEngine.classify in dark mode. No lightness ceiling: chroma alone
     separates a brand colour from a pale tint, and a ceiling breaks warm ramps
     in half. */
  function classify(c) {
    if (okL(c) <= CFG.darkPassthroughOkL) return 'alreadyDark';
    if (okC(c) >= CFG.brandFillMinChroma) return 'brandFill';
    return 'remapped';
  }

  /* Mirrors KdmEngine._cappedSurface. */
  function cappedSurface(L, c, h) {
    var out = fromOkLch(L, c, h), guard = 0;
    while (luminance(out) > CFG.surfaceMaxLuminance && L > 0 && guard < 200) {
      L -= 0.004; guard++;
      out = fromOkLch(L, c, h);
    }
    return out;
  }

  /* Mirrors KdmEngine.mapSurface, including I6 and the I1 separation. Returns
     the very same array when the colour is left alone, which callers rely on. */
  function mapSurface(authored, parent, parentAuthored) {
    if (classify(authored) !== 'remapped') return authored;

    /* I6: an element repeating its parent's authored background is not a new
       surface. Without this, table-nested email builds a staircase. */
    if (parent && parentAuthored && sameColour(authored, parentAuthored)) return parent;

    var hue = okH(authored);
    var chroma = Math.min(okC(authored) * CFG.surfaceChromaFactor, CFG.surfaceChromaCap);
    var t = (okL(authored) - CFG.darkPassthroughOkL) / (1 - CFG.darkPassthroughOkL);
    t = t < 0 ? 0 : (t > 1 ? 1 : t);
    var L = okL(PAGE_RGB) + CFG.surfaceLiftOkL + t * CFG.surfaceRangeOkL;
    var out = cappedSurface(L, chroma, hue);
    if (!parent) return out;

    /* Separation is owed only where the author drew a visible step, and it
       moves in the direction the author drew it. */
    if (parentAuthored && contrast(authored, parentAuthored) < CFG.surfaceSeparation) return out;
    var step = (!parentAuthored || okL(authored) >= okL(parentAuthored)) ? 0.005 : -0.005;
    var guard = 0;
    while (contrast(out, parent) < CFG.surfaceSeparation &&
           L < CFG.surfaceCeilingOkL && L > 0 && guard < 300) {
      L += step; guard++;
      var next = cappedSurface(L, chroma, hue);
      if (sameColour(next, out)) break;
      out = next;
    }
    return out;
  }

  /* Mirrors KdmEngine.solveForeground: I5 no-op, then invert, then repair.
     Inverting rather than solving to the nearest passing value is what keeps a
     typographic hierarchy from collapsing onto one grey. */
  function solveForeground(authored, bg, target) {
    if (contrast(authored, bg) >= target) return authored;
    var hue = okH(authored), chroma = okC(authored);

    var inverted = fromOkLch(
      CFG.textFloorOkL + (1 - okL(authored)) * CFG.textRangeOkL, chroma, hue);
    if (contrast(inverted, bg) >= target) return inverted;

    var preferLighter = luminance(bg) < CFG.surfaceMaxLuminance;
    var L = okL(inverted);
    for (var i = 0; i < 400; i++) {
      L += preferLighter ? 0.0025 : -0.0025;
      if (L <= 0 || L >= 1) break;
      var c = fromOkLch(L, chroma, hue);
      if (contrast(c, bg) >= target) return c;
    }
    return preferLighter ? [1, 1, 1] : [0, 0, 0];
  }

  /* Mirrors KdmEngine.mapShadow. A shadow that lightens in dark mode reads as
     a glow, so shadows are driven down rather than up. */
  function mapShadow(c) {
    return fromOkLch(okL(c) * 0.35, Math.min(okC(c), CFG.surfaceChromaCap), okH(c));
  }

  /* Mirrors KdmEngine.mapBorder for an opaque colour. Borders move toward the
     page rather than away from it: a subtle hairline must stay subtle. Returns
     the very same array when the border is left alone. */
  function mapBorder(c, bg) {
    if (okL(c) <= CFG.darkPassthroughOkL || classify(c) === 'brandFill') return c;
    var t = Math.min(okL(bg) + 0.10, 0.55);
    return fromOkLch(t, Math.min(okC(c), CFG.surfaceChromaCap), okH(c));
  }

  /* Mirrors KdmEngine.targetFor. */
  function targetForSize(px, bold) {
    var large = px >= 24 || (bold && px >= 18.66);
    return large ? CFG.largeTextContrast : CFG.textContrast;
  }

  var COLOUR_TOKEN = /rgba?\([^)]*\)|#[0-9a-fA-F]{3,8}\b/g;

  /* Maps each colour stop with the surface rules; a brand gradient is left
     alone because its stops are brand fills. */
  function mapGradient(value, parentBg) {
    return value.replace(COLOUR_TOKEN, function (tok) {
      var c = parseColor(tok);
      if (!c) return tok;
      var opaque = c[3] < 0.999 ? over(c, c[3], parentBg) : [c[0], c[1], c[2]];
      var mapped = mapSurface(opaque, null, null);
      if (mapped === opaque) return tok;
      return c[3] < 0.999 ? rgba(mapped, c[3]) : css(mapped);
    });
  }

  /* Average of the colours a gradient resolves to, so text drawn on top can be
     solved against what it actually sits on. */
  function gradientAverage(value, parentBg) {
    var toks = value.match(COLOUR_TOKEN);
    if (!toks || !toks.length) return null;
    var acc = [0, 0, 0], n = 0;
    for (var i = 0; i < toks.length; i++) {
      var c = parseColor(toks[i]);
      if (!c) continue;
      var opaque = c[3] < 0.999 ? over(c, c[3], parentBg) : [c[0], c[1], c[2]];
      var m = mapSurface(opaque, null, null);
      acc[0] += m[0]; acc[1] += m[1]; acc[2] += m[2]; n++;
    }
    return n ? q([acc[0] / n, acc[1] / n, acc[2] / n]) : null;
  }

  function mapShadowValue(value) {
    return value.replace(COLOUR_TOKEN, function (tok) {
      var c = parseColor(tok);
      if (!c) return tok;
      var m = mapShadow([c[0], c[1], c[2]]);
      return c[3] < 0.999 ? rgba(m, c[3]) : css(m);
    });
  }

  var api = {
    classify: classify, mapSurface: mapSurface, solveForeground: solveForeground,
    mapShadow: mapShadow, mapBorder: mapBorder, targetForSize: targetForSize,
    mapGradient: mapGradient, gradientAverage: gradientAverage, mapShadowValue: mapShadowValue,
    over: over, css: css, parseColor: parseColor, fromOkLch: fromOkLch,
    okL: okL, okC: okC, okH: okH, luminance: luminance, contrast: contrast
  };
  if (OPTIONS.exportsOnly) return api;

  /* ------------------------------------------------------------------ page */

  var root = document.documentElement;
  root.setAttribute('data-kdm-theme', IS_DARK ? 'dark' : 'light');
  root.setAttribute('data-kdm-version', VERSION);

  /* Raster and embedded content is never recoloured — a photograph must stay a
     photograph. SVG is deliberately absent: it is vector artwork we can reason
     about, and leaving it alone strands black icons on dark surfaces. */
  var SKIP_TAGS = { IMG: 1, VIDEO: 1, AUDIO: 1, CANVAS: 1, IFRAME: 1, PICTURE: 1, SOURCE: 1, OBJECT: 1, EMBED: 1 };

  /* Never painted, so never recoloured, rescaled or counted. */
  var NON_RENDERED = { SCRIPT: 1, STYLE: 1, TEMPLATE: 1, NOSCRIPT: 1 };

  var BORDERS = [
    ['borderTopWidth', 'borderTopColor', 'border-top-color'],
    ['borderRightWidth', 'borderRightColor', 'border-right-color'],
    ['borderBottomWidth', 'borderBottomColor', 'border-bottom-color'],
    ['borderLeftWidth', 'borderLeftColor', 'border-left-color']
  ];

  function isSvg(el) { return el.namespaceURI === 'http://www.w3.org/2000/svg'; }

  /* Only an element that paints text itself is recoloured or rescaled, so a
     container's colour is never solved against the wrong background. */
  function hasOwnText(el) {
    var n = el.childNodes;
    for (var i = 0; i < n.length; i++) {
      if (n[i].nodeType === 3 && n[i].nodeValue && n[i].nodeValue.trim().length) return true;
    }
    return false;
  }

  /* True for anything the package injected: it sits between our marker
     comments. Lets author-dark detection ignore a host's own CSS. */
  function insideOurBlock(node) {
    for (var n = node && node.previousSibling; n; n = n.previousSibling) {
      if (n.nodeType === 8) {
        var v = String(n.nodeValue).trim();
        if (v === 'kdm:head' || v === 'kdm:body') return true;
        if (v === '/kdm:head' || v === '/kdm:body') return false;
      }
    }
    return false;
  }

  /* Dispatched after parsing finishes, so a listener a host adds after this
     script — in its own body-end script — still hears it. */
  function emit(name, detail) {
    function fire() {
      try { window.dispatchEvent(new CustomEvent(name, { detail: detail })); } catch (e) { /* ignore */ }
    }
    if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', fire);
    else fire();
  }

  /* What actually arrived in the document. A template can lose elements to a
     sanitiser between authoring and delivery; without a census the only
     symptom is something quietly missing from the render. */
  function census() {
    try {
      var c = {};
      ['img', 'svg', 'table', 'style', 'video', 'audio', 'iframe'].forEach(function (t) {
        var n = document.getElementsByTagName(t).length;
        if (n) c[t] = n;
      });
      return c;
    } catch (e) { return null; }
  }

  var stats = { surfaces: 0, texts: 0, skipped: 0, untouched: 0, scaled: 0 };
  var trace = [];

  /* Hands the decision back to the host. The pass can stop for perfectly good
     reasons, and without this the only way to tell which one is to attach a
     remote debugger to a web view on a device. */
  function report(source) {
    var detail = { v: VERSION, source: source, stats: stats, dom: census(), trace: TRACE ? trace : null };
    root.setAttribute('data-kdm-source', source);
    root.setAttribute('data-kdm-stats', JSON.stringify(stats));
    try { window.kdmReport = detail; } catch (e) { /* ignore */ }
    emit('kdm:report', detail);
  }

  function traceSurface(authored, mapped, kind, label) {
    if (trace.length >= 40) return;
    trace.push({ el: label, a: css(authored), m: css(mapped), k: kind });
  }

  /* ------------------------------------------------------- layout reporting */

  /* Optionally scales content wider than the viewport down to fit, then tells
     the host how tall the document is. Runs after the colour pass, so the
     height reflects the recoloured, rescaled layout. */
  var lastLayout = null;

  function layout() {
    var scale = 1;
    if (FIT_TO_WIDTH) {
      var wrap = document.getElementById('kdm-root');
      var content = document.getElementById('kdm-content');
      if (wrap && content) {
        /* Measure before writing anything. An element's own transform does not
           change its layout box, so its natural width and height can be read
           as they stand — resetting first would re-lay-out the whole content
           on every resize and image load, twice. */
        var vw = document.documentElement.clientWidth;
        var cw = content.scrollWidth;
        scale = (cw > vw && cw > 0) ? vw / cw : 1;
        /* Only clamp the height when scaling down; otherwise leave it natural
           so the last line is never cut off by a sub-pixel rounding. */
        var transform = scale < 1 ? 'scale(' + scale + ')' : 'none';
        var height = scale < 1 ? Math.ceil(content.offsetHeight * scale) + 'px' : 'auto';
        if ((content.style.transform || 'none') !== transform) content.style.transform = transform;
        if ((wrap.style.height || 'auto') !== height) wrap.style.height = height;
      }
    }
    var h = document.body ? document.body.scrollHeight : 0;
    /* Several triggers fire for one change (DOMContentLoaded, load, the
       observer); the host hears each distinct size once. */
    if (lastLayout && lastLayout.height === h && lastLayout.scale === scale) return;
    lastLayout = { height: h, scale: scale };
    try { window.kdmLayout = lastLayout; } catch (e) { /* ignore */ }
    emit('kdm:layout', lastLayout);
  }

  try {
    window.addEventListener('load', layout);
    window.addEventListener('resize', layout);
    document.addEventListener('DOMContentLoaded', layout);
    if (typeof ResizeObserver !== 'undefined') {
      var observed = (FIT_TO_WIDTH && document.getElementById('kdm-content')) || document.body;
      if (observed) new ResizeObserver(layout).observe(observed);
    }
  } catch (e) { /* layout reporting is a convenience; never block rendering */ }

  /* ------------------------------------------------------- font scaling pass */

  /* A font-size setting must scale a template that sizes text in px, which is
     almost all of them. Scaling the root only affects rem, so each element's
     resolved font size is multiplied instead.

     Two passes on purpose: reading a child's computed size after its parent
     has already been rewritten would inherit the scaled value and scale it
     twice. Collect every original size first, then write. Multiplying the
     resolved value preserves the template's typographic hierarchy exactly. */
  function scaleFonts() {
    if (!FONT_SCALE || Math.abs(FONT_SCALE - 1) < 0.001) return 0;
    var all = document.body ? document.body.querySelectorAll('*') : [];
    var jobs = [];
    for (var i = 0; i < all.length; i++) {
      var el = all[i];
      if (SKIP_TAGS[el.tagName] || NON_RENDERED[el.tagName]) continue;
      if (!hasOwnText(el)) continue;
      var px = parseFloat(getComputedStyle(el).fontSize);
      if (px > 0) jobs.push([el, px]);
    }
    for (var j = 0; j < jobs.length; j++) {
      jobs[j][0].style.setProperty('font-size', (jobs[j][1] * FONT_SCALE).toFixed(2) + 'px', 'important');
    }
    return jobs.length;
  }

  /* ------------------------------------------------ author dark-mode opt-out */

  /* Inspects real CSS rules rather than matching text, so the phrase appearing
     in a comment or a text node cannot switch the engine off.

     The package injects color-scheme twice before this runs — as a meta and in
     the pre-paint CSS — so UA widgets, scrollbars and the pre-paint canvas
     match the theme. Both look exactly like an author declaring their own dark
     mode, and detecting either one would switch the pass off on every message.
     Everything the package injects carries an id or sits between marker
     comments; it is skipped, and only what the author wrote is judged. */
  function authorHandlesDark() {
    var sheets = document.styleSheets;
    for (var i = 0; i < sheets.length; i++) {
      var owner = sheets[i].ownerNode;
      if (owner && (owner.id === 'kdm-theme-css' || insideOurBlock(owner))) continue;
      var rules;
      try { rules = sheets[i].cssRules; } catch (e) { continue; }
      if (!rules) continue;
      for (var j = 0; j < rules.length; j++) {
        var r = rules[j];
        if (r.type === 4 /* CSSMediaRule */ && r.conditionText &&
            r.conditionText.indexOf('prefers-color-scheme') !== -1) return true;
        if (r.style && r.style.getPropertyValue &&
            r.style.getPropertyValue('color-scheme').indexOf('dark') !== -1) return true;
      }
    }
    var metas = document.querySelectorAll('meta[name="color-scheme"]');
    for (var k = 0; k < metas.length; k++) {
      if (metas[k].id === 'kdm-color-scheme' || insideOurBlock(metas[k])) continue;
      if ((metas[k].getAttribute('content') || '').indexOf('dark') !== -1) return true;
    }
    return false;
  }

  /* Font scaling is independent of colour: it must happen even when the
     author owns dark mode, and in light mode. */
  try { stats.scaled = scaleFonts(); } catch (e) { /* text stays at its authored size */ }

  if (!IS_DARK) { report('light'); return; }
  if (authorHandlesDark()) { report('author'); return; }

  /* ------------------------------------------------------------------ pass */

  /* Writes are split by whether the property is inherited.

     color, fill and stroke ARE inherited: a child's text decision reads the
     colour its parent was just given, so those are written immediately.

     background-color, background-image, box-shadow and border colours are
     NOT inherited, so no later read in the walk can observe them. They are
     queued and written in one batch at the end. Each immediate write
     invalidates style, and the next getComputedStyle read pays for the
     recalc — queueing removes most of those recalcs without changing a single
     decision. */
  var queued = [];
  function paintLater(el, prop, value) { queued.push(el, prop, value); }
  function flush() {
    for (var i = 0; i < queued.length; i += 3) queued[i].style.setProperty(queued[i + 1], queued[i + 2], 'important');
    queued = [];
  }

  function walk(el, parentBg, parentAuthoredBg) {
    if (NON_RENDERED[el.tagName]) return;
    if (el.hasAttribute && el.hasAttribute('data-kdm-preserve')) { stats.skipped++; return; }

    var effectiveBg = parentBg;
    var effectiveAuthoredBg = parentAuthoredBg;

    if (!SKIP_TAGS[el.tagName]) {
      var cs = getComputedStyle(el);

      /* --- background ------------------------------------------------------ */
      var bg = parseColor(cs.backgroundColor);
      if (bg && bg[3] > 0.001) {
        var opaque = bg[3] < 0.999 ? over(bg, bg[3], parentBg) : [bg[0], bg[1], bg[2]];
        var mapped = mapSurface(opaque, parentBg, parentAuthoredBg);
        if (TRACE) {
          traceSurface(opaque, mapped,
            (mapped === opaque) ? classify(opaque) : (mapped === parentBg ? 'inherited' : 'remapped'),
            el.tagName.toLowerCase() + (el.className ? '.' + String(el.className).split(' ')[0] : ''));
        }
        effectiveBg = mapped;
        /* The authored colour is what the next level compares against, so that
           a child repeating this background is recognised as not a new surface
           (I6). It must be the authored value, not the mapped one. */
        effectiveAuthoredBg = opaque;
        if (mapped !== opaque) {
          /* A translucent authored fill is replaced with the opaque mapped
             colour: the alpha has already been accounted for. */
          paintLater(el, 'background-color', css(mapped));
          stats.surfaces++;
        } else {
          stats.untouched++;
        }
      }

      /* --- gradients ------------------------------------------------------- */
      var bi = cs.backgroundImage;
      if (bi && bi !== 'none' && bi.indexOf('gradient') !== -1 && bi.indexOf('url(') === -1) {
        var mappedBi = mapGradient(bi, parentBg);
        if (mappedBi !== bi) paintLater(el, 'background-image', mappedBi);
        /* A background shorthand resets background-color to transparent, so a
           gradient element otherwise reports no backdrop at all and its text is
           solved against the container behind it. Use the gradient's own mapped
           average instead — that is what the text actually sits on.

           Not for a brand gradient: those pass through unchanged, so the
           author's text/gradient pairing is exactly what light mode shows, and
           the two modes never disagree about a deliberate choice. */
        var avg = gradientAverage(bi, parentBg);
        if (avg && classify(avg) !== 'brandFill') {
          effectiveBg = avg;
          effectiveAuthoredBg = null;
        }
      }

      /* --- shadows --------------------------------------------------------- */
      var sh = cs.boxShadow;
      if (sh && sh !== 'none') {
        var mappedSh = mapShadowValue(sh);
        if (mappedSh !== sh) paintLater(el, 'box-shadow', mappedSh);
      }

      /* --- borders --------------------------------------------------------- */
      /* Reading computed style is the dominant cost of the whole pass, and
         most elements have no border at all: one shorthand read answers that
         for all four sides. Any other answer — including a browser that does
         not serialise the shorthand — falls through to the per-side reads. */
      if (cs.borderWidth !== '0px') {
        for (var b = 0; b < 4; b++) {
          var side = BORDERS[b];
          if (!((parseFloat(cs[side[0]]) || 0) > 0)) continue;
          var bc = parseColor(cs[side[1]]);
          if (!bc || bc[3] < 0.05) continue;
          var oc = bc[3] < 0.999 ? over(bc, bc[3], effectiveBg) : [bc[0], bc[1], bc[2]];
          var nb = mapBorder(oc, effectiveBg);
          if (nb !== oc) paintLater(el, side[2], css(nb));
        }
      }

      /* --- svg paint ------------------------------------------------------- */
      /* An icon's fill behaves like text: it has to read against the surface
         behind it. A brand-coloured mark is left alone on the same rule that
         protects a brand fill, so a logo keeps its colours. */
      if (isSvg(el)) {
        ['fill', 'stroke'].forEach(function (prop) {
          var raw = cs[prop];
          if (!raw || raw === 'none') return;
          var pc = parseColor(raw);
          if (!pc || pc[3] < 0.05) return;
          var oc = pc[3] < 0.999 ? over(pc, pc[3], effectiveBg) : [pc[0], pc[1], pc[2]];
          if (classify(oc) === 'brandFill') return;
          var solved = solveForeground(oc, effectiveBg, CFG.largeTextContrast);
          if (solved !== oc) {
            el.style.setProperty(prop, css(solved), 'important');
            stats.texts++;
          } else {
            stats.untouched++;
          }
        });
      }

      /* --- text ------------------------------------------------------------ */
      if (hasOwnText(el)) {
        var fg = parseColor(cs.color);
        if (fg && fg[3] > 0.05) {
          var ofg = fg[3] < 0.999 ? over(fg, fg[3], effectiveBg) : [fg[0], fg[1], fg[2]];
          var weight = cs.fontWeight;
          var bold = weight === 'bold' || weight === 'bolder' || (parseInt(weight, 10) || 400) >= 600;
          var target = targetForSize(parseFloat(cs.fontSize) || 16, bold);
          var solvedFg = solveForeground(ofg, effectiveBg, target);
          if (solvedFg !== ofg) {
            el.style.setProperty('color', css(solvedFg), 'important');
            stats.texts++;
          } else {
            stats.untouched++;
          }
        }
      }
    } else {
      stats.skipped++;
    }

    var kids = el.children;
    for (var i = 0; i < kids.length; i++) walk(kids[i], effectiveBg, effectiveAuthoredBg);
  }

  try {
    walk(document.body, PAGE_RGB, null);
    flush();
    report('engine');
  } catch (e) {
    /* Never blank the content because the transform failed — keep what was
       decided so far (text already corrected needs its surfaces) and say why. */
    try { flush(); } catch (e2) { /* ignore */ }
    root.setAttribute('data-kdm-error', String((e && e.message) || e));
    report('error');
  }
  return api;
}

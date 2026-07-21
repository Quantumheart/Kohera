// Faithful JS port of lib/shared/widgets/kohera_loader.dart (_MyceliumPulsePainter).
// Same 32x32 mask, same 5 legs, same spark/spore/gill model. Driven by the
// --kohera-loader-color CSS var; window.setKoheraLoaderColor(hex) recolors at
// runtime (called from lib/core/services/web_shell_sync_web.dart).
(function () {
  const GRID = 32;
  const SAMPLES = 16;
  const TRAVEL = 0.72;
  const TRAIL = 5;
  const TRAIL_STEP = 0.055;
  const CYCLE_MS = 1100;

  const SPORE_COUNT = 6;
  const SPORE_SPAWN_GY = 9.5;
  const SPORE_FALL = 9;
  const SPORE_GX = [6, 9, 11, 21, 23, 25];
  const GILL_GX = [7, 10, 13, 19, 22, 25];
  const GILL_ROWS = [9, 10];
  const CAP_SOURCE = [50, 4];

  // Each leg: its own segments (origin = segs[0][0]); tip is the last node.
  const LEGS = [
    { segs: [[[47.8, 50], [47, 62], [30, 75], [11, 89]]], tip: [11, 89] },
    { segs: [[[49.15, 50], [48.5, 63], [37, 80], [30, 90]]], tip: [30, 90] },
    {
      segs: [
        [[50.5, 50], [50.5, 58], [51, 65], [51, 71]],
        [[51, 71], [50.5, 80], [50, 88], [50, 96]],
      ],
      tip: [50, 96],
    },
    { segs: [[[51.85, 50], [52.5, 63], [64, 78], [71, 90]]], tip: [71, 90] },
    { segs: [[[53.2, 50], [54, 62], [72, 74], [90, 89]]], tip: [90, 89] },
  ];

  function cubicPoint(c, u) {
    const mu = 1 - u;
    const a = mu * mu * mu;
    const b = 3 * mu * mu * u;
    const cc = 3 * mu * u * u;
    const d = u * u * u;
    return [
      a * c[0][0] + b * c[1][0] + cc * c[2][0] + d * c[3][0],
      a * c[0][1] + b * c[1][1] + cc * c[2][1] + d * c[3][1],
    ];
  }

  function segLen(c) {
    let len = 0;
    let prev = c[0];
    for (let i = 1; i <= SAMPLES; i++) {
      const p = cubicPoint(c, i / SAMPLES);
      len += Math.hypot(p[0] - prev[0], p[1] - prev[1]);
      prev = p;
    }
    return len;
  }

  function buildFire(leg) {
    const origin = leg.segs[0][0];
    const capSeg = [CAP_SOURCE, [50, 31], [52, 45], origin];
    const fire = [capSeg].concat(leg.segs);
    const lens = fire.map(segLen);
    const total = lens.reduce((a, b) => a + b, 0);
    return { fire: fire, lens: lens, total: total, tip: leg.tip };
  }

  function pointAtDistance(c, dist, len) {
    if (len <= 0) return c[3];
    let prev = c[0];
    let acc = 0;
    for (let i = 1; i <= SAMPLES; i++) {
      const p = cubicPoint(c, i / SAMPLES);
      const step = Math.hypot(p[0] - prev[0], p[1] - prev[1]);
      if (acc + step >= dist) {
        const f = step === 0 ? 0 : Math.max(0, Math.min(1, (dist - acc) / step));
        return [prev[0] + (p[0] - prev[0]) * f, prev[1] + (p[1] - prev[1]) * f];
      }
      acc += step;
      prev = p;
    }
    return c[3];
  }

  function legPoint(built, t) {
    let d = Math.max(0, Math.min(1, t)) * built.total;
    for (let i = 0; i < built.fire.length; i++) {
      const len = built.lens[i];
      if (d <= len || i === built.fire.length - 1) {
        return pointAtDistance(built.fire[i], Math.min(d, len), len);
      }
      d -= len;
    }
    return built.tip;
  }

  function cell(p) {
    return [
      Math.max(0, Math.min(GRID - 1, Math.floor((p[0] * GRID) / 100))),
      Math.max(0, Math.min(GRID - 1, Math.floor((p[1] * GRID) / 100))),
    ];
  }

  const BLACK = [0, 0, 0];
  const WHITE = [255, 255, 255];

  function hexToRgb(h) {
    h = h.replace('#', '');
    if (h.length === 3) {
      h = h[0] + h[0] + h[1] + h[1] + h[2] + h[2];
    }
    return [
      parseInt(h.slice(0, 2), 16),
      parseInt(h.slice(2, 4), 16),
      parseInt(h.slice(4, 6), 16),
    ];
  }

  function lerp(a, b, t) {
    return a + (b - a) * t;
  }

  function lerpColor(c1, c2, t) {
    return [lerp(c1[0], c2[0], t), lerp(c1[1], c2[1], t), lerp(c1[2], c2[2], t)];
  }

  function rgb(c) {
    return 'rgb(' + (c[0] | 0) + ',' + (c[1] | 0) + ',' + (c[2] | 0) + ')';
  }

  const BUILT = LEGS.map(buildFire);
  let base = null;
  let gill = null;
  let spore = null;
  let light = null;
  let activeLeg = Math.floor(Math.random() * LEGS.length);
  let lastProgress = 0;

  const NS = 'http://www.w3.org/2000/svg';
  let gillsG = null;
  let sporesG = null;
  let sparkG = null;

  function clear(g) {
    while (g.firstChild) g.removeChild(g.firstChild);
  }

  function addRect(g, x, y, fill, alpha) {
    const r = document.createElementNS(NS, 'rect');
    r.setAttribute('x', x);
    r.setAttribute('y', y);
    r.setAttribute('width', 1);
    r.setAttribute('height', 1);
    r.setAttribute('fill', fill);
    if (alpha !== undefined && alpha < 1) r.setAttribute('fill-opacity', alpha);
    g.appendChild(r);
  }

  function setBase(hex) {
    base = hexToRgb(hex);
    gill = lerpColor(base, BLACK, 0.35);
    spore = lerpColor(base, WHITE, 0.5);
    light = lerpColor(base, WHITE, 0.9);
    clear(gillsG);
    for (const gx of GILL_GX) {
      for (const gy of GILL_ROWS) {
        addRect(gillsG, gx, gy, rgb(gill));
      }
    }
  }

  function drawSpores(progress) {
    for (let i = 0; i < SPORE_COUNT; i++) {
      const local = (progress + i / SPORE_COUNT) % 1;
      const gy = Math.round(SPORE_SPAWN_GY + SPORE_FALL * local);
      const drift = (SPORE_GX[i] - 16) * 0.18 * local;
      const gx = Math.round(SPORE_GX[i] + drift);
      let alpha = 1;
      if (local < 0.12) {
        alpha = local / 0.12;
      } else if (local > 0.65) {
        alpha = Math.max(0, (1 - local) / 0.35);
      }
      addRect(sporesG, gx, gy, rgb(spore), alpha);
    }
  }

  function drawPulse(progress) {
    let t = progress / TRAVEL;
    if (t < 0) t = 0;
    if (t > 1) t = 1;
    if (t <= 0 || t >= 1) return;
    const b = BUILT[activeLeg];
    const fade = t < 0.12 ? t / 0.12 : 1;
    for (let i = 0; i <= TRAIL; i++) {
      const tt = t - i * TRAIL_STEP;
      if (tt < 0) break;
      const c = cell(legPoint(b, tt));
      const col = lerpColor(light, base, i / TRAIL);
      addRect(sparkG, c[0], c[1], rgb(col), fade);
    }
    let arrival = (t - 0.82) / 0.18;
    if (arrival < 0) arrival = 0;
    if (arrival > 1) arrival = 1;
    if (arrival > 0) {
      const tip = cell(b.tip);
      const flashAlpha = 1 - arrival;
      const fill = rgb(light);
      const offsets = [[0, 0], [1, 0], [-1, 0], [0, 1], [0, -1]];
      for (const o of offsets) {
        addRect(sparkG, tip[0] + o[0], tip[1] + o[1], fill, flashAlpha);
      }
    }
  }

  function nextLeg() {
    const n = Math.floor(Math.random() * (LEGS.length - 1));
    return n >= activeLeg ? n + 1 : n;
  }

  let startTs = null;
  function frame(ts) {
    if (startTs === null) startTs = ts;
    const progress = ((ts - startTs) % CYCLE_MS) / CYCLE_MS;
    if (progress < lastProgress) activeLeg = nextLeg();
    lastProgress = progress;
    clear(sporesG);
    clear(sparkG);
    drawSpores(progress);
    drawPulse(progress);
    requestAnimationFrame(frame);
  }

  function init() {
    const svg = document.getElementById('loading');
    if (!svg) return;
    gillsG = svg.querySelector('#kohera-gills');
    sporesG = svg.querySelector('#kohera-spores');
    sparkG = svg.querySelector('#kohera-spark');
    const css = getComputedStyle(document.documentElement)
      .getPropertyValue('--kohera-loader-color')
      .trim();
    setBase(css || '#1976D2');
    requestAnimationFrame(frame);
  }

  window.setKoheraLoaderColor = function (hex) {
    document.documentElement.style.setProperty('--kohera-loader-color', hex);
    if (base) setBase(hex);
  };

  window.addEventListener('flutter-first-frame', function () {
    const el = document.getElementById('loading');
    if (el) el.remove();
  });

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', init);
  } else {
    init();
  }
})();

// Safe-area probe: Flutter web does not read env(safe-area-inset-*) into
// MediaQuery.padding (engine defaults ViewPadding.zero). This probe resolves
// the insets via CSS and exposes them to Dart (web_shell_sync_web.dart), which
// injects them into MediaQuery.padding at the root so SafeArea / paddingOf
// work on iOS/Android PWA. Requires viewport-fit=cover (set in index.html).
(function () {
  const probe = document.createElement('div');
  probe.id = 'kohera-safe-area-probe';
  probe.style.cssText =
    'position:fixed;top:0;left:0;width:0;height:0;visibility:hidden;' +
    'padding-top:env(safe-area-inset-top);' +
    'padding-right:env(safe-area-inset-right);' +
    'padding-bottom:env(safe-area-inset-bottom);' +
    'padding-left:env(safe-area-inset-left);';
  document.documentElement.appendChild(probe);

  function px(v) {
    const n = parseFloat(v);
    return isNaN(n) ? 0 : n;
  }

  window.koheraSafeAreaInsets = function () {
    const s = getComputedStyle(probe);
    return {
      top: px(s.paddingTop),
      right: px(s.paddingRight),
      bottom: px(s.paddingBottom),
      left: px(s.paddingLeft),
    };
  };
})();
// GENERATED from frontend2/src/lib/festivalThemes.js by `npm run sync:festival` — do not edit here.
// Needs tsParticles 3.9.1 (tsparticles.bundle.min.js) loaded first.
(function () {
// Festival effect themes (tsParticles options + vector artwork).
//
// SAME FILE is copied (as a plain script) to the backend for the admin
// preview: Web_Backend/wwwroot/js/festival-themes.js — run
// `npm run sync:festival` in frontend2 after editing.
//
// Every theme returns tsParticles v3 options for a non-fullscreen container,
// except NewYear which uses the custom fireworks renderer in festivalFx.js.

const svg = (body, w = 64, h = 64) =>
  'data:image/svg+xml;utf8,' +
  encodeURIComponent(`<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 ${w} ${h}">${body}</svg>`)

// ---------- artwork ----------
const ART = {
  snowflake: svg(
    `<g stroke="#fff" stroke-width="3.2" stroke-linecap="round" fill="none">
      ${[0, 60, 120].map((r) => `<g transform="rotate(${r} 32 32)"><path d="M32 6v52"/><path d="M32 14l-6-6M32 14l6-6M32 50l-6 6M32 50l6 6"/></g>`).join('')}
    </g>`,
  ),
  chineseLantern: svg(
    `<defs><radialGradient id="g" cx="40%" cy="40%" r="70%"><stop offset="0" stop-color="#ff6b5a"/><stop offset=".6" stop-color="#e3261b"/><stop offset="1" stop-color="#a5110c"/></radialGradient></defs>
     <path d="M32 2v6" stroke="#c99a2e" stroke-width="2"/>
     <rect x="20" y="8" width="24" height="6" rx="2" fill="#f2c14e"/>
     <ellipse cx="32" cy="34" rx="22" ry="20" fill="url(#g)"/>
     <path d="M32 14c-8 6-8 34 0 40M32 14c8 6 8 34 0 40M18 20c-4 8-4 20 0 28M46 20c4 8 4 20 0 28" stroke="#ffd166" stroke-opacity=".55" stroke-width="1.4" fill="none"/>
     <rect x="20" y="52" width="24" height="5" rx="2" fill="#f2c14e"/>
     <path d="M32 57v6M28 57l-1 5M36 57l1 5" stroke="#f2c14e" stroke-width="1.6"/>`,
    64, 66,
  ),
  redEnvelope: svg(
    `<rect x="12" y="6" width="40" height="54" rx="5" fill="#d7261e"/>
     <path d="M12 14q20 14 40 0" fill="#b81c15"/>
     <circle cx="32" cy="24" r="7" fill="#f6c453"/><text x="32" y="28" font-size="9" text-anchor="middle" fill="#b81c15" font-family="serif">福</text>`,
  ),
  goldSpark: svg(
    `<path d="M32 4c2 18 10 26 28 28-18 2-26 10-28 28-2-18-10-26-28-28 18-2 26-10 28-28z" fill="#ffd166"/>`,
  ),
  petal: (c1, c2) =>
    svg(
      `<defs><linearGradient id="p" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="${c1}"/><stop offset="1" stop-color="${c2}"/></linearGradient></defs>
       <path d="M32 4C48 18 52 38 32 60 12 38 16 18 32 4z" fill="url(#p)"/>
       <path d="M32 10v44" stroke="#fff" stroke-opacity=".35" stroke-width="1.5"/>`,
    ),
  leaf: svg(
    `<path d="M10 54C10 24 30 8 56 8c0 26-16 46-46 46z" fill="#3f9d4a"/><path d="M12 52L50 14" stroke="#cdeccf" stroke-opacity=".7" stroke-width="2"/>`,
  ),
  vesakLantern: svg(
    `<path d="M32 2v6" stroke="#ccc" stroke-width="1.5"/>
     <path d="M32 8L54 26 32 44 10 26z" fill="#ffe08a"/>
     <path d="M32 8L54 26H10z" fill="#ffb84d"/>
     <path d="M32 8v36M10 26h44" stroke="#fff" stroke-opacity=".6" stroke-width="1.2"/>
     <path d="M18 34l-4 26M24 38l-2 24M32 44v20M40 38l2 24M46 34l4 26" stroke-width="2.2" stroke-linecap="round"
       stroke="url(#t)"/>
     <defs><linearGradient id="t" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#ff6fa8"/><stop offset=".5" stop-color="#7bd3ff"/><stop offset="1" stop-color="#b78bff"/></linearGradient></defs>`,
    64, 66,
  ),
  lotus: svg(
    `<g fill="#f7a8c8">
       <path d="M32 50C22 40 22 22 32 8c10 14 10 32 0 42z" fill="#f48fb8"/>
       <path d="M32 52C20 50 10 38 8 24c14 2 24 14 24 28z"/>
       <path d="M32 52c12-2 22-14 24-28-14 2-24 14-24 28z"/>
     </g>
     <ellipse cx="32" cy="54" rx="18" ry="4" fill="#5fb374"/>`,
  ),
  diya: svg(
    `<defs><radialGradient id="f" cx="50%" cy="70%" r="60%"><stop offset="0" stop-color="#fff6c2"/><stop offset=".45" stop-color="#ffc23d"/><stop offset="1" stop-color="#ff7a00" stop-opacity="0"/></radialGradient></defs>
     <circle cx="32" cy="22" r="16" fill="url(#f)"/>
     <path d="M32 8c5 7 5 13 0 18-5-5-5-11 0-18z" fill="#ffb02e"/>
     <path d="M32 13c2 4 2 7 0 10-2-3-2-6 0-10z" fill="#fff3b0"/>
     <path d="M8 34h48c-2 14-12 22-24 22S10 48 8 34z" fill="#c4622d"/>
     <path d="M8 34h48" stroke="#8a3d17" stroke-width="3"/>
     <path d="M16 42h32" stroke="#f2b04d" stroke-width="2" stroke-dasharray="3 3"/>`,
  ),
  ember: svg(
    `<defs><radialGradient id="e"><stop offset="0" stop-color="#fffbe0"/><stop offset=".4" stop-color="#ffcc4d"/><stop offset="1" stop-color="#ff8c00" stop-opacity="0"/></radialGradient></defs><circle cx="32" cy="32" r="30" fill="url(#e)"/>`,
  ),
  autumnLantern: svg(
    `<defs><radialGradient id="a" cx="45%" cy="40%" r="70%"><stop offset="0" stop-color="#fff0b3"/><stop offset=".5" stop-color="#ffab40"/><stop offset="1" stop-color="#e0661a"/></radialGradient></defs>
     <path d="M32 2v6" stroke="#b3824a" stroke-width="2"/>
     <rect x="24" y="8" width="16" height="5" rx="2" fill="#7a4a1d"/>
     <path d="M20 13h24c6 10 6 30 0 40H20c-6-10-6-30 0-40z" fill="url(#a)"/>
     <path d="M26 13c-3 10-3 30 0 40M38 13c3 10 3 30 0 40" stroke="#c4561a" stroke-opacity=".5" stroke-width="1.3" fill="none"/>
     <rect x="24" y="53" width="16" height="5" rx="2" fill="#7a4a1d"/>`,
    64, 60,
  ),
  heart: (c) => svg(`<path d="M32 56S6 40 6 22C6 12 13 6 21 6c5 0 9 3 11 7 2-4 6-7 11-7 8 0 15 6 15 16 0 18-26 34-26 34z" fill="${c}"/><path d="M16 16c3-3 7-3 9 0" stroke="#fff" stroke-opacity=".5" stroke-width="3" fill="none" stroke-linecap="round"/>`),
  crescent: svg(`<path d="M40 6a26 26 0 1 0 18 44A22 22 0 1 1 40 6z" fill="#ffd77a"/>`),
  star: svg(`<path d="M32 4l7.6 18.2 19.7 1.6-15 12.9 4.6 19.2L32 45.6 15.1 55.9l4.6-19.2-15-12.9 19.7-1.6z" fill="#fff1b8"/>`),
}

const img = (src, w = 64, h = 64) => ({ src, width: w, height: h })

// ---------- option builders ----------
function drift({ images, count, size, speed, direction = 'bottom', wobble = 12, rotate = true, roll = false, tilt = false, opacity = [0.75, 1], twinkle = false, density, small }) {
  return {
    fullScreen: { enable: false },
    detectRetina: true,
    fpsLimit: 60,
    background: { color: 'transparent' },
    particles: {
      number: { value: Math.max(4, Math.round(count * density * (small ? 0.5 : 1))) },
      shape: { type: 'image', options: { image: images } },
      size: { value: { min: size[0], max: size[1] } },
      opacity: { value: { min: opacity[0], max: opacity[1] } },
      move: {
        enable: true,
        direction,
        speed: { min: speed[0], max: speed[1] },
        straight: false,
        random: false,
        outModes: { default: 'out' },
        drift: { min: -0.4, max: 0.4 },
      },
      wobble: { enable: wobble > 0, distance: wobble, speed: { min: -6, max: 6 } },
      rotate: rotate
        ? { value: { min: -20, max: 20 }, direction: 'random', animation: { enable: true, speed: { min: 2, max: 8 }, sync: false } }
        : { value: 0 },
      roll: roll ? { enable: true, darken: { enable: true, value: 20 }, speed: { min: 5, max: 15 } } : { enable: false },
      tilt: tilt
        ? { enable: true, value: { min: 0, max: 360 }, direction: 'random', animation: { enable: true, speed: 30 } }
        : { enable: false },
      twinkle: twinkle ? { particles: { enable: true, frequency: 0.04, opacity: 1 } } : undefined,
    },
  }
}

function confetti(colors, { density, small }) {
  return {
    fullScreen: { enable: false },
    detectRetina: true,
    fpsLimit: 60,
    background: { color: 'transparent' },
    particles: {
      number: { value: Math.round(90 * density * (small ? 0.5 : 1)) },
      color: { value: colors },
      shape: { type: ['square', 'circle'] },
      size: { value: { min: 4, max: 9 } },
      opacity: { value: 1 },
      move: { enable: true, direction: 'bottom', speed: { min: 2, max: 5 }, outModes: { default: 'out' }, drift: { min: -1, max: 1 } },
      rotate: { value: { min: 0, max: 360 }, direction: 'random', animation: { enable: true, speed: 30 } },
      tilt: { enable: true, value: { min: 0, max: 360 }, direction: 'random', animation: { enable: true, speed: 30 } },
      roll: { enable: true, enlighten: { enable: true, value: 20 }, speed: { min: 15, max: 25 } },
      wobble: { enable: true, distance: 30, speed: { min: -15, max: 15 } },
    },
  }
}

// Returns { kind: 'particles', options } or { kind: 'fireworks', colors }.
function buildFestival(theme, { density = 1, small = false } = {}) {
  const o = { density, small }
  switch (theme) {
    case 'Christmas':
      return {
        kind: 'particles',
        options: {
          ...drift({ images: [img(ART.snowflake)], count: 70, size: [3, 11], speed: [0.6, 2], wobble: 10, opacity: [0.5, 1], ...o }),
        },
      }
    case 'NewYear':
      return { kind: 'fireworks', colors: ['#70e4fd', '#ffd166', '#ff5d8f', '#ffffff', '#b78bff', '#7dffb2'] }
    case 'ChineseNewYear':
      return {
        kind: 'particles',
        options: drift({
          images: [img(ART.chineseLantern, 64, 66), img(ART.chineseLantern, 64, 66), img(ART.redEnvelope), img(ART.goldSpark)],
          count: 22, size: [8, 22], speed: [0.5, 1.4], wobble: 18, ...o,
        }),
      }
    case 'SinhalaTamilNewYear':
      return {
        kind: 'particles',
        options: drift({
          images: [img(ART.petal('#ff4d4d', '#c3122b')), img(ART.petal('#ffb347', '#ff7b00')), img(ART.petal('#ffd84d', '#f5a300')), img(ART.leaf)],
          count: 40, size: [9, 17], speed: [0.8, 2], wobble: 22, roll: true, tilt: true, ...o,
        }),
      }
    case 'Vesak':
      return {
        kind: 'particles',
        options: drift({
          images: [img(ART.vesakLantern, 64, 66), img(ART.vesakLantern, 64, 66), img(ART.lotus), img(ART.ember)],
          count: 22, size: [8, 22], speed: [0.3, 0.9], direction: 'top', wobble: 14, twinkle: true, ...o,
        }),
      }
    case 'Deepavali':
      return {
        kind: 'particles',
        options: drift({
          images: [img(ART.diya), img(ART.ember), img(ART.ember), img(ART.goldSpark)],
          count: 34, size: [4, 16], speed: [0.4, 1.2], direction: 'top', wobble: 10, rotate: false, twinkle: true, ...o,
        }),
      }
    case 'MidAutumn':
      return {
        kind: 'particles',
        options: drift({
          images: [img(ART.autumnLantern, 64, 60), img(ART.autumnLantern, 64, 60), img(ART.ember), img(ART.star)],
          count: 22, size: [7, 20], speed: [0.3, 0.9], direction: 'top', wobble: 14, twinkle: true, ...o,
        }),
      }
    case 'Valentine':
      return {
        kind: 'particles',
        options: drift({
          images: [img(ART.heart('#ff4d79')), img(ART.heart('#ff8fab')), img(ART.heart('#e8174f'))],
          count: 28, size: [6, 15], speed: [0.6, 1.5], direction: 'top', wobble: 16, ...o,
        }),
      }
    case 'Eid':
      return {
        kind: 'particles',
        options: drift({
          images: [img(ART.crescent), img(ART.star), img(ART.star), img(ART.goldSpark)],
          count: 30, size: [4, 13], speed: [0.3, 0.9], wobble: 8, twinkle: true, ...o,
        }),
      }
    case 'SriLankaIndependence':
      return { kind: 'particles', options: confetti(['#c2185b', '#ff8f00', '#00897b', '#ffc107', '#ffffff'], o) }
    case 'ChinaNationalDay':
      return { kind: 'particles', options: confetti(['#de2910', '#ffde00', '#ff6b4a'], o) }
    default:
      return null
  }
}

// ---------- New Year fireworks (plain canvas, additive glow + fading trails) ----------
function startFireworks(container, colors, { density = 1 } = {}) {
  const canvas = document.createElement('canvas')
  canvas.style.cssText = 'position:absolute;inset:0;width:100%;height:100%;pointer-events:none'
  container.appendChild(canvas)
  const ctx = canvas.getContext('2d')
  const dpr = Math.min(window.devicePixelRatio || 1, 2)
  let w = 0
  let h = 0
  const resize = () => {
    w = container.clientWidth
    h = container.clientHeight
    canvas.width = w * dpr
    canvas.height = h * dpr
    ctx.setTransform(dpr, 0, 0, dpr, 0, 0)
  }
  resize()
  const rand = (a, b) => a + Math.random() * (b - a)
  const pick = (a) => a[(Math.random() * a.length) | 0]
  const rockets = []
  const sparks = []
  let next = 0
  let raf = 0
  let last = performance.now()

  const launch = () => {
    rockets.push({ x: rand(w * 0.15, w * 0.85), y: h + 10, vy: -rand(h / 95, h / 70), ty: rand(h * 0.12, h * 0.45), color: pick(colors) })
  }
  const explode = (r) => {
    const n = Math.round((w < 640 ? 50 : 90) * density)
    const ring = Math.random() < 0.35
    for (let i = 0; i < n; i++) {
      const a = (i / n) * Math.PI * 2 + rand(-0.05, 0.05)
      const sp = ring ? 3.2 : rand(0.8, 4)
      sparks.push({ x: r.x, y: r.y, px: r.x, py: r.y, vx: Math.cos(a) * sp, vy: Math.sin(a) * sp, life: 1, decay: rand(0.008, 0.016), color: Math.random() < 0.2 ? '#ffffff' : r.color })
    }
  }
  const frame = (t) => {
    const dt = Math.min((t - last) / 16.67, 3)
    last = t
    // translucent clear = motion trails
    ctx.globalCompositeOperation = 'destination-out'
    ctx.fillStyle = 'rgba(0,0,0,0.22)'
    ctx.fillRect(0, 0, w, h)
    ctx.globalCompositeOperation = 'lighter'
    if (t > next) {
      launch()
      if (Math.random() < 0.3) launch()
      next = t + rand(500, 1300) / density
    }
    for (let i = rockets.length - 1; i >= 0; i--) {
      const r = rockets[i]
      r.y += r.vy * dt
      ctx.fillStyle = r.color
      ctx.beginPath()
      ctx.arc(r.x, r.y, 2, 0, Math.PI * 2)
      ctx.fill()
      if (r.y <= r.ty) {
        explode(r)
        rockets.splice(i, 1)
      }
    }
    ctx.lineCap = 'round'
    for (let i = sparks.length - 1; i >= 0; i--) {
      const s = sparks[i]
      s.px = s.x
      s.py = s.y
      s.vx *= 0.985
      s.vy = s.vy * 0.985 + 0.045 * dt
      s.x += s.vx * dt
      s.y += s.vy * dt
      s.life -= s.decay * dt
      if (s.life <= 0) {
        sparks.splice(i, 1)
        continue
      }
      ctx.globalAlpha = s.life
      ctx.strokeStyle = s.color
      ctx.lineWidth = 2
      ctx.beginPath()
      ctx.moveTo(s.px, s.py)
      ctx.lineTo(s.x, s.y)
      ctx.stroke()
    }
    ctx.globalAlpha = 1
    raf = requestAnimationFrame(frame)
  }
  const onVisibility = () => {
    cancelAnimationFrame(raf)
    if (!document.hidden) {
      last = performance.now()
      raf = requestAnimationFrame(frame)
    }
  }
  window.addEventListener('resize', resize)
  document.addEventListener('visibilitychange', onVisibility)
  raf = requestAnimationFrame(frame)
  return () => {
    cancelAnimationFrame(raf)
    window.removeEventListener('resize', resize)
    document.removeEventListener('visibilitychange', onVisibility)
    canvas.remove()
  }
}

  window.buildFestival = buildFestival
  window.startFestivalFx = function (container, theme, opts) {
    opts = opts || {}
    var spec = buildFestival(theme, { density: opts.density || 1, small: container.clientWidth < 640 })
    if (!spec || !container) return function () {}
    if (spec.kind === 'fireworks') return startFireworks(container, spec.colors, { density: opts.density || 1 })
    var stopped = false, instance = null
    var ready = window.__protonFxReady || (window.__protonFxReady = (window.loadFull ? window.loadFull(window.tsParticles) : Promise.resolve()))
    ready.then(function () {
      if (stopped) return
      return window.tsParticles.load({ id: 'festival-preview-' + (++window.__protonFxSeq || (window.__protonFxSeq = 1)), element: container, options: spec.options })
    }).then(function (inst) { instance = inst; if (stopped && inst) inst.destroy() })
    return function () { stopped = true; if (instance) instance.destroy() }
  }
})()

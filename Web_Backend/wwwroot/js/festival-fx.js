(function () {
// Seasonal festival effects drawn on one full-screen <canvas>. Theme keys are
// set per scheduled "Festival" row in Admin → Site Content → Festival effects.
//
// SAME FILE lives in the backend at Web_Backend/wwwroot/js/festival-fx.js
// (admin preview) — keep the two copies identical.
//
// Cheap by design: plain 2D canvas, no filters, ~20–60 particles, pauses
// while the tab is hidden, fewer particles on small screens.
const THEMES = {
  Christmas:        { mode: 'fall',     glyphs: ['❄︎', '❅︎', '❆︎', '•'], dots: '#ffffff', count: 55, size: [10, 22], speed: [0.4, 1.2] },
  NewYear:          { mode: 'firework', colors: ['#70e4fd', '#ffd166', '#ef476f', '#ffffff', '#a78bfa'] },
  ChineseNewYear:   { mode: 'fall',     glyphs: ['🏮', '🧧', '✨'], count: 18, size: [18, 30], speed: [0.3, 0.8], swing: 1.2 },
  SinhalaTamilNewYear: { mode: 'fall',  glyphs: ['🌺', '🌼', '🌸', '🍃'], count: 26, size: [14, 24], speed: [0.4, 1.0], spin: true },
  Vesak:            { mode: 'rise',     glyphs: ['🏮', '🪷', '✨'], count: 18, size: [16, 28], speed: [0.25, 0.6], swing: 0.8 },
  Deepavali:        { mode: 'rise',     glyphs: ['🪔', '✨', '✨'], count: 22, size: [14, 26], speed: [0.3, 0.8] },
  MidAutumn:        { mode: 'rise',     glyphs: ['🏮', '🥮', '🌕'], count: 16, size: [18, 28], speed: [0.25, 0.6], swing: 1 },
  Valentine:        { mode: 'rise',     glyphs: ['❤', '💖', '💕'], count: 22, size: [14, 26], speed: [0.4, 1.0], swing: 1 },
  Eid:              { mode: 'fall',     glyphs: ['🌙', '⭐', '✨'], count: 22, size: [14, 24], speed: [0.3, 0.8] },
  SriLankaIndependence: { mode: 'confetti', colors: ['#8d153a', '#eb7400', '#00534e', '#ffbe29'] },
  ChinaNationalDay: { mode: 'confetti', colors: ['#de2910', '#ffde00'] },
}

const FESTIVAL_THEMES = Object.keys(THEMES)

const rand = (a, b) => a + Math.random() * (b - a)
const pick = (arr) => arr[(Math.random() * arr.length) | 0]

// Starts the effect on `canvas`; returns a stop() function.
function startFestivalFx(canvas, themeKey, { density = 1 } = {}) {
  const theme = THEMES[themeKey]
  if (!theme || !canvas) return () => {}
  const ctx = canvas.getContext('2d')
  let w = 0
  let h = 0
  const dpr = Math.min(window.devicePixelRatio || 1, 2)
  const resize = () => {
    w = canvas.clientWidth
    h = canvas.clientHeight
    canvas.width = w * dpr
    canvas.height = h * dpr
    ctx.setTransform(dpr, 0, 0, dpr, 0, 0)
  }
  resize()
  const small = w < 640
  const scale = (small ? 0.5 : 1) * density

  // ---------- particle modes ----------
  const parts = []
  const spawnDrift = (initial) => {
    const [s0, s1] = theme.size
    const [v0, v1] = theme.speed
    const up = theme.mode === 'rise'
    return {
      x: rand(0, w),
      y: initial ? rand(0, h) : up ? h + 30 : -30,
      size: rand(s0, s1),
      vy: rand(v0, v1) * (up ? -1 : 1),
      phase: rand(0, Math.PI * 2),
      swing: (theme.swing ?? 0.6) * rand(0.5, 1.2),
      rot: rand(0, Math.PI * 2),
      vr: theme.spin ? rand(-0.02, 0.02) : 0,
      glyph: pick(theme.glyphs),
      alpha: rand(0.55, 0.95),
    }
  }
  const spawnConfetti = (initial) => ({
    x: rand(0, w),
    y: initial ? rand(-h, h) : rand(-60, -10),
    wdt: rand(6, 11),
    hgt: rand(3, 6),
    vy: rand(1, 2.4),
    vx: rand(-0.6, 0.6),
    rot: rand(0, Math.PI * 2),
    vr: rand(-0.12, 0.12),
    color: pick(theme.colors),
  })

  if (theme.mode === 'fall' || theme.mode === 'rise') {
    for (let i = 0; i < Math.round(theme.count * scale); i++) parts.push(spawnDrift(true))
  } else if (theme.mode === 'confetti') {
    for (let i = 0; i < Math.round(70 * scale); i++) parts.push(spawnConfetti(true))
  }

  const sparks = []
  let nextBurst = 0
  const burst = (t) => {
    const x = rand(w * 0.15, w * 0.85)
    const y = rand(h * 0.1, h * 0.45)
    const color = pick(theme.colors)
    const n = small ? 28 : 46
    for (let i = 0; i < n; i++) {
      const a = (i / n) * Math.PI * 2
      const sp = rand(1.2, 3.2)
      sparks.push({ x, y, vx: Math.cos(a) * sp, vy: Math.sin(a) * sp, life: 1, color })
    }
    nextBurst = t + rand(700, 1600) / density
  }

  // ---------- loop ----------
  let raf = 0
  let last = performance.now()
  const frame = (t) => {
    const dt = Math.min((t - last) / 16.67, 3) // 1 = one 60 fps frame
    last = t
    ctx.clearRect(0, 0, w, h)

    if (theme.mode === 'fall' || theme.mode === 'rise') {
      ctx.textAlign = 'center'
      ctx.textBaseline = 'middle'
      for (let i = 0; i < parts.length; i++) {
        const p = parts[i]
        p.y += p.vy * dt
        p.phase += 0.015 * dt
        p.rot += p.vr * dt
        const x = p.x + Math.sin(p.phase) * 18 * p.swing
        if ((p.vy > 0 && p.y > h + 40) || (p.vy < 0 && p.y < -40)) parts[i] = spawnDrift(false)
        ctx.globalAlpha = p.alpha
        ctx.save()
        ctx.translate(x, p.y)
        ctx.rotate(p.vr ? p.rot : Math.sin(p.phase) * 0.15)
        ctx.font = `${p.size}px "Segoe UI Emoji","Apple Color Emoji","Noto Color Emoji",sans-serif`
        ctx.fillStyle = theme.dots || '#fff'
        ctx.fillText(p.glyph, 0, 0)
        ctx.restore()
      }
    } else if (theme.mode === 'confetti') {
      for (let i = 0; i < parts.length; i++) {
        const p = parts[i]
        p.y += p.vy * dt
        p.x += p.vx * dt
        p.rot += p.vr * dt
        if (p.y > h + 20) parts[i] = spawnConfetti(false)
        ctx.globalAlpha = 0.9
        ctx.save()
        ctx.translate(p.x, p.y)
        ctx.rotate(p.rot)
        ctx.fillStyle = p.color
        ctx.fillRect(-p.wdt / 2, -p.hgt / 2, p.wdt, p.hgt * Math.abs(Math.cos(p.rot * 2)) + 1)
        ctx.restore()
      }
    } else if (theme.mode === 'firework') {
      if (t > nextBurst) burst(t)
      for (let i = sparks.length - 1; i >= 0; i--) {
        const s = sparks[i]
        s.x += s.vx * dt
        s.y += s.vy * dt
        s.vy += 0.035 * dt
        s.vx *= 0.985
        s.life -= 0.012 * dt
        if (s.life <= 0) {
          sparks.splice(i, 1)
          continue
        }
        ctx.globalAlpha = s.life
        ctx.fillStyle = s.color
        ctx.beginPath()
        ctx.arc(s.x, s.y, 2.2, 0, Math.PI * 2)
        ctx.fill()
      }
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
    ctx.clearRect(0, 0, w, h)
  }
}

window.startFestivalFx = startFestivalFx;
window.FESTIVAL_THEMES = FESTIVAL_THEMES;
})();

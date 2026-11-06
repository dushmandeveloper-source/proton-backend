// Student "your time zone" view (any country). Schedule times are always shown
// in China + Sri Lanka by the server; when a student picks another zone, every
// element with data-tz-start (ISO with offset) gets a third flag chip in that
// zone, and the dashboard clock gets a third chip. Choice is saved to the
// student's account (POST /Student/TimeZone/Save) and cached locally.
(function () {
    const ZONES = [
        ['Asia/Shanghai', 'China', '🇨🇳'], ['Asia/Colombo', 'Sri Lanka', '🇱🇰'],
        ['Asia/Kolkata', 'India', '🇮🇳'], ['Asia/Dhaka', 'Bangladesh', '🇧🇩'], ['Asia/Karachi', 'Pakistan', '🇵🇰'],
        ['Asia/Kathmandu', 'Nepal', '🇳🇵'], ['Indian/Maldives', 'Maldives', '🇲🇻'], ['Asia/Thimphu', 'Bhutan', '🇧🇹'],
        ['Asia/Kabul', 'Afghanistan', '🇦🇫'], ['Asia/Tehran', 'Iran', '🇮🇷'], ['Asia/Dubai', 'United Arab Emirates', '🇦🇪'],
        ['Asia/Muscat', 'Oman', '🇴🇲'], ['Asia/Qatar', 'Qatar', '🇶🇦'], ['Asia/Bahrain', 'Bahrain', '🇧🇭'],
        ['Asia/Kuwait', 'Kuwait', '🇰🇼'], ['Asia/Riyadh', 'Saudi Arabia', '🇸🇦'], ['Asia/Baghdad', 'Iraq', '🇮🇶'],
        ['Asia/Amman', 'Jordan', '🇯🇴'], ['Asia/Beirut', 'Lebanon', '🇱🇧'], ['Asia/Jerusalem', 'Israel', '🇮🇱'],
        ['Europe/Istanbul', 'Türkiye', '🇹🇷'], ['Asia/Tashkent', 'Uzbekistan', '🇺🇿'], ['Asia/Almaty', 'Kazakhstan', '🇰🇿'],
        ['Asia/Bishkek', 'Kyrgyzstan', '🇰🇬'], ['Asia/Yangon', 'Myanmar', '🇲🇲'], ['Asia/Bangkok', 'Thailand', '🇹🇭'],
        ['Asia/Ho_Chi_Minh', 'Vietnam', '🇻🇳'], ['Asia/Phnom_Penh', 'Cambodia', '🇰🇭'], ['Asia/Vientiane', 'Laos', '🇱🇦'],
        ['Asia/Kuala_Lumpur', 'Malaysia', '🇲🇾'], ['Asia/Singapore', 'Singapore', '🇸🇬'], ['Asia/Jakarta', 'Indonesia (Jakarta)', '🇮🇩'],
        ['Asia/Manila', 'Philippines', '🇵🇭'], ['Asia/Brunei', 'Brunei', '🇧🇳'], ['Asia/Hong_Kong', 'Hong Kong', '🇭🇰'],
        ['Asia/Macau', 'Macau', '🇲🇴'], ['Asia/Taipei', 'Taiwan', '🇹🇼'], ['Asia/Ulaanbaatar', 'Mongolia', '🇲🇳'],
        ['Asia/Seoul', 'South Korea', '🇰🇷'], ['Asia/Tokyo', 'Japan', '🇯🇵'],
        ['Australia/Perth', 'Australia (Perth)', '🇦🇺'], ['Australia/Sydney', 'Australia (Sydney)', '🇦🇺'], ['Pacific/Auckland', 'New Zealand', '🇳🇿'],
        ['Europe/London', 'United Kingdom', '🇬🇧'], ['Europe/Dublin', 'Ireland', '🇮🇪'], ['Europe/Paris', 'France', '🇫🇷'],
        ['Europe/Berlin', 'Germany', '🇩🇪'], ['Europe/Amsterdam', 'Netherlands', '🇳🇱'], ['Europe/Brussels', 'Belgium', '🇧🇪'],
        ['Europe/Zurich', 'Switzerland', '🇨🇭'], ['Europe/Vienna', 'Austria', '🇦🇹'], ['Europe/Rome', 'Italy', '🇮🇹'],
        ['Europe/Madrid', 'Spain', '🇪🇸'], ['Europe/Lisbon', 'Portugal', '🇵🇹'], ['Europe/Stockholm', 'Sweden', '🇸🇪'],
        ['Europe/Oslo', 'Norway', '🇳🇴'], ['Europe/Copenhagen', 'Denmark', '🇩🇰'], ['Europe/Helsinki', 'Finland', '🇫🇮'],
        ['Europe/Warsaw', 'Poland', '🇵🇱'], ['Europe/Prague', 'Czechia', '🇨🇿'], ['Europe/Budapest', 'Hungary', '🇭🇺'],
        ['Europe/Bucharest', 'Romania', '🇷🇴'], ['Europe/Athens', 'Greece', '🇬🇷'], ['Europe/Kyiv', 'Ukraine', '🇺🇦'],
        ['Europe/Moscow', 'Russia (Moscow)', '🇷🇺'], ['Africa/Cairo', 'Egypt', '🇪🇬'], ['Africa/Casablanca', 'Morocco', '🇲🇦'],
        ['Africa/Lagos', 'Nigeria', '🇳🇬'], ['Africa/Accra', 'Ghana', '🇬🇭'], ['Africa/Nairobi', 'Kenya', '🇰🇪'],
        ['Africa/Addis_Ababa', 'Ethiopia', '🇪🇹'], ['Africa/Dar_es_Salaam', 'Tanzania', '🇹🇿'], ['Africa/Kampala', 'Uganda', '🇺🇬'],
        ['Africa/Johannesburg', 'South Africa', '🇿🇦'], ['Indian/Mauritius', 'Mauritius', '🇲🇺'],
        ['America/Toronto', 'Canada (Toronto)', '🇨🇦'], ['America/Vancouver', 'Canada (Vancouver)', '🇨🇦'],
        ['America/New_York', 'USA (New York)', '🇺🇸'], ['America/Chicago', 'USA (Chicago)', '🇺🇸'],
        ['America/Denver', 'USA (Denver)', '🇺🇸'], ['America/Los_Angeles', 'USA (Los Angeles)', '🇺🇸'],
        ['America/Mexico_City', 'Mexico', '🇲🇽'], ['America/Sao_Paulo', 'Brazil', '🇧🇷'], ['America/Argentina/Buenos_Aires', 'Argentina', '🇦🇷'],
        ['America/Santiago', 'Chile', '🇨🇱'], ['America/Bogota', 'Colombia', '🇨🇴'], ['America/Lima', 'Peru', '🇵🇪'],
    ];
    const BUILT_IN = ['Asia/Shanghai', 'Asia/Colombo']; // already shown by the server
    const KEY = 'proton.studentTz';
    const meta = z => ZONES.find(x => x[0] === z);

    function supported(z) {
        try { new Intl.DateTimeFormat('en', { timeZone: z }); return true; } catch { return false; }
    }
    function readZone() {
        let z = window.__studentTz || '';
        try { z = z || localStorage.getItem(KEY) || ''; } catch { }
        return z && supported(z) ? z : '';
    }
    let zone = readZone();

    const fmtCache = {};
    function fmt(date, z) {
        const f = fmtCache[z] || (fmtCache[z] = new Intl.DateTimeFormat('en-US', { timeZone: z, hour: 'numeric', minute: '2-digit' }));
        return f.format(date);
    }
    function dayKey(date, z) {
        return new Intl.DateTimeFormat('en-CA', { timeZone: z, year: 'numeric', month: '2-digit', day: '2-digit' }).format(date);
    }
    function flagOf(z) { const m = meta(z); return m ? m[2] : '🌐'; }

    // Third chip after each server-rendered time.
    function renderTimes(root) {
        (root || document).querySelectorAll('[data-tz-start]').forEach(el => {
            let chip = el.nextElementSibling && el.nextElementSibling.classList.contains('tz-local') ? el.nextElementSibling : null;
            if (!zone || BUILT_IN.includes(zone)) { if (chip) chip.remove(); return; }
            const start = new Date(el.dataset.tzStart);
            if (isNaN(start)) return;
            const end = el.dataset.tzEnd ? new Date(el.dataset.tzEnd) : null;
            const ref = el.dataset.tzStart.slice(0, 10);
            const sDay = dayKey(start, zone);
            const note = sDay > ref ? ' (next day)' : sDay < ref ? ' (prev day)' : '';
            const text = `${flagOf(zone)} ${fmt(start, zone)}${end && !isNaN(end) ? ' – ' + fmt(end, zone) : ''}${note}`;
            if (!chip) {
                chip = document.createElement('span');
                chip.className = 'tz-local inline-flex items-center ml-1.5 px-1.5 py-0.5 rounded-md text-[11px] font-semibold bg-indigo-50 dark:bg-indigo-950 text-indigo-700 dark:text-indigo-300 whitespace-nowrap';
                el.insertAdjacentElement('afterend', chip);
            }
            chip.textContent = text;
            chip.title = 'Your time (' + (meta(zone) ? meta(zone)[1] : zone) + ')';
        });
    }

    // Third chip on the dashboard clock pill.
    function renderClock() {
        document.querySelectorAll('[data-clock-local]').forEach(wrap => {
            const show = zone && !BUILT_IN.includes(zone);
            wrap.classList.toggle('hidden', !show);
            if (!show) return;
            wrap.querySelector('[data-clock-local-flag]').textContent = flagOf(zone);
            wrap.querySelector('[data-clock-local-time]').textContent = fmt(new Date(), zone);
            wrap.title = (meta(zone) ? meta(zone)[1] : zone) + ' (your time)';
        });
    }

    function fillPickers() {
        document.querySelectorAll('select[data-tz-picker]').forEach(sel => {
            if (!sel.dataset.filled) {
                sel.dataset.filled = '1';
                const device = (Intl.DateTimeFormat().resolvedOptions().timeZone) || '';
                const opts = ['<option value="">🇨🇳 China + 🇱🇰 Sri Lanka only</option>'];
                if (device && !meta(device) && supported(device)) opts.push(`<option value="${device}">🌐 My device (${device})</option>`);
                ZONES.filter(x => !BUILT_IN.includes(x[0]) && supported(x[0]))
                    .sort((a, b) => a[1].localeCompare(b[1]))
                    .forEach(([z, name, flag]) => opts.push(`<option value="${z}">${flag} ${name}${z === device ? ' — this device' : ''}</option>`));
                sel.innerHTML = opts.join('');
                sel.addEventListener('change', () => setZone(sel.value));
            }
            sel.value = zone && !BUILT_IN.includes(zone) ? zone : '';
            // Compact button: show the chosen country's flag next to the globe.
            const btn = sel.closest('.tz-button');
            if (btn) {
                const cur = btn.querySelector('[data-tz-current]');
                const chosen = zone && !BUILT_IN.includes(zone);
                if (cur) cur.textContent = chosen ? flagOf(zone) : '';
                btn.title = chosen ? 'My time: ' + (meta(zone) ? meta(zone)[1] : zone) + ' (tap to change)' : 'Show times in my country';
            }
        });
    }

    function setZone(z) {
        zone = z && supported(z) ? z : '';
        try { zone ? localStorage.setItem(KEY, zone) : localStorage.removeItem(KEY); } catch { }
        renderAll();
        const token = document.querySelector('input[name="__RequestVerificationToken"]');
        const body = new URLSearchParams({ zone: zone });
        if (token) body.append('__RequestVerificationToken', token.value);
        fetch('/Student/TimeZone/Save', { method: 'POST', body, credentials: 'same-origin' }).catch(() => { });
    }

    function renderAll() { fillPickers(); renderTimes(); renderClock(); }

    document.addEventListener('DOMContentLoaded', () => {
        renderAll();
        setInterval(renderClock, 15000);
        // Calendar popups are built later by JS -- pick their times up too.
        new MutationObserver(muts => {
            for (const m of muts) for (const n of m.addedNodes)
                if (n.nodeType === 1 && !n.classList.contains('tz-local')) renderTimes(n);
        }).observe(document.body, { childList: true, subtree: true });
    });
})();

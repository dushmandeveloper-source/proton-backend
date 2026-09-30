// Shared ApexCharts look for the admin pages (dashboard, Finance). Loads
// ApexCharts on demand, applies one theme (fonts, grid, tooltip, light/dark,
// entrance animation) and re-themes live when the portal's dark toggle flips.
// Usage: ProtonCharts.render(el, options) -> Promise<chart>
(function () {
    var SRC = 'https://cdn.jsdelivr.net/npm/apexcharts@3.54.1/dist/apexcharts.min.js';
    var loading = null;
    var charts = [];

    function load() {
        if (window.ApexCharts) return Promise.resolve();
        if (loading) return loading;
        loading = new Promise(function (resolve, reject) {
            var s = document.createElement('script');
            s.src = SRC; s.async = true;
            s.onload = resolve; s.onerror = reject;
            document.head.appendChild(s);
        });
        return loading;
    }

    function isDark() { return document.documentElement.classList.contains('dark'); }
    var reduce = window.matchMedia && window.matchMedia('(prefers-reduced-motion: reduce)').matches;

    function theme() {
        var dark = isDark();
        return {
            chart: {
                fontFamily: 'inherit', foreColor: dark ? '#94a3b8' : '#64748b', background: 'transparent',
                toolbar: { show: false }, zoom: { enabled: false },
                animations: { enabled: !reduce, easing: 'easeinout', speed: 900, animateGradually: { enabled: true, delay: 90 }, dynamicAnimation: { enabled: true, speed: 450 } },
                dropShadow: { enabled: false }
            },
            theme: { mode: dark ? 'dark' : 'light' },
            grid: { borderColor: dark ? 'rgba(148,163,184,.14)' : 'rgba(148,163,184,.22)', strokeDashArray: 4, padding: { left: 6, right: 10 } },
            tooltip: { theme: dark ? 'dark' : 'light', style: { fontSize: '12px' } },
            legend: { position: 'top', horizontalAlign: 'right', fontWeight: 600, markers: { radius: 12, width: 10, height: 10 }, itemMargin: { horizontal: 10 } },
            dataLabels: { enabled: false },
            states: { hover: { filter: { type: 'lighten', value: 0.06 } }, active: { filter: { type: 'none' } } },
            stroke: { lineCap: 'round' }
        };
    }

    function merge(a, b) {
        var out = Array.isArray(a) ? a.slice() : Object.assign({}, a);
        Object.keys(b || {}).forEach(function (k) {
            var v = b[k];
            out[k] = v && typeof v === 'object' && !Array.isArray(v) && typeof v !== 'function' && a && typeof a[k] === 'object' && !Array.isArray(a[k])
                ? merge(a[k], v) : v;
        });
        return out;
    }

    function fmt(v, digits) {
        return Number(v || 0).toLocaleString(undefined, { minimumFractionDigits: digits == null ? 0 : digits, maximumFractionDigits: 2 });
    }
    function compact(v) {
        var n = Math.abs(v || 0);
        if (n >= 1e6) return (v / 1e6).toFixed(1).replace(/\.0$/, '') + 'M';
        if (n >= 1e3) return (v / 1e3).toFixed(1).replace(/\.0$/, '') + 'k';
        return fmt(v);
    }

    function render(el, options) {
        if (typeof el === 'string') el = document.querySelector(el);
        if (!el) return Promise.resolve(null);
        return load().then(function () {
            var opts = merge(theme(), options);
            var chart = new ApexCharts(el, opts);
            chart.__opts = options;
            charts.push(chart);
            return chart.render().then(function () { return chart; });
        });
    }

    // Follow the portal's theme toggle.
    new MutationObserver(function () {
        charts.forEach(function (c) {
            var t = theme();
            c.updateOptions({ theme: t.theme, chart: { foreColor: t.chart.foreColor }, grid: t.grid, tooltip: t.tooltip }, false, false);
        });
    }).observe(document.documentElement, { attributes: true, attributeFilter: ['class'] });

    window.ProtonCharts = { render: render, fmt: fmt, compact: compact, isDark: isDark };
})();

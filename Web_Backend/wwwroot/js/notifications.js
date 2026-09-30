// Top-bar notification bell (Views/Shared/_NotificationBell.cshtml).
// - Live push over SignalR (/hubs/notifications, event "notify").
// - Dropdown lazily loads /Notifications/List on open.
// - Items link through /Notifications/Open/{id} (marks read, redirects).
// - On any page, a "#hl-<id>" hash scrolls to and flashes that element.
(function () {
    var root = document.getElementById('notif-root');
    if (!root) return;

    var toggle = document.getElementById('notif-toggle');
    var panel = document.getElementById('notif-panel');
    var list = document.getElementById('notif-list');
    var badge = document.getElementById('notif-badge');
    var badgeCount = document.getElementById('notif-badge-count');
    var markAll = document.getElementById('notif-mark-all');
    var sub = document.getElementById('notif-sub');

    // Icon + tint per event type; anything unlisted falls back to a bell.
    var ICONS = {
        BalanceDue: ['wallet', '#dc2626', '#fef2f2'], PaymentAdded: ['wallet', '#059669', '#ecfdf5'], PaymentEdited: ['wallet', '#0284c7', '#f0f9ff'],
        PaymentSubmitted: ['receipt', '#d97706', '#fffbeb'], SlipVerified: ['badge-check', '#059669', '#ecfdf5'], PaymentRejected: ['circle-x', '#dc2626', '#fef2f2'], InstallmentPlan: ['calendar-clock', '#7c3aed', '#f5f3ff'],
        StudentPaid: ['wallet', '#059669', '#ecfdf5'], DiscountGiven: ['badge-percent', '#059669', '#ecfdf5'],
        AccessRequested: ['key-round', '#d97706', '#fffbeb'], FullAccessGranted: ['lock-open', '#059669', '#ecfdf5'],
        StudentRegistered: ['user-plus', '#7c3aed', '#f5f3ff'], AgentRegistered: ['user-plus', '#7c3aed', '#f5f3ff'],
        AgentApproved: ['shield-check', '#059669', '#ecfdf5'], AccountVerified: ['shield-check', '#059669', '#ecfdf5'],
        AccountRejected: ['shield-x', '#dc2626', '#fef2f2'], PassportVerified: ['id-card', '#059669', '#ecfdf5'],
        PassportRejected: ['id-card', '#dc2626', '#fef2f2'], DocumentSubmitted: ['file-up', '#ea580c', '#fff7ed'],
        HomeworkSubmitted: ['notebook-pen', '#7c3aed', '#f5f3ff'], HomeworkPosted: ['notebook-pen', '#7c3aed', '#f5f3ff'],
        MaterialPosted: ['book-open', '#4f46e5', '#eef2ff'], ExamSubmitted: ['clipboard-check', '#0284c7', '#f0f9ff'],
        GradeReleased: ['award', '#0284c7', '#f0f9ff']
    };

    function renderIcons() { if (window.lucide && lucide.createIcons) lucide.createIcons(); }
    var unread = parseInt(badgeCount.textContent, 10) || 0;
    var loaded = false;

    function setUnread(n) {
        unread = Math.max(0, n);
        badgeCount.textContent = unread > 99 ? '99+' : String(unread);
        badge.hidden = unread === 0;
        toggle.classList.toggle('nb-has-unread', unread > 0);
        if (sub) sub.textContent = unread > 0 ? unread + ' unread' : 'No unread';
    }

    function esc(s) {
        var d = document.createElement('div');
        d.textContent = s == null ? '' : String(s);
        return d.innerHTML;
    }

    function timeAgo(value) {
        var t = new Date(value).getTime();
        if (isNaN(t)) return '';
        var s = Math.max(0, Math.floor((Date.now() - t) / 1000));
        if (s < 60) return 'just now';
        var m = Math.floor(s / 60); if (m < 60) return m + 'm ago';
        var h = Math.floor(m / 60); if (h < 24) return h + 'h ago';
        var d = Math.floor(h / 24); if (d < 7) return d + 'd ago';
        return new Date(t).toLocaleDateString();
    }

    function itemHtml(n, isNew) {
        var isRead = n.isRead === true;
        var ic = ICONS[n.eventType] || ['bell', '#7c3aed', '#f5f3ff'];
        return '<a href="/Notifications/Open/' + encodeURIComponent(n.notificationID || n.notificationId) + '" role="menuitem"' +
            ' class="nb-item' + (isRead ? '' : ' nb-unread') + (isNew ? ' nb-new' : '') + '">' +
            '<span class="nb-item-icon" style="color:' + ic[1] + ';background:' + ic[2] + '"><i data-lucide="' + ic[0] + '"></i></span>' +
            '<span class="nb-item-main">' +
            '<span class="nb-item-title"><span>' + esc(n.title) + '</span>' + (isRead ? '' : '<i class="nb-dot"></i>') + '</span>' +
            (n.body ? '<span class="nb-item-body">' + esc(n.body) + '</span>' : '') +
            '<span class="nb-item-time">' + timeAgo(n.createdDate) + '</span>' +
            '</span></a>';
    }

    function empty() {
        return '<div class="nb-empty"><div class="nb-empty-icon"><i data-lucide="bell-off"></i></div>You are all caught up.</div>';
    }

    function load() {
        return fetch('/Notifications/List', { credentials: 'same-origin' })
            .then(function (r) { return r.ok ? r.json() : null; })
            .then(function (data) {
                if (!data) return;
                loaded = true;
                setUnread(data.unread);
                list.innerHTML = data.items.length ? data.items.map(function (n) { return itemHtml(n, false); }).join('') : empty();
                renderIcons();
            })
            .catch(function () { list.innerHTML = empty(); renderIcons(); });
    }

    toggle.addEventListener('click', function (e) {
        e.stopPropagation();
        setOpen(panel.hidden);
    });
    function setOpen(open) {
        panel.hidden = !open;
        toggle.setAttribute('aria-expanded', open ? 'true' : 'false');
        if (open) load();
    }
    document.addEventListener('click', function (e) {
        if (!panel.hidden && !root.contains(e.target)) setOpen(false);
    });
    document.addEventListener('keydown', function (e) {
        if (e.key === 'Escape' && !panel.hidden) setOpen(false);
    });

    markAll.addEventListener('click', function () {
        var tokenEl = document.querySelector('input[name="__RequestVerificationToken"]');
        fetch('/Notifications/MarkAllRead', {
            method: 'POST',
            credentials: 'same-origin',
            headers: { 'RequestVerificationToken': tokenEl ? tokenEl.value : '' }
        }).then(function (r) { if (r.ok) load(); });
    });

    // ---------- Live push ----------
    function connect() {
        if (!window.signalR) return;
        var conn = new signalR.HubConnectionBuilder()
            .withUrl('/hubs/notifications')
            .withAutomaticReconnect()
            .build();
        conn.on('notify', function (n) {
            setUnread(unread + 1);
            if (loaded) {
                if (list.querySelector('.nb-empty')) list.innerHTML = '';
                list.insertAdjacentHTML('afterbegin', itemHtml(n, true));
                renderIcons();
            }
            if (typeof window.showToast === 'function') window.showToast(n.title + (n.body ? ' — ' + n.body : ''));
        });
        // Chat messages ride the same connection; the top-bar chat icon and
        // the Messages page listen for this DOM event (messaging.js).
        conn.on('message', function (m) {
            document.dispatchEvent(new CustomEvent('proton:message', { detail: m }));
        });
        window.protonHub = conn;
        // Catch up on anything missed while disconnected.
        conn.onreconnected(function () { load(); document.dispatchEvent(new CustomEvent('proton:reconnected')); });
        conn.start().catch(function () { setTimeout(connect, 5000); });
    }

    if (window.signalR) {
        connect();
    } else {
        var s = document.createElement('script');
        s.src = 'https://cdn.jsdelivr.net/npm/@microsoft/signalr@8.0.7/dist/browser/signalr.min.js';
        s.onload = connect;
        document.head.appendChild(s);
    }

    // ---------- Deep-link highlight ----------
    function highlight() {
        var h = decodeURIComponent(location.hash || '');
        if (h.indexOf('#hl-') !== 0) return;
        var el = document.getElementById(h.substring(1));
        if (!el) return;
        // Reveal collapsed rows/sections that contain the target.
        var p = el;
        while (p && p !== document.body) {
            if (p.classList && p.classList.contains('hidden') && p.tagName !== 'TR') p.classList.remove('hidden');
            p = p.parentElement;
        }
        el.scrollIntoView({ behavior: 'smooth', block: 'center' });
        el.classList.remove('hl-flash');
        void el.offsetWidth;
        el.classList.add('hl-flash');
    }
    if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', highlight);
    else highlight();
    window.addEventListener('hashchange', highlight);
})();

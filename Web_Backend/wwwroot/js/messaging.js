// Chat page (Views/Shared/Messaging/_Chat.cshtml). Server endpoints live on
// MessagesControllerBase under /{Area}/Messages. Live updates arrive as the
// "proton:message" DOM event that notifications.js raises for SignalR pushes.
(function () {
    var app = document.getElementById('chat-app');
    if (!app) return;

    var BASE = app.dataset.base;
    var ME = app.dataset.me;
    var BROADCAST = app.dataset.broadcast === '1';
    var IS_STUDENT = app.dataset.student === '1';

    var listEl = document.getElementById('ch-list');
    var filterEl = document.getElementById('ch-filter');
    var emptyEl = document.getElementById('ch-empty');
    var threadEl = document.getElementById('ch-thread');
    var msgsEl = document.getElementById('ch-messages');
    var titleEl = document.getElementById('ch-thread-title');
    var subEl = document.getElementById('ch-thread-sub');
    var avatarEl = document.getElementById('ch-thread-avatar');
    var composer = document.getElementById('ch-composer');
    var input = document.getElementById('ch-input');
    var sendBtn = document.getElementById('ch-send');

    var conversations = [];
    var active = null;       // ConversationID
    var activeIsSupport = false;
    var lastDay = '';

    // ---------- helpers ----------
    function token() {
        var el = document.querySelector('input[name="__RequestVerificationToken"]');
        return el ? el.value : '';
    }
    function esc(s) {
        var d = document.createElement('div');
        d.textContent = s == null ? '' : String(s);
        return d.innerHTML;
    }
    function icons() { if (window.lucide && lucide.createIcons) lucide.createIcons(); }
    function post(url, data) {
        var fd = new FormData();
        Object.keys(data).forEach(function (k) {
            var v = data[k];
            if (Array.isArray(v)) v.forEach(function (x) { fd.append(k, x); });
            else fd.append(k, v);
        });
        return fetch(url, { method: 'POST', body: fd, credentials: 'same-origin', headers: { 'RequestVerificationToken': token() } })
            .then(function (r) {
                return r.json().catch(function () { return {}; }).then(function (j) {
                    if (!r.ok) throw new Error(j.message || 'Something went wrong. Please try again.');
                    return j;
                });
            });
    }
    function getJson(url) {
        return fetch(url, { credentials: 'same-origin' }).then(function (r) { if (!r.ok) throw new Error(r.status); return r.json(); });
    }
    var PALETTE = ['#7c3aed', '#2563eb', '#0891b2', '#059669', '#d97706', '#db2777', '#4f46e5', '#0d9488'];
    function color(key) {
        var h = 0; key = key || '';
        for (var i = 0; i < key.length; i++) h = (h * 31 + key.charCodeAt(i)) | 0;
        return PALETTE[Math.abs(h) % PALETTE.length];
    }
    function initials(name) {
        var p = (name || '?').trim().split(/\s+/);
        return ((p[0] || '')[0] || '?').toUpperCase() + (p.length > 1 ? (p[p.length - 1][0] || '').toUpperCase() : '');
    }
    function avatar(name, key, support) {
        if (support) return '<div class="ch-avatar ch-support"><i data-lucide="headset"></i></div>';
        return '<div class="ch-avatar" style="background:' + color(key) + '">' + esc(initials(name)) + '</div>';
    }
    function shortTime(v) {
        var d = new Date(v); if (isNaN(d)) return '';
        var now = new Date();
        if (d.toDateString() === now.toDateString()) return d.toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' });
        var y = new Date(now); y.setDate(now.getDate() - 1);
        if (d.toDateString() === y.toDateString()) return 'Yesterday';
        if (now - d < 6 * 864e5) return d.toLocaleDateString([], { weekday: 'short' });
        return d.toLocaleDateString([], { day: 'numeric', month: 'short' });
    }
    function dayLabel(v) {
        var d = new Date(v), now = new Date();
        if (d.toDateString() === now.toDateString()) return 'Today';
        var y = new Date(now); y.setDate(now.getDate() - 1);
        if (d.toDateString() === y.toDateString()) return 'Yesterday';
        return d.toLocaleDateString([], { weekday: 'long', day: 'numeric', month: 'long' });
    }
    function clock(v) { var d = new Date(v); return isNaN(d) ? '' : d.toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' }); }

    function syncBadge() {
        var total = conversations.reduce(function (s, c) { return s + (c.conversationID === active ? 0 : c.unreadCount); }, 0);
        if (typeof window.protonSetChatUnread === 'function') window.protonSetChatUnread(total);
    }

    // ---------- conversation list ----------
    function renderList() {
        var q = (filterEl.value || '').toLowerCase();
        var rows = conversations.filter(function (c) {
            return !q || (c.title || '').toLowerCase().indexOf(q) >= 0 || (c.lastBody || '').toLowerCase().indexOf(q) >= 0;
        });
        if (!rows.length) {
            listEl.innerHTML = '<div class="ch-muted ch-pad">' + (conversations.length ? 'No matches.' : 'No conversations yet.') + '</div>';
            return;
        }
        listEl.innerHTML = rows.map(function (c) {
            var unread = c.conversationID !== active && c.unreadCount > 0;
            var supportAvatar = IS_STUDENT && c.isSupport;
            return '<button type="button" class="ch-conv' + (c.conversationID === active ? ' ch-active' : '') + (unread ? ' ch-unread' : '') + '" data-id="' + esc(c.conversationID) + '">' +
                avatar(c.title, c.title, supportAvatar) +
                '<div class="ch-conv-main">' +
                '<div class="ch-conv-top"><span class="ch-conv-name">' + esc(c.title) + '</span><span class="ch-conv-time">' + shortTime(c.lastMessageDate) + '</span></div>' +
                (c.kind ? '<div class="ch-conv-kind">' + esc(c.kind) + '</div>' : '') +
                '<div class="ch-conv-bottom"><span class="ch-conv-preview">' + (c.lastFromMe ? 'You: ' : '') + esc(c.lastBody) + '</span>' +
                (unread ? '<span class="ch-count">' + (c.unreadCount > 99 ? '99+' : c.unreadCount) + '</span>' : '') + '</div>' +
                '</div></button>';
        }).join('');
        icons();
    }

    function loadConversations() {
        return getJson(BASE + '/Conversations').then(function (list) {
            conversations = list;
            renderList();
            syncBadge();
        }).catch(function () {
            listEl.innerHTML = '<div class="ch-muted ch-pad">Could not load conversations.</div>';
        });
    }
    var refreshTimer = null;
    function refreshSoon() { clearTimeout(refreshTimer); refreshTimer = setTimeout(loadConversations, 250); }

    listEl.addEventListener('click', function (e) {
        var b = e.target.closest('.ch-conv');
        if (b) openThread(b.dataset.id);
    });
    filterEl.addEventListener('input', renderList);

    // ---------- thread ----------
    function messageHtml(m, isNew) {
        var html = '';
        var day = dayLabel(m.createdDate);
        if (day !== lastDay) { html += '<div class="ch-day">' + esc(day) + '</div>'; lastDay = day; }
        var mine = m.mine === true || m.senderUserID === ME || m.senderUserId === ME;
        // Show who wrote it when several people can answer (support inbox).
        var showSender = !mine && activeIsSupport;
        html += '<div class="ch-row ' + (mine ? 'ch-mine' : 'ch-theirs') + (isNew ? ' ch-new' : '') + '">' +
            (showSender ? '<div class="ch-sender">' + esc(m.senderName) + '</div>' : '') +
            '<div class="ch-bubble">' + esc(m.body) + '<span class="ch-time">' + clock(m.createdDate) + '</span></div></div>';
        return html;
    }
    function scrollBottom() { msgsEl.scrollTop = msgsEl.scrollHeight; }

    function showThreadPane(show) {
        threadEl.hidden = !show;
        emptyEl.hidden = show;
        app.classList.toggle('ch-in-thread', show);
    }

    function openThread(id) {
        active = id;
        window.protonActiveConversation = id;
        var c = conversations.find(function (x) { return x.conversationID === id; });
        if (c) { c.unreadCount = 0; }
        renderList(); syncBadge();
        showThreadPane(true);
        msgsEl.innerHTML = '<div class="ch-muted ch-pad">Loading…</div>';
        history.replaceState(null, '', BASE + '/Index?c=' + encodeURIComponent(id));
        return getJson(BASE + '/Thread?id=' + encodeURIComponent(id)).then(function (t) {
            if (active !== id) return;
            activeIsSupport = !!(c ? c.isSupport : false) || /Support/.test(t.subtitle || '');
            titleEl.textContent = t.title;
            subEl.textContent = t.subtitle || (c && c.kind) || '';
            avatarEl.outerHTML = '<div class="ch-avatar" id="ch-thread-avatar"></div>';
            avatarEl = document.getElementById('ch-thread-avatar');
            avatarEl.outerHTML = avatar(t.title, t.title, IS_STUDENT && activeIsSupport).replace('class="ch-avatar', 'id="ch-thread-avatar" class="ch-avatar');
            avatarEl = document.getElementById('ch-thread-avatar');
            lastDay = '';
            msgsEl.innerHTML = t.messages.length
                ? t.messages.map(function (m) { return messageHtml(m, false); }).join('')
                : '<div class="ch-muted ch-pad">Say hello 👋</div>';
            icons();
            scrollBottom();
            input.focus();
        }).catch(function () {
            msgsEl.innerHTML = '<div class="ch-muted ch-pad">Could not load this conversation.</div>';
        });
    }

    document.getElementById('ch-back').addEventListener('click', function () {
        active = null; window.protonActiveConversation = null;
        showThreadPane(false); renderList();
        history.replaceState(null, '', BASE + '/Index');
    });

    function autosize() { input.style.height = 'auto'; input.style.height = Math.min(input.scrollHeight, 140) + 'px'; }
    input.addEventListener('input', autosize);
    input.addEventListener('keydown', function (e) {
        if (e.key === 'Enter' && !e.shiftKey && !e.isComposing) { e.preventDefault(); composer.requestSubmit(); }
    });

    composer.addEventListener('submit', function (e) {
        e.preventDefault();
        var body = input.value.trim();
        if (!body || !active) return;
        var id = active;
        if (msgsEl.querySelector('.ch-pad')) msgsEl.innerHTML = '';
        msgsEl.insertAdjacentHTML('beforeend',
            '<div class="ch-row ch-mine ch-new ch-pending"><div class="ch-bubble">' + esc(body) + '<span class="ch-time">Sending…</span></div></div>');
        scrollBottom();
        input.value = ''; autosize();
        sendBtn.disabled = true;
        post(BASE + '/Reply', { conversationId: id, body: body })
            .then(function () {
                var p = msgsEl.querySelector('.ch-pending');
                if (p) { p.classList.remove('ch-pending'); p.querySelector('.ch-time').textContent = clock(new Date()); }
                refreshSoon();
            })
            .catch(function (err) {
                var p = msgsEl.querySelector('.ch-pending');
                if (p) p.remove();
                input.value = body; autosize();
                if (window.showToast) window.showToast(err.message, 'error');
            })
            .finally(function () { sendBtn.disabled = false; input.focus(); });
    });

    // ---------- live ----------
    document.addEventListener('proton:message', function (e) {
        var m = e.detail || {};
        var mine = m.senderUserId === ME;
        if (m.conversationId === active && !mine) {
            if (msgsEl.querySelector('.ch-pad')) msgsEl.innerHTML = '';
            msgsEl.insertAdjacentHTML('beforeend', messageHtml({ senderUserId: m.senderUserId, senderName: m.senderName, body: m.body, createdDate: m.createdDate }, true));
            scrollBottom();
            post(BASE + '/Read', { conversationId: active }).catch(function () { });
        }
        refreshSoon();
    });
    document.addEventListener('proton:reconnected', function () {
        loadConversations();
        if (active) openThread(active);
    });

    // ---------- new message modal ----------
    var modal = document.getElementById('ch-modal');
    var contactsEl = document.getElementById('ch-contacts');
    var contactFilter = document.getElementById('ch-contact-filter');
    var chipsEl = document.getElementById('ch-chips');
    var modalBody = document.getElementById('ch-modal-body');
    var modalErr = document.getElementById('ch-modal-error');
    var modalSend = document.getElementById('ch-modal-send');
    var selectAll = document.getElementById('ch-select-all');
    var selCount = document.getElementById('ch-selected-count');
    var contacts = null;
    var selected = {};   // userID -> contact

    function renderChips() {
        var ids = Object.keys(selected);
        chipsEl.innerHTML = ids.slice(0, 12).map(function (id) {
            return '<span class="ch-chip">' + esc(selected[id].fullName) +
                '<button type="button" data-unselect="' + esc(id) + '" aria-label="Remove"><i data-lucide="x"></i></button></span>';
        }).join('') + (ids.length > 12 ? '<span class="ch-chip">+' + (ids.length - 12) + ' more</span>' : '');
        if (selCount) selCount.textContent = ids.length + ' selected';
        icons();
    }
    function visibleContacts() {
        var q = (contactFilter.value || '').toLowerCase();
        return (contacts || []).filter(function (c) {
            return !q || (c.fullName || '').toLowerCase().indexOf(q) >= 0 || (c.subtitle || '').toLowerCase().indexOf(q) >= 0;
        });
    }
    function renderContacts() {
        var rows = visibleContacts();
        if (!rows.length) { contactsEl.innerHTML = '<div class="ch-muted ch-pad">' + (contacts && contacts.length ? 'No matches.' : 'No one available to message yet.') + '</div>'; return; }
        var type = BROADCAST ? 'checkbox' : 'radio';
        contactsEl.innerHTML = rows.map(function (c) {
            return '<label class="ch-contact"><input type="' + type + '" name="ch-to" value="' + esc(c.userID) + '"' + (selected[c.userID] ? ' checked' : '') + ' />' +
                avatar(c.fullName, c.userID, c.userID === 'SUPPORT') +
                '<span><span class="ch-contact-name">' + esc(c.fullName) + '</span><br /><span class="ch-contact-sub">' +
                esc(c.kind === 'Student' ? c.subtitle : (c.subtitle || c.kind)) + '</span></span></label>';
        }).join('');
        if (selectAll) selectAll.checked = rows.length > 0 && rows.every(function (c) { return selected[c.userID]; });
        icons();
    }
    function openModal(preselect) {
        modal.hidden = false;
        modalErr.hidden = true;
        document.body.style.overflow = 'hidden';
        var ready = contacts ? Promise.resolve() : getJson(BASE + '/Contacts').then(function (c) { contacts = c; });
        ready.then(function () {
            if (preselect) {
                var c = contacts.find(function (x) { return x.userID === preselect; });
                if (c) { if (!BROADCAST) selected = {}; selected[c.userID] = c; }
            }
            renderContacts(); renderChips();
            (Object.keys(selected).length ? modalBody : contactFilter).focus();
        }).catch(function () { contactsEl.innerHTML = '<div class="ch-muted ch-pad">Could not load contacts.</div>'; });
    }
    function closeModal() { modal.hidden = true; document.body.style.overflow = ''; }

    document.querySelectorAll('#ch-new, [data-ch-new]').forEach(function (b) { b.addEventListener('click', function () { openModal(); }); });
    modal.querySelectorAll('[data-ch-close]').forEach(function (b) { b.addEventListener('click', closeModal); });
    document.addEventListener('keydown', function (e) { if (e.key === 'Escape' && !modal.hidden) closeModal(); });
    contactFilter.addEventListener('input', renderContacts);
    contactsEl.addEventListener('change', function (e) {
        var inp = e.target; if (!inp.name || inp.name !== 'ch-to') return;
        var c = contacts.find(function (x) { return x.userID === inp.value; });
        if (!BROADCAST) selected = {};
        if (inp.checked) selected[c.userID] = c; else delete selected[c.userID];
        renderChips();
        if (selectAll) selectAll.checked = visibleContacts().every(function (x) { return selected[x.userID]; });
    });
    if (selectAll) selectAll.addEventListener('change', function () {
        visibleContacts().forEach(function (c) { if (selectAll.checked) selected[c.userID] = c; else delete selected[c.userID]; });
        renderContacts(); renderChips();
    });
    chipsEl.addEventListener('click', function (e) {
        var b = e.target.closest('[data-unselect]'); if (!b) return;
        delete selected[b.dataset.unselect]; renderContacts(); renderChips();
    });

    modalSend.addEventListener('click', function () {
        var to = Object.keys(selected);
        var body = modalBody.value.trim();
        modalErr.hidden = true;
        if (!to.length) { modalErr.textContent = 'Choose who to send this to.'; modalErr.hidden = false; return; }
        if (!body) { modalErr.textContent = 'Write a message first.'; modalErr.hidden = false; modalBody.focus(); return; }
        modalSend.disabled = true;
        post(BASE + '/Send', { to: to, body: body }).then(function (res) {
            closeModal();
            modalBody.value = ''; selected = {}; renderChips();
            if (window.showToast) window.showToast(to.length > 1 ? 'Message sent to ' + to.length + ' students.' : 'Message sent.');
            return loadConversations().then(function () {
                if (res.conversationIds && res.conversationIds.length) openThread(res.conversationIds[0]);
            });
        }).catch(function (err) {
            modalErr.textContent = err.message; modalErr.hidden = false;
        }).finally(function () { modalSend.disabled = false; });
    });

    // ---------- boot ----------
    loadConversations().then(function () {
        if (app.dataset.open) openThread(app.dataset.open);
        if (app.dataset.composeTo) openModal(app.dataset.composeTo);
    });
    icons();
})();

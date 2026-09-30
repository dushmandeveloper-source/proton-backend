// Searchable category dropdown for Admin → Finance, with inline "add new
// category" (name + icon + colour + Fixed/Variable). Markup:
//   <div class="cp" data-catpicker data-kind="Expense" data-input="#fn-category"
//        data-allow-empty="All categories" data-create-url="/Admin/Finance/CreateCategory"
//        data-can-create="1" data-icons='[...]' data-cats='[{id,name,icon,color,group}]'></div>
// The chosen CategoryID goes into the hidden input named by data-input.
// Dispatches "cp:change" on the input when the value changes.
(function () {
    var COLORS = ['#7c3aed', '#6366f1', '#3b82f6', '#0ea5e9', '#06b6d4', '#14b8a6', '#10b981', '#22c55e', '#84cc16',
                  '#eab308', '#f59e0b', '#f97316', '#ef4444', '#f43f5e', '#ec4899', '#a855f7', '#64748b', '#78716c'];

    function esc(s) { var d = document.createElement('div'); d.textContent = s == null ? '' : String(s); return d.innerHTML; }
    function icons() { if (window.lucide && lucide.createIcons) lucide.createIcons(); }
    function token() { var t = document.querySelector('input[name="__RequestVerificationToken"]'); return t ? t.value : ''; }
    function tile(c, small) {
        return '<span class="cp-ic' + (small ? ' cp-ic-sm' : '') + '" style="color:' + c.color + ';background:' + c.color + '1f"><i data-lucide="' + esc(c.icon) + '"></i></span>';
    }

    function init(root) {
        var input = document.querySelector(root.dataset.input);
        var cats = JSON.parse(root.dataset.cats || '[]');
        var iconKeys = JSON.parse(root.dataset.icons || '[]');
        var kind = root.dataset.kind || 'Expense';
        var emptyLabel = root.dataset.allowEmpty || '';
        var canCreate = root.dataset.canCreate === '1';
        var open = false, activeIdx = -1;

        root.classList.add('cp');
        root.innerHTML =
            '<button type="button" class="cp-btn" aria-haspopup="listbox" aria-expanded="false"></button>' +
            '<div class="cp-panel" hidden>' +
            '  <div class="cp-search"><i data-lucide="search"></i><input type="search" placeholder="Search categories…" autocomplete="off" /></div>' +
            '  <div class="cp-list" role="listbox"></div>' +
            (canCreate ? '  <button type="button" class="cp-add"><i data-lucide="plus"></i> Add new category</button>' +
            '  <div class="cp-new" hidden>' +
            '    <div class="cp-new-row"><span class="cp-ic cp-new-preview"></span><input class="cp-new-name" maxlength="100" placeholder="Category name" /></div>' +
            (kind === 'Expense' ? '    <div class="cp-seg"><button type="button" data-g="Variable" class="on">Variable</button><button type="button" data-g="Fixed">Fixed</button></div>' : '') +
            '    <div class="cp-swatches"></div>' +
            '    <input type="search" class="cp-icon-search" placeholder="Search icons…" />' +
            '    <div class="cp-icons"></div>' +
            '    <div class="cp-new-err" hidden></div>' +
            '    <div class="cp-new-actions"><button type="button" class="cp-cancel">Cancel</button><button type="button" class="cp-save">Add &amp; select</button></div>' +
            '  </div>' : '') +
            '</div>';

        var btn = root.querySelector('.cp-btn'), panel = root.querySelector('.cp-panel');
        var search = root.querySelector('.cp-search input'), list = root.querySelector('.cp-list');

        function current() { return cats.find(function (c) { return c.id === input.value; }); }
        function renderBtn() {
            var c = current();
            btn.innerHTML = (c ? tile(c, true) + '<span class="cp-btn-name">' + esc(c.name) + '</span>' + (c.group && kind === 'Expense' ? '<span class="cp-tag">' + esc(c.group) + '</span>' : '')
                              : '<span class="cp-ic cp-ic-sm cp-ic-empty"><i data-lucide="shapes"></i></span><span class="cp-btn-name cp-placeholder">' + esc(emptyLabel || 'Choose a category') + '</span>') +
                            '<i data-lucide="chevrons-up-down" class="cp-caret"></i>';
            icons();
        }
        function visible() {
            var q = search.value.trim().toLowerCase();
            return cats.filter(function (c) { return !q || c.name.toLowerCase().indexOf(q) >= 0 || (c.group || '').toLowerCase() === q; });
        }
        function renderList() {
            var rows = visible();
            var html = '';
            if (emptyLabel && !search.value.trim())
                html += '<div class="cp-opt' + (!input.value ? ' sel' : '') + '" data-id="" role="option"><span class="cp-ic cp-ic-sm cp-ic-empty"><i data-lucide="layers"></i></span><span>' + esc(emptyLabel) + '</span></div>';
            rows.forEach(function (c) {
                html += '<div class="cp-opt' + (c.id === input.value ? ' sel' : '') + '" data-id="' + esc(c.id) + '" role="option">' + tile(c, true) +
                        '<span class="cp-opt-name">' + esc(c.name) + '</span>' + (kind === 'Expense' && c.group ? '<span class="cp-tag">' + esc(c.group) + '</span>' : '') +
                        (c.id === input.value ? '<i data-lucide="check" class="cp-check"></i>' : '') + '</div>';
            });
            if (!rows.length) html += '<div class="cp-none">No match' + (canCreate ? '. Add it as a new category below.' : '') + '</div>';
            list.innerHTML = html;
            activeIdx = -1;
            icons();
        }
        function choose(id) {
            input.value = id;
            input.dispatchEvent(new CustomEvent('cp:change', { bubbles: true, detail: { id: id } }));
            renderBtn(); close();
        }
        function openPanel() {
            if (open) return; open = true;
            panel.hidden = false; btn.setAttribute('aria-expanded', 'true'); root.classList.add('open');
            search.value = ''; renderList(); setTimeout(function () { search.focus(); }, 10);
        }
        function close() {
            open = false; panel.hidden = true; btn.setAttribute('aria-expanded', 'false'); root.classList.remove('open');
            var nf = root.querySelector('.cp-new'); if (nf) nf.hidden = true;
            var ab = root.querySelector('.cp-add'); if (ab) ab.hidden = false;
        }
        function move(d) {
            var opts = list.querySelectorAll('.cp-opt'); if (!opts.length) return;
            activeIdx = (activeIdx + d + opts.length) % opts.length;
            opts.forEach(function (o, i) { o.classList.toggle('active', i === activeIdx); });
            opts[activeIdx].scrollIntoView({ block: 'nearest' });
        }

        btn.addEventListener('click', function () { open ? close() : openPanel(); });
        search.addEventListener('input', renderList);
        search.addEventListener('keydown', function (e) {
            if (e.key === 'ArrowDown') { e.preventDefault(); move(1); }
            else if (e.key === 'ArrowUp') { e.preventDefault(); move(-1); }
            else if (e.key === 'Enter') {
                e.preventDefault();
                var opts = list.querySelectorAll('.cp-opt');
                var pick = opts[activeIdx >= 0 ? activeIdx : (emptyLabel && !search.value.trim() ? 1 : 0)];
                if (pick) choose(pick.dataset.id);
            } else if (e.key === 'Escape') { e.stopPropagation(); close(); btn.focus(); }
        });
        list.addEventListener('click', function (e) { var o = e.target.closest('.cp-opt'); if (o) choose(o.dataset.id); });
        document.addEventListener('click', function (e) { if (open && !root.contains(e.target)) close(); });

        // ----- inline "add new category" -----
        if (canCreate) {
            var addBtn = root.querySelector('.cp-add'), nf = root.querySelector('.cp-new');
            var nameIn = nf.querySelector('.cp-new-name'), preview = nf.querySelector('.cp-new-preview');
            var sw = nf.querySelector('.cp-swatches'), iconGrid = nf.querySelector('.cp-icons'), iconSearch = nf.querySelector('.cp-icon-search');
            var err = nf.querySelector('.cp-new-err');
            var st = { icon: 'circle-dollar-sign', color: '#7c3aed', group: 'Variable' };
            sw.innerHTML = COLORS.map(function (c) { return '<button type="button" data-c="' + c + '" style="background:' + c + '" aria-label="' + c + '"></button>'; }).join('');
            function drawIcons() {
                var q = iconSearch.value.trim().toLowerCase();
                iconGrid.innerHTML = iconKeys.filter(function (k) { return !q || k.indexOf(q) >= 0; }).map(function (k) {
                    return '<button type="button" data-i="' + k + '" title="' + k + '" class="' + (k === st.icon ? 'on' : '') + '"><i data-lucide="' + k + '"></i></button>';
                }).join('');
                icons();
            }
            function paint() {
                preview.style.color = st.color; preview.style.background = st.color + '1f';
                preview.innerHTML = '<i data-lucide="' + st.icon + '"></i>';
                sw.querySelectorAll('button').forEach(function (b) { b.classList.toggle('on', b.dataset.c === st.color); });
                iconGrid.querySelectorAll('button').forEach(function (b) { b.classList.toggle('on', b.dataset.i === st.icon); });
                icons();
            }
            addBtn.addEventListener('click', function () {
                nf.hidden = false; addBtn.hidden = true; err.hidden = true;
                nameIn.value = search.value.trim(); iconSearch.value = '';
                drawIcons(); paint(); nameIn.focus();
            });
            nf.querySelector('.cp-cancel').addEventListener('click', function () { nf.hidden = true; addBtn.hidden = false; });
            sw.addEventListener('click', function (e) { var b = e.target.closest('button'); if (b) { st.color = b.dataset.c; paint(); } });
            iconGrid.addEventListener('click', function (e) { var b = e.target.closest('button'); if (b) { st.icon = b.dataset.i; paint(); } });
            iconSearch.addEventListener('input', drawIcons);
            nf.querySelectorAll('.cp-seg button').forEach(function (b) {
                b.addEventListener('click', function () {
                    st.group = b.dataset.g;
                    nf.querySelectorAll('.cp-seg button').forEach(function (x) { x.classList.toggle('on', x === b); });
                });
            });
            nameIn.addEventListener('keydown', function (e) { if (e.key === 'Enter') { e.preventDefault(); nf.querySelector('.cp-save').click(); } });
            nf.querySelector('.cp-save').addEventListener('click', function () {
                var name = nameIn.value.trim();
                if (!name) { err.textContent = 'Give the category a name.'; err.hidden = false; nameIn.focus(); return; }
                var fd = new FormData();
                fd.append('Kind', kind); fd.append('CategoryName', name); fd.append('IconKey', st.icon);
                fd.append('Color', st.color); fd.append('CategoryGroup', st.group);
                var saveBtn = this; saveBtn.disabled = true;
                fetch(root.dataset.createUrl, { method: 'POST', body: fd, credentials: 'same-origin', headers: { 'RequestVerificationToken': token() } })
                    .then(function (r) { return r.json().then(function (j) { if (!r.ok) throw new Error(j.message || 'Could not add the category.'); return j; }); })
                    .then(function (c) {
                        cats.push(c);
                        cats.sort(function (a, b) { return a.name.localeCompare(b.name); });
                        // Keep any other picker for the same kind on this page in sync.
                        document.querySelectorAll('[data-catpicker][data-kind="' + kind + '"]').forEach(function (other) {
                            if (other !== root && other.__cp) other.__cp.add(c);
                        });
                        choose(c.id);
                        if (window.showToast) window.showToast('Category "' + c.name + '" added.');
                    })
                    .catch(function (x) { err.textContent = x.message; err.hidden = false; })
                    .finally(function () { saveBtn.disabled = false; });
            });
        }

        root.__cp = {
            set: function (id) { input.value = id || ''; renderBtn(); },
            add: function (c) { if (!cats.some(function (x) { return x.id === c.id; })) { cats.push(c); cats.sort(function (a, b) { return a.name.localeCompare(b.name); }); } }
        };
        renderBtn();
    }

    function boot() { document.querySelectorAll('[data-catpicker]').forEach(function (el) { if (!el.__cp) init(el); }); }
    if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', boot); else boot();
    window.FinCatPicker = { boot: boot };
})();

// Admin → Exam → Questions → "Import from Word".
// Step 1 uploads the .docx to ReadWord (parse only). Step 2 shows every
// question as an editable card with a live preview; nothing is saved until
// "Import" posts the reviewed list to ImportQuestions. Needs exam-math.js
// (renderMixedLatex) and the #wi-modal markup in Exam/Edit.cshtml.
(function () {
    let items = [];

    const $ = id => document.getElementById(id);
    const modal = () => $('wi-modal');
    const token = () => document.querySelector('#af-token-holder input[name="__RequestVerificationToken"]')?.value || '';
    const icons = () => { if (window.lucide) lucide.createIcons(); };

    window.openWordImport = function () {
        $('wi-template').href = modal().dataset.templateUrl;
        showStep('upload');
        modal().classList.remove('hidden');
        document.body.style.overflow = 'hidden';
        icons();
    };
    window.closeWordImport = function () {
        if (items.length && !$('wi-step-review').classList.contains('hidden')
            && !confirm('Close without importing? The questions you reviewed will be discarded.')) return;
        modal().classList.add('hidden');
        document.body.style.overflow = '';
        items = [];
    };
    window.wiBack = function () { items = []; showStep('upload'); };

    window.wiCopyPrompt = async function () {
        const text = $('wi-prompt').value;
        const label = $('wi-copy-prompt').querySelector('span');
        try {
            await navigator.clipboard.writeText(text);
        } catch {
            // clipboard API needs https/permission — fall back to selecting the text
            const ta = $('wi-prompt');
            ta.closest('details').open = true;
            ta.focus(); ta.select();
            document.execCommand('copy');
        }
        label.textContent = 'Copied!';
        setTimeout(() => label.textContent = 'Copy prompt', 2000);
    };

    function showStep(step) {
        const review = step === 'review';
        $('wi-step-upload').classList.toggle('hidden', review);
        $('wi-step-review').classList.toggle('hidden', !review);
        $('wi-back').classList.toggle('hidden', !review);
        $('wi-import').classList.toggle('hidden', !review);
        $('wi-subtitle').textContent = review ? 'Step 2 of 2 — check and fix, then import' : 'Step 1 of 2 — choose the file';
        $('wi-footer-note').textContent = '';
        if (!review) {
            $('wi-file').value = '';
            $('wi-error').classList.add('hidden');
            $('wi-reading').classList.add('hidden');
        }
    }

    // ---------- Step 1: read the file ----------
    document.addEventListener('DOMContentLoaded', () => {
        const input = $('wi-file'), drop = $('wi-drop');
        if (!input) return;
        input.addEventListener('change', () => { if (input.files[0]) readFile(input.files[0]); });
        ['dragenter', 'dragover'].forEach(ev => drop.addEventListener(ev, e => { e.preventDefault(); drop.classList.add('border-[#7c3aed]'); }));
        ['dragleave', 'drop'].forEach(ev => drop.addEventListener(ev, e => { e.preventDefault(); drop.classList.remove('border-[#7c3aed]'); }));
        drop.addEventListener('drop', e => { const f = e.dataTransfer.files[0]; if (f) readFile(f); });
    });

    function showError(msg) {
        $('wi-reading').classList.add('hidden');
        const box = $('wi-error');
        box.textContent = msg;
        box.classList.remove('hidden');
    }

    async function readFile(file) {
        $('wi-error').classList.add('hidden');
        if (!/\.(docx|doc)$/i.test(file.name)) return showError('Please choose a Word file (.docx).');
        if (file.size > 30 * 1024 * 1024) return showError('The file is larger than 30 MB — compress the pictures in Word and try again.');
        $('wi-reading').classList.remove('hidden');
        const fd = new FormData();
        fd.append('file', file);
        fd.append('__RequestVerificationToken', token());
        try {
            const res = await fetch(modal().dataset.readUrl, { method: 'POST', body: fd });
            if (res.status === 401 || res.redirected) return showError('Your login has expired — refresh the page and sign in again.');
            const data = await res.json();
            if (!data.success) return showError(data.message || 'Could not read the file.');
            $('wi-reading').classList.add('hidden');
            startReview(data.result, file.name);
        } catch {
            showError('Could not reach the server — check your connection and try again.');
        }
    }

    // ---------- Step 2: review ----------
    function startReview(result, fileName) {
        items = (result.questions || []).map(q => ({
            number: q.number,
            include: true,
            text: q.text || '',
            type: q.questionType === 'Written' ? 'Written' : 'MCQ',
            marks: q.marks ?? null,
            options: (q.options || []).map(o => ({ text: o.text || '', correct: !!o.correct })),
            image: q.imageDataUrl || null,
            warnings: q.warnings || []
        }));
        if (items.length === 0) {
            return showError((result.warnings || []).join(' ') || 'No questions were found in this file.');
        }
        const existing = items.find(i => i.marks != null);
        $('wi-all-marks').value = existing ? existing.marks : 1;
        items.forEach(i => { if (i.marks == null) i.marks = Number($('wi-all-marks').value) || 1; });

        const fw = $('wi-file-warnings');
        fw.classList.toggle('hidden', !(result.warnings || []).length);
        fw.textContent = (result.warnings || []).join(' ');
        $('wi-only-issues').checked = false;

        const list = $('wi-list');
        list.innerHTML = '';
        items.forEach((item, idx) => list.appendChild(buildCard(item, idx)));
        showStep('review');
        refreshSummary();
        icons();
    }

    function issues(item) {
        const out = [];
        if (!item.text.trim()) out.push('No question text');
        if (!(Number(item.marks) > 0)) out.push('Marks must be more than 0');
        if (item.type === 'MCQ') {
            const filled = item.options.filter(o => o.text.trim());
            if (filled.length < 2) out.push('Needs at least 2 options');
            if (item.options.filter(o => o.correct && o.text.trim()).length !== 1) out.push('Tick the correct answer');
        }
        return out;
    }

    function buildCard(item, idx) {
        const card = document.createElement('div');
        card.className = 'wi-card rounded-2xl border border-slate-100 dark:border-slate-700 bg-white dark:bg-slate-900/40 transition';
        card.innerHTML = `
            <div class="flex flex-wrap items-center gap-3 px-4 py-3 border-b border-slate-100 dark:border-slate-700">
                <label class="flex items-center gap-2 cursor-pointer select-none">
                    <input type="checkbox" class="wi-include w-4 h-4 accent-[#7c3aed]" />
                    <span class="text-sm font-semibold text-slate-800 dark:text-slate-100">Q${idx + 1}</span>
                </label>
                <select class="wi-type px-2 py-1 rounded-lg border border-slate-200 dark:border-slate-600 bg-white dark:bg-slate-800 text-xs">
                    <option value="MCQ">Multiple choice</option><option value="Written">Written</option>
                </select>
                <label class="flex items-center gap-1.5 text-xs text-slate-500 dark:text-slate-400">Marks
                    <input type="number" min="0.5" step="0.5" class="wi-marks w-16 px-2 py-1 rounded-lg border border-slate-200 dark:border-slate-600 bg-white dark:bg-slate-800 text-xs" />
                </label>
                <span class="wi-status ml-auto inline-flex items-center gap-1 px-2 py-0.5 rounded-full text-[11px] font-semibold"></span>
            </div>
            <div class="wi-body grid grid-cols-1 lg:grid-cols-2 gap-4 p-4">
                <div class="space-y-3 min-w-0">
                    <textarea rows="2" class="wi-text eq-text block w-full resize-none rounded-xl border border-slate-200 dark:border-slate-600 bg-white dark:bg-slate-800 px-3 py-2 text-sm leading-relaxed text-slate-800 dark:text-slate-100 focus:outline-none focus:border-[#7c3aed] focus:ring-2 focus:ring-[#7c3aed]/20"></textarea>
                    <div class="wi-options space-y-1.5"></div>
                    <button type="button" class="wi-add-option text-xs text-[#7c3aed] hover:underline">+ Add option</button>
                    <ul class="wi-warnings space-y-1 text-xs text-amber-700 dark:text-amber-300"></ul>
                </div>
                <div class="min-w-0 rounded-xl bg-slate-50 dark:bg-slate-800/60 border border-slate-100 dark:border-slate-700 p-4">
                    <p class="text-[11px] uppercase tracking-wide font-semibold text-slate-400 mb-2">Preview</p>
                    <div class="wi-prev-text text-sm text-slate-800 dark:text-slate-100 mb-3"></div>
                    <div class="wi-prev-img hidden relative mb-3 inline-block">
                        <img alt="" class="max-w-full max-h-56 rounded-lg border border-slate-100 dark:border-slate-700 bg-white p-1" />
                        <button type="button" class="wi-remove-img absolute -top-2 -right-2 w-6 h-6 rounded-full bg-white dark:bg-slate-700 border border-slate-200 dark:border-slate-600 text-slate-500 hover:text-red-600 flex items-center justify-center shadow-sm" title="Remove picture"><i data-lucide="x" class="w-3.5 h-3.5"></i></button>
                    </div>
                    <div class="wi-prev-options space-y-1"></div>
                </div>
            </div>`;

        card.querySelector('.wi-include').checked = item.include;
        card.querySelector('.wi-type').value = item.type;
        card.querySelector('.wi-marks').value = item.marks;
        const ta = card.querySelector('.wi-text');
        ta.value = item.text;

        card.querySelector('.wi-include').addEventListener('change', e => { item.include = e.target.checked; update(); });
        card.querySelector('.wi-type').addEventListener('change', e => { item.type = e.target.value; update(); });
        card.querySelector('.wi-marks').addEventListener('input', e => { item.marks = e.target.value; update(); });
        ta.addEventListener('input', () => { item.text = ta.value; grow(ta); update(); });
        card.querySelector('.wi-add-option').addEventListener('click', () => { item.options.push({ text: '', correct: false }); renderOptions(); update(); });
        card.querySelector('.wi-remove-img').addEventListener('click', () => { item.image = null; update(); });

        const warnList = card.querySelector('.wi-warnings');
        item.warnings.forEach(w => {
            const li = document.createElement('li');
            li.className = 'flex gap-1.5';
            li.innerHTML = '<span aria-hidden="true">⚠</span><span></span>';
            li.lastChild.textContent = w;
            warnList.appendChild(li);
        });

        function renderOptions() {
            const box = card.querySelector('.wi-options');
            box.innerHTML = '';
            item.options.forEach((opt, i) => {
                const row = document.createElement('div');
                row.className = 'flex items-center gap-2';
                row.innerHTML = `
                    <span class="w-5 text-xs font-semibold text-slate-400 text-center">${String.fromCharCode(65 + i)}</span>
                    <input type="text" class="flex-1 min-w-0 px-2.5 py-1.5 rounded-lg border border-slate-200 dark:border-slate-600 bg-white dark:bg-slate-800 text-sm focus:outline-none focus:border-[#7c3aed]" />
                    <label class="flex items-center gap-1 text-xs text-slate-500 dark:text-slate-400 cursor-pointer"><input type="radio" class="w-4 h-4 accent-emerald-600" /> Correct</label>
                    <button type="button" class="text-slate-400 hover:text-red-600" title="Remove option"><i data-lucide="x" class="w-4 h-4"></i></button>`;
                const [input, radio, remove] = [row.querySelector('input[type=text]'), row.querySelector('input[type=radio]'), row.querySelector('button')];
                input.value = opt.text;
                radio.name = 'wi-correct-' + idx;
                radio.checked = opt.correct;
                input.addEventListener('input', () => { opt.text = input.value; update(); });
                radio.addEventListener('change', () => { item.options.forEach(o => o.correct = o === opt); update(); });
                remove.addEventListener('click', () => { item.options.splice(i, 1); renderOptions(); update(); });
                box.appendChild(row);
            });
            icons();
        }

        function update() {
            const isMcq = item.type === 'MCQ';
            card.querySelector('.wi-options').classList.toggle('hidden', !isMcq);
            card.querySelector('.wi-add-option').classList.toggle('hidden', !isMcq);
            card.querySelector('.wi-body').classList.toggle('opacity-50', !item.include);

            const pt = card.querySelector('.wi-prev-text');
            pt.dataset.rendered = '';
            if (item.text.trim()) renderMixedLatex(item.text, pt); else pt.textContent = '—';

            const pi = card.querySelector('.wi-prev-img');
            pi.classList.toggle('hidden', !item.image);
            if (item.image) pi.querySelector('img').src = item.image;

            const po = card.querySelector('.wi-prev-options');
            po.innerHTML = '';
            if (isMcq) item.options.filter(o => o.text.trim()).forEach(o => {
                const line = document.createElement('div');
                line.className = 'flex items-start gap-2 text-sm';
                line.innerHTML = `<span class="mt-0.5 w-4 h-4 shrink-0 rounded-full border-2 ${o.correct ? 'border-emerald-500 bg-emerald-500' : 'border-slate-300 dark:border-slate-600'}"></span><span class="min-w-0 flex-1"></span>`;
                renderMixedLatex(o.text, line.lastChild);
                po.appendChild(line);
            });

            const probs = item.include ? issues(item) : [];
            card.dataset.issue = probs.length ? '1' : '';
            const st = card.querySelector('.wi-status');
            st.className = 'wi-status ml-auto inline-flex items-center gap-1 px-2 py-0.5 rounded-full text-[11px] font-semibold ' + (
                !item.include ? 'bg-slate-100 dark:bg-slate-800 text-slate-500'
                : probs.length ? 'bg-red-50 dark:bg-red-950 text-red-600 dark:text-red-300'
                : 'bg-emerald-50 dark:bg-emerald-950 text-emerald-600 dark:text-emerald-300');
            st.textContent = !item.include ? 'Skipped' : probs.length ? probs.join(' · ') : 'Ready';
            card.classList.toggle('border-red-200', probs.length > 0);
            card.classList.toggle('dark:border-red-900', probs.length > 0);
            refreshSummary();
        }

        item.update = update;
        renderOptions();
        update();
        requestAnimationFrame(() => grow(ta));
        return card;
    }

    function grow(el) { el.style.height = 'auto'; el.style.height = el.scrollHeight + 'px'; }

    function refreshSummary() {
        const included = items.filter(i => i.include);
        const bad = included.filter(i => issues(i).length);
        const pics = included.filter(i => i.image).length;
        $('wi-summary').textContent = `${items.length} found · ${included.length} selected · ${pics} with pictures`;
        $('wi-footer-note').textContent = bad.length
            ? `${bad.length} question${bad.length === 1 ? '' : 's'} need${bad.length === 1 ? 's' : ''} attention — fix or untick ${bad.length === 1 ? 'it' : 'them'} to import.`
            : included.length ? 'All selected questions are ready. They will be added after the existing questions.' : 'Select at least one question.';
        const btn = $('wi-import');
        btn.disabled = bad.length > 0 || included.length === 0;
        $('wi-import-label').textContent = `Import ${included.length} question${included.length === 1 ? '' : 's'}`;
        if ($('wi-only-issues').checked) wiFilter();
    }

    window.wiFilter = function () {
        const only = $('wi-only-issues').checked;
        document.querySelectorAll('#wi-list .wi-card').forEach(c => c.classList.toggle('hidden', only && c.dataset.issue !== '1'));
    };

    window.wiApplyMarks = function () {
        const v = Number($('wi-all-marks').value);
        if (!(v > 0)) return;
        items.forEach((item, i) => {
            item.marks = v;
            document.querySelectorAll('#wi-list .wi-marks')[i].value = v;
            item.update();
        });
    };

    // ---------- Import ----------
    const extFor = type => ({ 'image/png': '.png', 'image/jpeg': '.jpg', 'image/gif': '.gif', 'image/bmp': '.bmp', 'image/tiff': '.tif', 'image/webp': '.webp', 'image/svg+xml': '.svg' }[type] || '.png');

    window.wiImport = async function () {
        const chosen = items.filter(i => i.include);
        if (!chosen.length || chosen.some(i => issues(i).length)) return;
        const btn = $('wi-import');
        btn.disabled = true;
        $('wi-import-label').textContent = 'Importing…';

        const fd = new FormData();
        fd.append('ExamID', modal().dataset.examId);
        fd.append('__RequestVerificationToken', token());
        fd.append('QuestionsJson', JSON.stringify(chosen.map(i => ({
            text: i.text.trim(),
            questionType: i.type,
            marks: Number(i.marks),
            options: i.type === 'MCQ' ? i.options.filter(o => o.text.trim()).map(o => ({ text: o.text.trim(), correct: o.correct })) : []
        }))));
        for (let n = 0; n < chosen.length; n++) {
            if (!chosen[n].image) continue;
            const blob = await (await fetch(chosen[n].image)).blob();
            fd.append('image_' + n, blob, 'q' + (n + 1) + extFor(blob.type));
        }

        try {
            const res = await fetch(modal().dataset.importUrl, { method: 'POST', body: fd });
            const data = await res.json();
            if (data.success) {
                items = [];
                $('wi-footer-note').textContent = data.message;
                location.reload();
                return;
            }
            fail(data.message || 'Import failed.');
        } catch {
            fail('Could not reach the server — nothing was imported. Try again.');
        }
    };

    function fail(msg) {
        refreshSummary();
        const note = $('wi-footer-note');
        note.textContent = msg;
        note.classList.add('text-red-600', 'dark:text-red-400');
        setTimeout(() => note.classList.remove('text-red-600', 'dark:text-red-400'), 8000);
    }
})();

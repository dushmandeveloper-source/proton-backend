// Enrollment step of the Admin and Agent register-student wizards
// (Views/Shared/_EnrollmentPicker.cshtml). Keeps three hidden JSON maps in
// sync for the server -- CourseCurrencySelectionsJson, CourseScheduleSelectionsJson,
// CoursePaymentsJson (all keyed by CourseID) -- and exposes
// window.protonValidateEnrollmentStep() for the wizard's Next/Save buttons.
// Prices here are display only; the server re-prices every registration.
(function () {
    'use strict';
    var root = document.getElementById('enrollmentPicker');
    if (!root) return;

    var slipForCash = root.dataset.slipForCash === '1';
    var slipRequired = root.dataset.slipRequired === '1';
    var requireBatch = root.dataset.requireBatch !== '0';
    var boxes = Array.prototype.slice.call(root.querySelectorAll('.course-checkbox'));
    var currencyJson = document.getElementById('courseCurrencySelectionsJson');
    var scheduleJson = document.getElementById('courseScheduleSelectionsJson');
    var paymentJson = document.getElementById('coursePaymentsJson');
    var summary = document.getElementById('epSummary');
    var summaryCount = document.getElementById('epSummaryCount');
    var totalEl = document.getElementById('enrollmentTotal');

    function fmt(n) {
        return (Number(n) || 0).toLocaleString(undefined, { minimumFractionDigits: 2, maximumFractionDigits: 2 });
    }
    function byCourse(selector, id) {
        var all = root.querySelectorAll(selector);
        for (var i = 0; i < all.length; i++) {
            if (all[i].getAttribute('data-course-id') === id || all[i].getAttribute('data-course-card') === id) return all[i];
        }
        return null;
    }
    function panelFor(id) { return byCourse('.ep-panel', id); }
    function cardFor(id) { return byCourse('[data-course-card]', id); }
    function show(el, on) { if (el) el.classList.toggle('hidden', !on); }
    function setError(el, msg) { if (!el) return; el.textContent = msg || ''; show(el, !!msg); }

    function methodFor(panel) {
        var r = panel.querySelector('.course-payment-method-radio:checked');
        return r ? r.value : '';
    }
    function currencyRadio(panel) {
        return panel.querySelector('.ep-currency-radio:checked') || panel.querySelector('.ep-currency-radio');
    }

    // ---- Currency: reprice the card, panel header and amount cap ----
    function applyCurrency(id) {
        var panel = panelFor(id), card = cardFor(id), box = card && card.querySelector('.course-checkbox');
        var r = panel && currencyRadio(panel);
        if (!r || !box) return;
        var code = r.value;
        var total = parseFloat(r.dataset.total) || 0;
        var raw = parseFloat(r.dataset.rawFee) || 0;
        var fees = parseFloat(r.dataset.feeCharges) || 0;
        var label = r.dataset.discountLabel || '';

        box.dataset.currency = code;
        box.dataset.fee = String(total);

        var strike = card.querySelector('.ep-price-strike');
        if (strike) { strike.textContent = code + ' ' + fmt(raw); show(strike, !!label); }
        var tot = card.querySelector('.ep-price-total');
        if (tot) tot.textContent = code + ' ' + fmt(total);
        var disc = card.querySelector('.ep-price-discount');
        if (disc) { disc.textContent = label; show(disc, !!label); }
        var feeEl = card.querySelector('.ep-price-fees');
        if (feeEl) { feeEl.textContent = 'incl. ' + code + ' ' + fmt(fees) + ' fees'; show(feeEl, fees > 0); }

        var head = panel.querySelector('.ep-panel-price');
        if (head) head.textContent = code + ' ' + fmt(total);
        var amount = panel.querySelector('.course-payment-amount');
        if (amount) amount.max = total.toFixed(2);
        var cur = panel.querySelector('.ep-amount-currency');
        if (cur) cur.textContent = code;
        var hint = panel.querySelector('.ep-amount-hint');
        if (hint) hint.textContent = 'Up to ' + code + ' ' + fmt(total) + '. A part payment is fine — the rest is paid later.';
        checkAmount(id, false);
    }

    // ---- Payment method: reveal amount/notes, and the slip where it applies ----
    function syncPayment(id) {
        var panel = panelFor(id);
        if (!panel) return;
        var method = methodFor(panel);
        show(panel.querySelector('.ep-pay-fields'), !!method);
        var wantsSlip = method === 'BankDeposit' || (slipForCash && method === 'Cash');
        show(panel.querySelector('.course-payment-slip-field'), wantsSlip);
        var label = panel.querySelector('.ep-slip-label');
        if (label) {
            var needed = slipRequired && method === 'BankDeposit';
            label.textContent = (method === 'Cash' ? 'Cash receipt' : 'Bank deposit slip') + (needed ? '' : ' (optional)');
        }
        if (!method) {
            // "None": drop any typed amount so a hidden, out-of-range value
            // can't block the browser's own form validation on Save.
            var amt = panel.querySelector('.course-payment-amount');
            if (amt) { amt.value = ''; amt.classList.remove('text-red-600'); }
            setError(panel.querySelector('.course-payment-amount-error'), '');
            setError(panel.querySelector('.ep-slip-error'), '');
        }
    }

    function checkAmount(id, requireValue) {
        var panel = panelFor(id);
        if (!panel) return true;
        var input = panel.querySelector('.course-payment-amount');
        var err = panel.querySelector('.course-payment-amount-error');
        if (!input || !methodFor(panel)) { setError(err, ''); return true; }
        var max = parseFloat(input.max);
        var value = parseFloat(input.value);
        var r = currencyRadio(panel);
        var code = r ? r.value : '';
        var msg = '';
        if (!isNaN(value) && value < 0) msg = 'The amount can’t be negative.';
        else if (!isNaN(max) && value > max) msg = 'Can’t be more than the course fee (' + code + ' ' + fmt(max) + ').';
        else if (requireValue && !(value > 0)) msg = 'Enter the amount received, or choose “None”.';
        setError(err, msg);
        input.classList.toggle('text-red-600', !!msg);
        return !msg;
    }

    // ---- Hidden JSON + running totals ----
    function rebuild() {
        var currencies = {}, schedules = {}, payments = {}, totals = {}, order = [], count = 0;
        boxes.forEach(function (box) {
            if (!box.checked) return;
            var id = box.value, panel = panelFor(id);
            count++;
            var code = box.dataset.currency || '';
            currencies[id] = code;
            if (!(code in totals)) { totals[code] = 0; order.push(code); }
            totals[code] += parseFloat(box.dataset.fee) || 0;
            if (!panel) return;
            var batch = panel.querySelector('.ep-batch-radio:checked');
            schedules[id] = batch ? batch.value : '';
            var method = methodFor(panel);
            if (method) {
                var amount = panel.querySelector('.course-payment-amount');
                var notes = panel.querySelector('.course-payment-notes');
                payments[id] = {
                    method: method,
                    amount: amount ? (parseFloat(amount.value) || 0) : 0,
                    notes: notes ? notes.value : ''
                };
            }
        });
        if (currencyJson) currencyJson.value = JSON.stringify(currencies);
        if (scheduleJson) scheduleJson.value = JSON.stringify(schedules);
        if (paymentJson) paymentJson.value = JSON.stringify(payments);

        show(summary, count > 0);
        if (summaryCount) summaryCount.textContent = count + (count === 1 ? ' course selected' : ' courses selected');
        if (totalEl) {
            // One total per currency -- never add LKR to USD.
            totalEl.textContent = 'Total: ' + order.map(function (c) { return c + ' ' + fmt(totals[c]); }).join(' · ');
        }
    }

    // ---- Reset a course to its defaults when it's unticked ----
    function resetPanel(id) {
        var panel = panelFor(id);
        if (!panel) return;
        panel.querySelectorAll('.ep-currency-radio').forEach(function (r) { r.checked = r.defaultChecked; });
        panel.querySelectorAll('.ep-batch-radio').forEach(function (r) { r.checked = r.defaultChecked; });
        panel.querySelectorAll('.course-payment-method-radio').forEach(function (r) { r.checked = r.value === ''; });
        panel.querySelectorAll('.course-payment-amount, .course-payment-notes').forEach(function (i) { i.value = ''; });
        var file = panel.querySelector('.ep-slip-input');
        if (file) { file.value = ''; updateFileName(file); }
        setError(panel.querySelector('.ep-batch-error'), '');
        applyCurrency(id);
        syncPayment(id);
    }

    function updateFileName(input) {
        var drop = input.closest('.ep-drop');
        var name = drop && drop.querySelector('.ep-file-name');
        if (name) name.textContent = input.files && input.files.length ? input.files[0].name : 'Choose a photo or PDF';
        if (input.files && input.files.length) {
            var panel = input.closest('.ep-panel');
            if (panel) setError(panel.querySelector('.ep-slip-error'), '');
        }
    }

    // ---- Wiring ----
    boxes.forEach(function (box) {
        box.addEventListener('change', function () {
            var id = box.value, panel = panelFor(id);
            show(panel, box.checked);
            if (!box.checked) resetPanel(id);
            rebuild();
        });
    });
    root.querySelectorAll('.ep-remove').forEach(function (btn) {
        btn.addEventListener('click', function () {
            var box = cardFor(btn.getAttribute('data-course-id'));
            box = box && box.querySelector('.course-checkbox');
            if (!box) return;
            box.checked = false;
            box.dispatchEvent(new Event('change', { bubbles: true }));
            box.focus();
        });
    });
    root.querySelectorAll('.ep-currency-radio').forEach(function (r) {
        r.addEventListener('change', function () { applyCurrency(r.dataset.courseId); rebuild(); });
    });
    root.querySelectorAll('.ep-batch-radio').forEach(function (r) {
        r.addEventListener('change', function () {
            var panel = panelFor(r.dataset.courseId);
            if (panel) setError(panel.querySelector('.ep-batch-error'), '');
            rebuild();
        });
    });
    root.querySelectorAll('.course-payment-method-radio').forEach(function (r) {
        r.addEventListener('change', function () {
            syncPayment(r.dataset.courseId);
            checkAmount(r.dataset.courseId, false);
            rebuild();
        });
    });
    root.querySelectorAll('.course-payment-amount').forEach(function (i) {
        i.addEventListener('input', function () { checkAmount(i.dataset.courseId, false); rebuild(); });
    });
    root.querySelectorAll('.course-payment-notes').forEach(function (i) { i.addEventListener('input', rebuild); });
    root.querySelectorAll('.ep-slip-input').forEach(function (i) {
        i.addEventListener('change', function () { updateFileName(i); });
    });

    var search = document.getElementById('epSearch');
    if (search) {
        var noMatch = document.getElementById('epNoMatch');
        search.addEventListener('input', function () {
            var q = search.value.trim().toLowerCase(), any = false;
            root.querySelectorAll('[data-course-card]').forEach(function (card) {
                var hit = !q || (card.getAttribute('data-search') || '').indexOf(q) !== -1;
                card.classList.toggle('hidden', !hit);
                if (hit) any = true;
            });
            show(noMatch, !any);
        });
        // Enter in the search box must not submit the whole wizard.
        search.addEventListener('keydown', function (e) { if (e.key === 'Enter') e.preventDefault(); });
    }

    // Initial state (also restores selections after a failed save).
    boxes.forEach(function (box) {
        applyCurrency(box.value);
        syncPayment(box.value);
        show(panelFor(box.value), box.checked);
    });
    rebuild();

    // ---- Step validation (wizard Next / Save) ----
    window.protonValidateEnrollmentStep = function () {
        var firstBad = null;
        boxes.forEach(function (box) {
            if (!box.checked) return;
            var id = box.value, panel = panelFor(id);
            if (!panel) return;
            var ok = true;

            var batches = panel.querySelectorAll('.ep-batch-radio:not(.ep-no-batch)');
            if (batches.length) {
                var open = Array.prototype.filter.call(batches, function (r) { return !r.disabled; });
                var picked = panel.querySelector('.ep-batch-radio:checked');
                var batchErr = panel.querySelector('.ep-batch-error');
                if (!open.length) { setError(batchErr, 'Every batch of this course is closed — untick it to continue.'); ok = false; }
                else if (!picked && requireBatch) { setError(batchErr, 'Choose a batch for this course.'); ok = false; }
                else setError(batchErr, '');
            }

            var method = methodFor(panel);
            if (method) {
                if (!checkAmount(id, true)) ok = false;
                var file = panel.querySelector('.ep-slip-input');
                var slipErr = panel.querySelector('.ep-slip-error');
                if (slipRequired && method === 'BankDeposit' && file && !(file.files && file.files.length)) {
                    setError(slipErr, 'Attach the bank deposit slip.');
                    ok = false;
                } else setError(slipErr, '');
            }
            if (!ok && !firstBad) firstBad = panel;
        });
        if (firstBad) {
            firstBad.scrollIntoView({ behavior: 'smooth', block: 'center' });
            return false;
        }
        rebuild();
        return true;
    };
})();

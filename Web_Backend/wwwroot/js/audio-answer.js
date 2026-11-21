// Voice recordings: student homework answers and staff Classroom "Audio" items. Any <button data-record-audio>
// inside a submit form records from the microphone; on stop the recording is
// placed into that form's <input type=file name=file>, so it submits exactly
// like a chosen file (HomeworkController.Submit, same type/size checks).
(function () {
    var MAX_SECONDS = 10 * 60;
    var active = null; // { btn, recorder, stream, timer, seconds }

    function pickMime() {
        var types = ['audio/webm;codecs=opus', 'audio/webm', 'audio/mp4', 'audio/ogg;codecs=opus'];
        if (!window.MediaRecorder) return null;
        for (var i = 0; i < types.length; i++) if (MediaRecorder.isTypeSupported(types[i])) return types[i];
        return '';
    }
    function extFor(mime) {
        if (mime.indexOf('mp4') >= 0) return '.m4a';
        if (mime.indexOf('ogg') >= 0) return '.ogg';
        return '.weba';
    }
    function fmt(s) { return Math.floor(s / 60) + ':' + String(s % 60).padStart(2, '0'); }
    function setLabel(form, text) {
        var l = form.querySelector('.file-label');
        if (l) l.textContent = text;
    }
    function setBtn(btn, recording, text) {
        btn.innerHTML = '<i data-lucide="' + (recording ? 'square' : 'mic') + '" class="w-3.5 h-3.5"></i> ' + text;
        btn.classList.toggle('is-recording', recording);
        btn.setAttribute('aria-pressed', recording ? 'true' : 'false');
        if (window.lucide) lucide.createIcons();
    }

    async function start(btn) {
        var form = btn.closest('form');
        var mime = pickMime();
        if (mime === null || !navigator.mediaDevices || !navigator.mediaDevices.getUserMedia) {
            setLabel(form, 'Recording isn’t supported in this browser — choose an audio file instead.');
            return;
        }
        var stream;
        try {
            stream = await navigator.mediaDevices.getUserMedia({ audio: true });
        } catch (e) {
            setLabel(form, 'Microphone blocked — allow it in your browser, or choose an audio file.');
            return;
        }
        var recorder = new MediaRecorder(stream, mime ? { mimeType: mime } : undefined);
        var chunks = [];
        recorder.ondataavailable = function (e) { if (e.data.size) chunks.push(e.data); };
        recorder.onstop = function () {
            var type = recorder.mimeType || mime || 'audio/webm';
            var blob = new Blob(chunks, { type: type });
            var seconds = recorder._seconds || 0;
            var file = new File([blob], (btn.dataset.fileName || 'voice-answer') + extFor(type), { type: type.split(';')[0] });
            var input = form.querySelector('input[type=file][name=file]');
            var dt = new DataTransfer();
            dt.items.add(file);
            input.files = dt.files;
            setLabel(form, '🎙 Recording (' + fmt(seconds) + ') — ready to submit');

            var preview = form.parentElement.querySelector('.voice-preview');
            if (!preview) {
                preview = document.createElement('audio');
                preview.controls = true;
                preview.className = 'voice-preview h-9 w-full mt-2 md:col-span-2';
                (btn.closest('.classroom-file') || form).insertAdjacentElement('afterend', preview);
            }
            if (preview.src) URL.revokeObjectURL(preview.src);
            preview.src = URL.createObjectURL(blob);
            setBtn(btn, false, 'Re-record');
        };
        recorder.start();
        active = { btn: btn, recorder: recorder, stream: stream, seconds: 0 };
        setBtn(btn, true, 'Stop 0:00');
        setLabel(form, 'Recording… speak now');
        active.timer = setInterval(function () {
            active.seconds++;
            setBtn(btn, true, 'Stop ' + fmt(active.seconds));
            if (active.seconds >= MAX_SECONDS) stop();
        }, 1000);
    }

    function stop() {
        if (!active) return;
        clearInterval(active.timer);
        active.stream.getTracks().forEach(function (t) { t.stop(); });
        active.recorder._seconds = active.seconds;
        active.recorder.stop();
        active = null;
    }

    document.addEventListener('click', function (e) {
        var btn = e.target.closest('[data-record-audio]');
        if (!btn) return;
        e.preventDefault();
        if (active && active.btn === btn) stop();
        else if (!active) start(btn);
    });

    // Choosing a file after recording replaces the recording.
    document.addEventListener('change', function (e) {
        if (e.target.matches('input[type=file][name=file]')) {
            var p = e.target.form && e.target.form.parentElement.querySelector('.voice-preview');
            var r = e.target.form && e.target.form.querySelector('.voice-preview');
            if (r) r.remove();
            if (p) p.remove();
        }
    });
})();

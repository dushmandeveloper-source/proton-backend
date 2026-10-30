// Shared display of exam question/option text (admin editor, student exam,
// admin + lecturer grading). Text is stored as "LaTeX": usually plain text,
// sometimes with \(...\) / $...$ math, or bare commands MathLive emits
// (\textbraceleft, \subseteq...). Load after katex.min.js; any element with
// class "katex-render" and a data-latex attribute is rendered on load.
(function () {
    // KaTeX draws spaces as non-breaking, and a whole \text{...} run as one
    // line — so a long question ran past the card. Turning its spaces back
    // into normal ones (plus the CSS below) lets it wrap like ordinary text.
    function makeBreakable(el) {
        const walker = document.createTreeWalker(el, NodeFilter.SHOW_TEXT);
        for (let n = walker.nextNode(); n; n = walker.nextNode()) {
            if (n.nodeValue.indexOf(' ') >= 0) n.nodeValue = n.nodeValue.replace(/ /g, ' ');
        }
    }

    function katexInto(latex, el) {
        // throwOnError must be true: with false KaTeX never throws — it paints
        // the raw source in red and the fallbacks never run.
        try { katex.render('\\text{' + latex + '}', el, { throwOnError: true }); return true; } catch { }
        try { katex.render(latex, el, { throwOnError: true }); return true; } catch { }
        return false;
    }

    function renderMixedLatex(latex, el) {
        el.classList.add('katex-wrap');
        latex = latex || '';
        // Plain text (the common case): no KaTeX at all — wraps naturally and
        // uses the page font.
        if (typeof katex === 'undefined' || !/[\\$]/.test(latex)) { el.textContent = latex; return; }

        // Text with delimited math: keep the text as text, render only the math.
        const parts = latex.split(/(\\\([\s\S]+?\\\)|\$[^$]+\$)/);
        if (parts.length > 1) {
            el.textContent = '';
            parts.forEach(p => {
                if (!p) return;
                const m = p.match(/^\\\(([\s\S]*)\\\)$/) || p.match(/^\$([\s\S]*)\$$/);
                if (!m) { el.appendChild(document.createTextNode(p)); return; }
                const span = document.createElement('span');
                try { katex.render(m[1], span, { throwOnError: true }); } catch { span.textContent = p; }
                el.appendChild(span);
            });
            makeBreakable(el);
            return;
        }

        if (katexInto(latex, el)) { makeBreakable(el); return; }
        el.textContent = latex.replace(/\\text\{([^{}]*)\}/g, '$1');
    }

    function renderAll(root) {
        (root || document).querySelectorAll('.katex-render').forEach(el => {
            if (el.dataset.rendered === '1') return;
            renderMixedLatex(el.dataset.latex || '', el);
            el.dataset.rendered = '1';
        });
    }

    const style = document.createElement('style');
    style.textContent =
        '.katex-wrap{display:block;min-width:0;max-width:100%;overflow-wrap:anywhere;word-break:normal}' +
        'span.katex-wrap{display:inline}' +
        '.katex-wrap .katex,.katex-wrap .katex-html{white-space:normal}' +
        '.katex-wrap .katex .base{display:inline;white-space:normal;width:auto}' +
        '.katex-wrap .katex{font-size:1.1em}';
    document.head.appendChild(style);

    window.renderMixedLatex = renderMixedLatex;
    window.renderExamMath = renderAll;
    if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', () => renderAll());
    else renderAll();
})();

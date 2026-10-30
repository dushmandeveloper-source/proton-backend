using System.Globalization;
using System.Text;
using System.Text.RegularExpressions;
using DocumentFormat.OpenXml;
using DocumentFormat.OpenXml.Packaging;
using W = DocumentFormat.OpenXml.Wordprocessing;

namespace Web_Backend.Classes
{
    // Reads exam questions out of a .docx (Admin → Exam → Import from Word).
    // Recognised layout (also what DownloadWordTemplate produces):
    //   第 1 题 / Question 1 / Q1 / 1.      starts a question (numbers must run in order)
    //   any lines                           question text (Chinese + English lines are kept as separate lines)
    //   (A) ... / A. ... / A) ...           options, in order A, B, C...; several may share one line
    //   Answer: B / 答案：B                  correct option (or an "Answer key" section at the end: "1. B  2. D ...")
    //   Marks: 2 / 分值：2                   optional
    //   Type: Written                       optional; a question with no options is Written
    //   Explanation: ... / 解析：...          ignored up to the next question
    // Pictures in a question become its image; Word equations become \(LaTeX\).
    // Nothing is saved here — the result goes to a review screen first.
    public static class WordQuestionImporter
    {
        public class ImportedOption
        {
            public string Text { get; set; } = "";
            public bool Correct { get; set; }
        }

        public class ImportedQuestion
        {
            public int Number { get; set; }
            public string Text { get; set; } = "";
            public string QuestionType { get; set; } = "MCQ";
            public decimal? Marks { get; set; }
            public List<ImportedOption> Options { get; set; } = new();
            public string? ImageDataUrl { get; set; }
            public List<string> Warnings { get; set; } = new();
        }

        public class ImportResult
        {
            public List<ImportedQuestion> Questions { get; set; } = new();
            public List<string> Warnings { get; set; } = new();
        }

        private const string WNs = "http://schemas.openxmlformats.org/wordprocessingml/2006/main";

        private static readonly Regex HeaderCn = new(@"^第\s*(\d{1,3})\s*[题題]\s*[:：.．、]?\s*(.*)$", RegexOptions.Compiled);
        private static readonly Regex HeaderEn = new(@"^(?:Question|Q)\s*\.?\s*(\d{1,3})\s*([:：.．)）、-])?\s*(.*)$", RegexOptions.Compiled | RegexOptions.IgnoreCase);
        private static readonly Regex HeaderNum = new(@"^(\d{1,3})\s*[.．、)）](?!\d)\s*(.*)$", RegexOptions.Compiled);
        private static readonly Regex HeaderEcho = new(@"^[（(]\s*(?:Question|Q)\s*\d{1,3}\s*[)）]\s*", RegexOptions.Compiled | RegexOptions.IgnoreCase);
        private static readonly Regex OptionStart = new(@"^(?:[（(]\s*([A-Ha-h])\s*[)）]|([A-Ha-h])\s*[.．、:：)）])\s*(.*)$", RegexOptions.Compiled);
        private static readonly Regex AnswerLine = new(@"^(?:correct\s+answer|answer|ans|key|正确答案|参考答案|答案)\s*[:：]?\s*[（(]?\s*([A-Ha-h])\s*[)）]?\s*[.。]?\s*$", RegexOptions.Compiled | RegexOptions.IgnoreCase);
        private static readonly Regex MarksLine = new(@"^(?:marks?|score|points?|分值|分数)\s*[:：]\s*(\d+(?:\.\d+)?)\s*(?:marks?|分)?\s*$", RegexOptions.Compiled | RegexOptions.IgnoreCase);
        private static readonly Regex TypeLine = new(@"^(?:type|题型)\s*[:：]\s*(\S+)", RegexOptions.Compiled | RegexOptions.IgnoreCase);
        private static readonly Regex ExplanationLine = new(@"^(?:explanation|solution|解析|解答|详解)\s*[:：]?", RegexOptions.Compiled | RegexOptions.IgnoreCase);
        private static readonly Regex AnswerKeyHeading = new(@"^(?:answer\s*key|answers|参考答案|答案)\s*[:：]?\s*(.*)$", RegexOptions.Compiled | RegexOptions.IgnoreCase);
        private static readonly Regex AnswerKeyPair = new(@"(\d{1,3})\s*[.．、:：)）-]?\s*[（(]?\s*([A-Ha-h])(?![A-Za-z])", RegexOptions.Compiled);

        // Placeholder the AI prompt (Exam/Edit.cshtml) asks for where a picture belongs.
        private static readonly Regex FigurePlaceholder = new(@"^\[\s*(?:figure|picture|image|diagram|insert[^\]]*|图|图片)\s*\]$", RegexOptions.Compiled | RegexOptions.IgnoreCase);

        private static readonly Regex TextAnswerLine = new(@"^(?:correct\s+answer|answer|ans|正确答案|参考答案|答案)\s*[:：]\s*(.+)$", RegexOptions.Compiled | RegexOptions.IgnoreCase);

        private enum State { Preamble, Question, Explanation, AnswerKey, AfterAnswer }


        public static ImportResult Parse(Stream docx)
        {
            var result = new ImportResult();
            using var doc = WordprocessingDocument.Open(docx, false);
            var main = doc.MainDocumentPart ?? throw new InvalidOperationException("The file has no document body.");
            var body = main.Document?.Body ?? throw new InvalidOperationException("The file has no document body.");
            var numbering = new NumberingLabels(main);

            ImportedQuestion? cur = null;
            var imageCount = 0;
            var state = State.Preamble;
            var answerKey = new Dictionary<int, char>();

            // Only top-level paragraphs: paragraphs inside text boxes/shapes
            // are also present in the fallback copy Word writes, and would be
            // read twice.
            foreach (var p in body.Descendants<W.Paragraph>().Where(p => !p.Ancestors<W.Paragraph>().Any()))
            {
                var images = new List<ExtractedImage>();
                var warnings = new List<string>();
                var text = new ParagraphReader(main, images, warnings).Read(p);
                var label = numbering.LabelFor(p);
                if (label != null) text = label + " " + text;

                // A paragraph may hold several lines (soft line breaks).
                var lines = text.Split('\n').Select(Clean).ToList();
                if (lines.All(l => l.Length == 0) && images.Count == 0 && warnings.Count == 0) continue;

                foreach (var line in lines)
                {
                    if (line.Length == 0) continue;

                    if (state == State.AnswerKey)
                    {
                        foreach (Match m in AnswerKeyPair.Matches(line))
                            answerKey[int.Parse(m.Groups[1].Value)] = char.ToUpperInvariant(m.Groups[2].Value[0]);
                        continue;
                    }

                    var header = MatchHeader(line, cur?.Number ?? 0);
                    if (header != null)
                    {
                        cur = new ImportedQuestion { Number = header.Value.number };
                        if (header.Value.number != result.Questions.Count + 1)
                            cur.Warnings.Add($"Numbered {header.Value.number} but it is question {result.Questions.Count + 1} in the file — check nothing was skipped.");
                        result.Questions.Add(cur);
                        imageCount = 0;
                        state = State.Question;
                        var rest = HeaderEcho.Replace(header.Value.rest, "").Trim();
                        if (rest.Length > 0) AddTextLine(cur, rest);
                        continue;
                    }

                    var keyHeading = AnswerKeyHeading.Match(line);
                    if (keyHeading.Success && !AnswerLine.IsMatch(line)
                        && (keyHeading.Groups[1].Value.Length == 0 || AnswerKeyPair.IsMatch(keyHeading.Groups[1].Value)))
                    {
                        state = State.AnswerKey;
                        foreach (Match m in AnswerKeyPair.Matches(keyHeading.Groups[1].Value))
                            answerKey[int.Parse(m.Groups[1].Value)] = char.ToUpperInvariant(m.Groups[2].Value[0]);
                        continue;
                    }

                    if (cur == null) continue; // title, instructions, name/date lines

                    // Anything after the answer (working, "80 = 1", links, headings) up
                    // to the next question is not part of the question — except Marks/Type.
                    var ans = AnswerLine.Match(line);
                    if (ans.Success && state == State.AfterAnswer)
                    {
                        // Never overwrite: a second answer means a question header was missed.
                        if (!cur.Warnings.Any(w => w.StartsWith("A second answer")))
                            cur.Warnings.Add("A second answer line was found below this question — a question may have been missed. Check the question numbering in the file.");
                        continue;
                    }
                    if (ans.Success)
                    {
                        SetAnswer(cur, char.ToUpperInvariant(ans.Groups[1].Value[0]));
                        state = State.AfterAnswer;
                        continue;
                    }
                    var textAns = TextAnswerLine.Match(line);
                    if (textAns.Success && state == State.Question)
                    {
                        cur.Warnings.Add(cur.Options.Count > 0
                            ? $"The answer \"{textAns.Groups[1].Value.Trim()}\" isn't an option letter — tick the correct option."
                            : $"Model answer \"{textAns.Groups[1].Value.Trim()}\" isn't stored (students type their own answer; the lecturer marks it).");
                        state = State.AfterAnswer;
                        continue;
                    }
                    var marks = MarksLine.Match(line);
                    if (marks.Success)
                    {
                        cur.Marks = decimal.Parse(marks.Groups[1].Value, CultureInfo.InvariantCulture);
                        continue;
                    }
                    var type = TypeLine.Match(line);
                    if (type.Success)
                    {
                        var t = type.Groups[1].Value.ToLowerInvariant();
                        if (t.StartsWith("written") || t.StartsWith("essay") || t.StartsWith("short") || t.Contains("简答") || t.Contains("问答"))
                            cur.QuestionType = "Written";
                        continue;
                    }
                    if (FigurePlaceholder.IsMatch(line))
                    {
                        if (images.Count == 0)
                            cur.Warnings.Add("Says [FIGURE] but no picture was pasted there — add the picture after importing, or in Word and import again.");
                        continue;
                    }
                    if (ExplanationLine.IsMatch(line)) { state = State.Explanation; continue; }
                    if (state is State.Explanation or State.AfterAnswer) continue;

                    if (TryAddOptions(cur, line)) continue;

                    if (cur.Options.Count > 0)
                        cur.Options[^1].Text = (cur.Options[^1].Text + " " + line).Trim();
                    else
                        AddTextLine(cur, line);
                }

                if (cur != null && state == State.Question)
                {
                    foreach (var w in warnings) cur.Warnings.Add(w);
                    foreach (var img in images)
                    {
                        imageCount++;
                        if (img.Warning != null) { cur.Warnings.Add(img.Warning); continue; }
                        if (cur.ImageDataUrl == null)
                        {
                            cur.ImageDataUrl = img.DataUrl;
                            if (cur.Options.Count > 0) cur.Warnings.Add("The picture sits among the options — it is shown under the question text.");
                        }
                        else if (imageCount == 2)
                            cur.Warnings.Add("Has more than one picture — only the first is used. Combine them into one picture in Word if all are needed.");
                    }
                }
                else if (cur == null && images.Count > 0)
                    result.Warnings.Add("A picture before the first question was ignored.");
            }

            foreach (var (num, letter) in answerKey)
            {
                var q = result.Questions.FirstOrDefault(x => x.Number == num);
                if (q == null) result.Warnings.Add($"The answer key has an answer for question {num}, which isn't in the file.");
                else if (!q.Options.Any(o => o.Correct)) SetAnswer(q, letter);
                else if (q.Options.FindIndex(o => o.Correct) != letter - 'A')
                    q.Warnings.Add($"The answer under the question and the answer key ({letter}) disagree — the one under the question is used.");
            }

            foreach (var q in result.Questions) Validate(q);
            if (result.Questions.Count == 0)
                result.Warnings.Add("No questions were found. Each question must start with a line like \"Question 1\" or \"第 1 题\" — download the template to see the layout.");
            return result;
        }

        private static (int number, string rest)? MatchHeader(string line, int lastNumber)
        {
            var m = HeaderCn.Match(line);
            if (m.Success) return (int.Parse(m.Groups[1].Value), m.Groups[2].Value);
            m = HeaderEn.Match(line);
            // "Question 12" / "Q12" — only as a header line on its own or as the
            // next number, so "Q1 and Q2 are charges..." inside a question doesn't split it.
            // Punctuation after the number ("Q.10:", "Question 3.") marks a header even
            // when the numbering jumps; the jump is flagged on the card.
            if (m.Success && (m.Groups[3].Value.Trim().Length == 0 || m.Groups[2].Success || int.Parse(m.Groups[1].Value) == lastNumber + 1))
                return (int.Parse(m.Groups[1].Value), m.Groups[3].Value);
            // Bare "12." only when it is the next number — otherwise "10. m/s" inside
            // a question would start a new one.
            m = HeaderNum.Match(line);
            if (m.Success && int.Parse(m.Groups[1].Value) == lastNumber + 1) return (lastNumber + 1, m.Groups[2].Value);
            return null;
        }

        private static void AddTextLine(ImportedQuestion q, string line) =>
            q.Text = q.Text.Length == 0 ? line : q.Text + "\n" + line;

        // Option lines must continue the sequence (A, then B...). Handles
        // several options on one line: "(A) 16 N (B) 144 N" / "A. 16 N  B. 144 N".
        private static bool TryAddOptions(ImportedQuestion q, string line)
        {
            var m = OptionStart.Match(line);
            if (!m.Success) return false;
            var letter = char.ToUpperInvariant((m.Groups[1].Success ? m.Groups[1].Value : m.Groups[2].Value)[0]);
            var expected = (char)('A' + q.Options.Count);
            if (letter != expected) return false;
            // "A. ..." with no paren is ambiguous with prose ("A ball is thrown") only
            // when no punctuation follows; the regex already requires it.

            var rest = m.Groups[3].Value;
            var parts = new List<string>();
            var next = (char)(letter + 1);
            while (true)
            {
                var split = FindNextOption(rest, next);
                if (split < 0) { parts.Add(rest); break; }
                parts.Add(rest[..split]);
                rest = OptionStart.Match(rest[split..]).Groups[3].Value;
                next++;
            }
            foreach (var part in parts) q.Options.Add(new ImportedOption { Text = part.Trim() });
            return true;
        }

        private static int FindNextOption(string s, char letter)
        {
            var m = Regex.Match(s, $@"[（(]\s*{letter}\s*[)）]|(?<=\s){letter}\s*[.．、:：)）]\s", RegexOptions.IgnoreCase);
            return m.Success && m.Index > 0 ? m.Index : -1;
        }

        private static void SetAnswer(ImportedQuestion q, char letter)
        {
            var i = letter - 'A';
            if (i < 0 || i >= q.Options.Count)
            {
                q.Warnings.Add($"Answer {letter} doesn't match any option.");
                return;
            }
            for (var k = 0; k < q.Options.Count; k++) q.Options[k].Correct = k == i;
        }

        private static void Validate(ImportedQuestion q)
        {
            if (q.Text.Trim().Length == 0) q.Warnings.Add("No question text.");
            if (q.Options.Count == 0 && q.QuestionType == "MCQ") q.QuestionType = "Written";
            if (q.QuestionType == "Written")
            {
                if (q.Options.Count > 0) q.Warnings.Add("Marked as Written, so its options will be dropped.");
                return;
            }
            if (q.Options.Count == 1) q.Warnings.Add("Only one option was found.");
            if (q.Options.Any(o => o.Text.Length == 0)) q.Warnings.Add("An option is empty.");
            if (!q.Options.Any(o => o.Correct)) q.Warnings.Add("No correct answer — tick one before importing.");
            if (q.Options.GroupBy(o => o.Text).Any(g => g.Count() > 1 && g.Key.Length > 0)) q.Warnings.Add("Two options have the same text.");
            if (q.Text.Contains('$')) q.Warnings.Add("Contains a $ sign — check the preview shows it correctly.");
        }

        private static string Clean(string s)
        {
            s = s.Replace(' ', ' ').Replace('\t', ' ');
            s = Regex.Replace(s, @"[ 　]{2,}", " ");
            return s.Trim(' ', '　', '​');
        }

        // ---------------------------------------------------------------
        // Paragraph → text, collecting pictures and turning equations into \(...\)
        // ---------------------------------------------------------------
        private class ExtractedImage
        {
            public string? DataUrl { get; set; }
            public string? Warning { get; set; }
        }

        private class ParagraphReader
        {
            private readonly MainDocumentPart main;
            private readonly List<ExtractedImage> images;
            private readonly List<string> warnings;
            private readonly StringBuilder sb = new();

            public ParagraphReader(MainDocumentPart main, List<ExtractedImage> images, List<string> warnings)
            {
                this.main = main; this.images = images; this.warnings = warnings;
            }

            public string Read(W.Paragraph p)
            {
                Walk(p);
                return sb.ToString();
            }

            private void Walk(OpenXmlElement el)
            {
                foreach (var child in el.ChildElements)
                {
                    switch (child.LocalName)
                    {
                        case "pPr": case "rPr": case "del": case "moveFrom": case "proofErr": case "bookmarkStart": case "bookmarkEnd":
                            break;
                        case "r" when child.NamespaceUri == WNs:
                            ReadRun(child);
                            break;
                        case "oMathPara":
                            foreach (var m in child.ChildElements.Where(c => c.LocalName == "oMath")) AppendMath(m);
                            break;
                        case "oMath":
                            AppendMath(child);
                            break;
                        case "AlternateContent":
                            var choice = child.ChildElements.FirstOrDefault(c => c.LocalName == "Choice") ?? child.ChildElements.FirstOrDefault();
                            if (choice != null) Walk(choice);
                            break;
                        default:
                            Walk(child); // hyperlink, ins, smartTag, sdt, fldSimple...
                            break;
                    }
                }
            }

            private void AppendMath(OpenXmlElement oMath)
            {
                var latex = OmmlToLatex.Convert(oMath).Trim();
                if (latex.Length > 0) sb.Append("\\(").Append(latex).Append("\\)");
            }

            private void ReadRun(OpenXmlElement run)
            {
                var rPr = run.GetFirstChild<W.RunProperties>();
                var vert = rPr?.VerticalTextAlignment?.Val?.Value;
                var symbolFont = IsSymbolFont(rPr);
                var buf = new StringBuilder();
                foreach (var c in run.ChildElements)
                {
                    switch (c)
                    {
                        case W.Text t: buf.Append(symbolFont ? SymbolFont.Map(t.Text) : t.Text); break;
                        case W.TabChar: buf.Append(' '); break;
                        case W.Break: case W.CarriageReturn: buf.Append('\n'); break;
                        case W.NoBreakHyphen: buf.Append('-'); break;
                        case W.SymbolChar sym: buf.Append(SymbolFont.FromSym(sym)); break;
                        case W.Drawing d: ReadDrawing(d); break;
                        case W.Picture pict: ReadVml(pict); break;
                        case W.EmbeddedObject:
                            warnings.Add("Contains an old-style equation/object (MathType or Equation 3.0) that can't be read — it was left out. Retype it with the Equation button after importing.");
                            buf.Append(" [equation] ");
                            break;
                        default:
                            if (c.LocalName == "AlternateContent")
                            {
                                var choice = c.ChildElements.FirstOrDefault(x => x.LocalName == "Choice") ?? c.ChildElements.FirstOrDefault();
                                choice?.Descendants<W.Drawing>().ToList().ForEach(ReadDrawing);
                            }
                            break;
                    }
                }
                var s = buf.ToString();
                if (s.Length == 0) return;
                if (vert == W.VerticalPositionValues.Superscript) s = Scripts.Super(s);
                else if (vert == W.VerticalPositionValues.Subscript) s = Scripts.Sub(s);
                sb.Append(s);
            }

            private static bool IsSymbolFont(W.RunProperties? rPr)
            {
                var f = rPr?.RunFonts;
                var name = f?.Ascii?.Value ?? f?.HighAnsi?.Value ?? "";
                return name.Equals("Symbol", StringComparison.OrdinalIgnoreCase);
            }

            private void ReadDrawing(W.Drawing d)
            {
                var blip = d.Descendants().FirstOrDefault(e => e.LocalName == "blip");
                var embed = blip?.GetAttributes().FirstOrDefault(a => a.LocalName == "embed").Value;
                if (string.IsNullOrEmpty(embed))
                {
                    // Shapes/canvas/chart drawn in Word rather than a picture
                    if (d.Descendants().Any(e => e.LocalName is "wsp" or "wgp" or "wpc" or "chart"))
                        images.Add(new ExtractedImage { Warning = "Has a diagram drawn with Word shapes (not a picture) — it can't be imported. Paste the diagram as a picture (e.g. a screenshot) and add it after importing." });
                    return;
                }
                AddImagePart(embed);
            }

            private void ReadVml(W.Picture pict)
            {
                var data = pict.Descendants().FirstOrDefault(e => e.LocalName == "imagedata");
                var id = data?.GetAttributes().FirstOrDefault(a => a.LocalName == "id").Value;
                if (!string.IsNullOrEmpty(id)) AddImagePart(id);
            }

            private void AddImagePart(string relId)
            {
                if (main.GetPartById(relId) is not ImagePart part) return;
                var ct = part.ContentType.ToLowerInvariant();
                if (ct.Contains("emf") || ct.Contains("wmf"))
                {
                    images.Add(new ExtractedImage { Warning = "Has a picture in Windows Metafile format (EMF/WMF), which browsers can't show. In Word, right-click it → Save as Picture → PNG, insert the PNG, and import again (or add it after importing)." });
                    return;
                }
                using var s = part.GetStream();
                using var ms = new MemoryStream();
                s.CopyTo(ms);
                if (ms.Length > 5 * 1024 * 1024)
                {
                    images.Add(new ExtractedImage { Warning = "Has a picture larger than 5 MB — compress it in Word (Picture Format → Compress) and import again." });
                    return;
                }
                if (ct == "image/x-png") ct = "image/png";
                images.Add(new ExtractedImage { DataUrl = $"data:{ct};base64,{Convert.ToBase64String(ms.ToArray())}" });
            }
        }

        // Word list numbering ("1." / "A." produced by Word, not typed) is not
        // in the paragraph text; rebuild the label so it can be recognised.
        private class NumberingLabels
        {
            private readonly NumberingDefinitionsPart? part;
            private readonly Dictionary<int, int[]> counters = new();

            public NumberingLabels(MainDocumentPart main) { part = main.NumberingDefinitionsPart; }

            public string? LabelFor(W.Paragraph p)
            {
                var numPr = p.ParagraphProperties?.NumberingProperties;
                var numId = numPr?.NumberingId?.Val?.Value;
                if (part?.Numbering == null || numId == null || numId == 0) return null;
                var ilvl = numPr?.NumberingLevelReference?.Val?.Value ?? 0;
                var num = part.Numbering.Elements<W.NumberingInstance>().FirstOrDefault(n => n.NumberID?.Value == numId);
                var absId = num?.AbstractNumId?.Val?.Value;
                var abs = part.Numbering.Elements<W.AbstractNum>().FirstOrDefault(a => a.AbstractNumberId?.Value == absId);
                var lvl = abs?.Elements<W.Level>().FirstOrDefault(l => l.LevelIndex?.Value == ilvl);
                if (lvl == null) return null;

                if (!counters.TryGetValue(numId.Value, out var c)) counters[numId.Value] = c = new int[9];
                var start = lvl.StartNumberingValue?.Val?.Value ?? 1;
                c[ilvl] = c[ilvl] == 0 ? start : c[ilvl] + 1;
                for (var i = ilvl + 1; i < 9; i++) c[i] = 0;

                var fmt = lvl.NumberingFormat?.Val?.Value;
                var text = lvl.LevelText?.Val?.Value ?? "%1.";
                string Format(int n) =>
                    fmt == W.NumberFormatValues.UpperLetter ? ((char)('A' + (n - 1) % 26)).ToString() :
                    fmt == W.NumberFormatValues.LowerLetter ? ((char)('a' + (n - 1) % 26)).ToString() :
                    fmt == W.NumberFormatValues.Bullet ? "" :
                    n.ToString(CultureInfo.InvariantCulture);
                if (fmt == W.NumberFormatValues.Bullet) return null;
                return Regex.Replace(text, @"%(\d)", m =>
                {
                    var lv = int.Parse(m.Groups[1].Value) - 1;
                    return lv == ilvl ? Format(c[ilvl]) : c[lv].ToString(CultureInfo.InvariantCulture);
                });
            }
        }

        private static class Scripts
        {
            private const string SupFrom = "0123456789+-−=()niax";
            private const string SupTo = "⁰¹²³⁴⁵⁶⁷⁸⁹⁺⁻⁻⁼⁽⁾ⁿⁱᵃˣ";
            private const string SubFrom = "0123456789+-−=()aeoxhklmnpst";
            private const string SubTo = "₀₁₂₃₄₅₆₇₈₉₊₋₋₌₍₎ₐₑₒₓₕₖₗₘₙₚₛₜ";

            public static string Super(string s) => Map(s, SupFrom, SupTo) ?? $"\\(^{{{OmmlToLatex.Escape(s)}}}\\)";
            public static string Sub(string s) => Map(s, SubFrom, SubTo) ?? $"\\(_{{{OmmlToLatex.Escape(s)}}}\\)";

            private static string? Map(string s, string from, string to)
            {
                var sb = new StringBuilder();
                foreach (var ch in s)
                {
                    var i = from.IndexOf(ch);
                    if (i < 0) return null;
                    sb.Append(to[i]);
                }
                return sb.ToString();
            }
        }

        // The "Symbol" font draws Greek letters/maths signs from ordinary codes.
        private static class SymbolFont
        {
            private static readonly Dictionary<int, string> Map0 = new()
            {
                ['a'] = "α", ['b'] = "β", ['c'] = "χ", ['d'] = "δ", ['e'] = "ε", ['f'] = "φ", ['g'] = "γ", ['h'] = "η", ['i'] = "ι", ['j'] = "ϕ",
                ['k'] = "κ", ['l'] = "λ", ['m'] = "μ", ['n'] = "ν", ['o'] = "ο", ['p'] = "π", ['q'] = "θ", ['r'] = "ρ", ['s'] = "σ", ['t'] = "τ",
                ['u'] = "υ", ['w'] = "ω", ['x'] = "ξ", ['y'] = "ψ", ['z'] = "ζ",
                ['D'] = "Δ", ['F'] = "Φ", ['G'] = "Γ", ['L'] = "Λ", ['P'] = "Π", ['Q'] = "Θ", ['S'] = "Σ", ['W'] = "Ω", ['Y'] = "Ψ", ['X'] = "Ξ",
                [0x22] = "∀", [0x24] = "∃", [0x27] = "∋", [0x2D] = "−", [0x5E] = "⊥", [0x7E] = "∼",
                [0xA3] = "≤", [0xA5] = "∞", [0xAB] = "↔", [0xAC] = "←", [0xAD] = "↑", [0xAE] = "→", [0xAF] = "↓",
                [0xB0] = "°", [0xB1] = "±", [0xB2] = "″", [0xB3] = "≥", [0xB4] = "×", [0xB5] = "∝", [0xB6] = "∂", [0xB7] = "•", [0xB8] = "÷",
                [0xB9] = "≠", [0xBA] = "≡", [0xBB] = "≈", [0xBC] = "…", [0xC6] = "∅", [0xC7] = "∩", [0xC8] = "∪", [0xCC] = "⊂", [0xCD] = "⊆",
                [0xCE] = "∈", [0xCF] = "∉", [0xD1] = "∇", [0xD6] = "√", [0xD7] = "·", [0xDB] = "⇔", [0xDE] = "⇒", [0xE5] = "∑", [0xF2] = "∫", [0xA2] = "′",
            };

            public static string Map(string s)
            {
                var sb = new StringBuilder();
                foreach (var ch in s) sb.Append(Map0.TryGetValue(ch & 0xFF, out var v) && (ch < 0x80 || ch >= 0xF000) ? v : ch.ToString());
                return sb.ToString();
            }

            public static string FromSym(W.SymbolChar sym)
            {
                var code = int.TryParse(sym.Char?.Value, NumberStyles.HexNumber, CultureInfo.InvariantCulture, out var c) ? c : 0;
                var font = sym.Font?.Value ?? "";
                if (font.Equals("Symbol", StringComparison.OrdinalIgnoreCase) && Map0.TryGetValue(code & 0xFF, out var v)) return v;
                if (font.StartsWith("Wingdings", StringComparison.OrdinalIgnoreCase)) return "";
                return code >= 0x20 && code < 0xF000 ? ((char)code).ToString() : "";
            }
        }
    }
}

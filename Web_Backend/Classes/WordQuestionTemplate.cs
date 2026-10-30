using DocumentFormat.OpenXml;
using DocumentFormat.OpenXml.Packaging;
using M = DocumentFormat.OpenXml.Math;
using W = DocumentFormat.OpenXml.Wordprocessing;

namespace Web_Backend.Classes
{
    // The downloadable "Word template" for Import from Word: instructions plus
    // sample questions in exactly the layout WordQuestionImporter reads.
    public static class WordQuestionTemplate
    {
        public static byte[] Build()
        {
            using var ms = new MemoryStream();
            using (var doc = WordprocessingDocument.Create(ms, WordprocessingDocumentType.Document))
            {
                var main = doc.AddMainDocumentPart();
                main.Document = new W.Document(new W.Body());
                var b = main.Document.Body!;

                b.Append(P("Proton exam questions — Word template", bold: true, size: 32));
                b.Append(P("Delete these instructions and the samples, then type or paste your questions in the same layout. Anything above the first question (title, name/date lines) is ignored.", size: 20, color: "64748B"));
                foreach (var rule in new[]
                {
                    "Start every question on its own line: “Question 1”, “Q1”, “1.” or “第 1 题”. Numbers must go 1, 2, 3…",
                    "Write the question on the lines below it (Chinese and English lines are both kept).",
                    "Options on their own lines: “(A) …”, “A. …” or “A) …” — or several on one line: “(A) 16 N  (B) 24 N”.",
                    "The correct answer on its own line: “Answer: B” (or “答案：B”). You can instead put an “Answer key” at the end: 1. B  2. D …",
                    "Optional lines: “Marks: 2” and “Type: Written” (a question with no options is Written).",
                    "Pictures: paste the diagram as a picture (Insert → Pictures, or paste a screenshot) inside the question. One picture per question.",
                    "Equations: use Insert → Equation in Word — they are converted automatically. Typed symbols (x², √, π, H₂O) also work. Old MathType/Equation 3.0 objects can't be read.",
                    "Lines starting “Explanation:” / “解析：” are skipped.",
                })
                    b.Append(P("•  " + rule, size: 20, color: "64748B"));
                b.Append(P(""));

                b.Append(P("第 1 题（Question 1）", bold: true));
                b.Append(P("下列哪个物理量是矢量？（ ）"));
                b.Append(P("（Which of the following physical quantities is a vector?）"));
                b.Append(P("(A) 质量（Mass）"));
                b.Append(P("(B) 时间（Time）"));
                b.Append(P("(C) 速度（Velocity）"));
                b.Append(P("(D) 温度（Temperature）"));
                b.Append(P("Answer: C"));
                b.Append(P("Marks: 2"));
                b.Append(P(""));

                b.Append(P("Question 2", bold: true));
                var q2 = new W.Paragraph(R("A 2 kg ball moves at 3 m/s. Its kinetic energy "));
                q2.Append(new M.OfficeMath(
                    new M.Subscript(new M.Base(MR("E")), new M.SubArgument(MR("k"))),
                    MR("="),
                    new M.Fraction(new M.Numerator(MR("1")), new M.Denominator(MR("2"))),
                    MR("m"),
                    new M.Superscript(new M.Base(MR("v")), new M.SuperArgument(MR("2")))));
                q2.Append(R(" is:"));
                b.Append(q2);
                b.Append(P("(A) 3 J   (B) 6 J   (C) 9 J   (D) 18 J"));
                b.Append(P("Answer: C"));
                b.Append(P("Explanation: ½ × 2 × 3² = 9 J (this line is ignored)", color: "64748B"));
                b.Append(P(""));

                b.Append(P("Question 3", bold: true));
                b.Append(P("Balance the equation and name the gas produced: Zn + HCl → ZnCl₂ + H₂"));
                b.Append(P("Type: Written"));
                b.Append(P("Marks: 4"));

                main.Document.Save();
            }
            return ms.ToArray();
        }

        private static W.Run R(string text, bool bold = false, int size = 22, string? color = null)
        {
            var props = new W.RunProperties(new W.RunFonts { Ascii = "Calibri", HighAnsi = "Calibri", EastAsia = "Microsoft YaHei" });
            if (bold) props.Append(new W.Bold());
            if (color != null) props.Append(new W.Color { Val = color });
            props.Append(new W.FontSize { Val = size.ToString() });
            return new W.Run(props, new W.Text(text) { Space = SpaceProcessingModeValues.Preserve });
        }

        private static W.Paragraph P(string text, bool bold = false, int size = 22, string? color = null) =>
            new(new W.ParagraphProperties(new W.SpacingBetweenLines { After = "60" }), R(text, bold, size, color));

        private static M.Run MR(string text) => new(new M.Text(text));
    }
}

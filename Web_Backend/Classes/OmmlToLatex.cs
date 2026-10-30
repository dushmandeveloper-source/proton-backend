using System.Text;
using DocumentFormat.OpenXml;

namespace Web_Backend.Classes
{
    // Word equation (Office Math / OMML, what Word's Insert → Equation makes)
    // → LaTeX for KaTeX. Works on element local names so it doesn't depend on
    // the SDK's typed math classes; unknown elements fall back to their content.
    public static class OmmlToLatex
    {
        public static string Convert(OpenXmlElement oMath) => Children(oMath).Trim();

        private static string Children(OpenXmlElement el)
        {
            var sb = new StringBuilder();
            foreach (var c in el.ChildElements) sb.Append(Node(c));
            return sb.ToString();
        }

        private static OpenXmlElement? Child(OpenXmlElement el, string name) =>
            el.ChildElements.FirstOrDefault(c => c.LocalName == name);

        private static string Arg(OpenXmlElement el, string name)
        {
            var c = Child(el, name);
            return c == null ? "" : Children(c).Trim();
        }

        private static string? Prop(OpenXmlElement el, string prName, string propName)
        {
            var pr = Child(el, prName);
            var p = pr == null ? null : Child(pr, propName);
            if (p == null) return null;
            var val = p.GetAttributes().FirstOrDefault(a => a.LocalName == "val").Value;
            return val ?? ""; // present without val = "on"
        }

        private static bool On(string? v) => v != null && v != "0" && v != "off" && v != "false";

        private static string G(string s) => "{" + s + "}";

        private static string Node(OpenXmlElement el)
        {
            switch (el.LocalName)
            {
                case "r": return Run(el);
                case "f":
                    {
                        var num = Arg(el, "num"); var den = Arg(el, "den");
                        var type = Prop(el, "fPr", "type");
                        if (type == "lin") return num + "/" + den;
                        if (type == "noBar") return @"\genfrac{}{}{0pt}{}" + G(num) + G(den);
                        return @"\frac" + G(num) + G(den);
                    }
                case "sSup": return G(Arg(el, "e")) + "^" + G(Arg(el, "sup"));
                case "sSub": return G(Arg(el, "e")) + "_" + G(Arg(el, "sub"));
                case "sSubSup": return G(Arg(el, "e")) + "_" + G(Arg(el, "sub")) + "^" + G(Arg(el, "sup"));
                case "sPre": return "{}_" + G(Arg(el, "sub")) + "^" + G(Arg(el, "sup")) + G(Arg(el, "e"));
                case "rad":
                    {
                        var deg = Arg(el, "deg");
                        var hide = On(Prop(el, "radPr", "degHide"));
                        return (hide || deg.Length == 0 ? @"\sqrt" : @"\sqrt[" + deg + "]") + G(Arg(el, "e"));
                    }
                case "d":
                    {
                        var beg = Prop(el, "dPr", "begChr") ?? "(";
                        var end = Prop(el, "dPr", "endChr") ?? ")";
                        var sep = Prop(el, "dPr", "sepChr") ?? "|";
                        var parts = el.ChildElements.Where(c => c.LocalName == "e").Select(c => Children(c).Trim());
                        return @"\left" + Delim(beg) + string.Join(" " + Delim(sep, true) + " ", parts) + @"\right" + Delim(end);
                    }
                case "nary":
                    {
                        var chr = Prop(el, "naryPr", "chr") ?? "∫";
                        var op = chr switch
                        {
                            "∑" => @"\sum", "∏" => @"\prod", "∐" => @"\coprod", "∫" => @"\int", "∬" => @"\iint", "∭" => @"\iiint",
                            "∮" => @"\oint", "⋃" => @"\bigcup", "⋂" => @"\bigcap", "⋁" => @"\bigvee", "⋀" => @"\bigwedge",
                            _ => Escape(chr)
                        };
                        var sub = On(Prop(el, "naryPr", "subHide")) ? "" : Arg(el, "sub");
                        var sup = On(Prop(el, "naryPr", "supHide")) ? "" : Arg(el, "sup");
                        return op + (sub.Length > 0 ? "_" + G(sub) : "") + (sup.Length > 0 ? "^" + G(sup) : "") + " " + G(Arg(el, "e"));
                    }
                case "func":
                    {
                        var name = Arg(el, "fName");
                        return name + " " + G(Arg(el, "e"));
                    }
                // "lim"/"max" bases are operators: no braces, so the limit goes underneath
                case "limLow": { var e = Arg(el, "e"); return (e.StartsWith('\\') ? e : G(e)) + "_" + G(Arg(el, "lim")); }
                case "limUpp": { var e = Arg(el, "e"); return (e.StartsWith('\\') ? e : G(e)) + "^" + G(Arg(el, "lim")); }
                case "acc":
                    {
                        var chr = Prop(el, "accPr", "chr") ?? "̂";
                        var cmd = chr switch
                        {
                            "⃗" or "→" or "⃑" => @"\vec",
                            "̃" or "~" => @"\tilde",
                            "̇" or "˙" => @"\dot",
                            "̈" or "¨" => @"\ddot",
                            "̅" or "‾" or "¯" => @"\overline",
                            "̄" => @"\bar",
                            "̆" => @"\breve",
                            "̌" => @"\check",
                            "⃖" or "←" => @"\overleftarrow",
                            "⃡" or "↔" => @"\overleftrightarrow",
                            _ => @"\hat"
                        };
                        return cmd + G(Arg(el, "e"));
                    }
                case "bar":
                    return (Prop(el, "barPr", "pos") == "top" ? @"\overline" : @"\underline") + G(Arg(el, "e"));
                case "groupChr":
                    {
                        var chr = Prop(el, "groupChrPr", "chr") ?? "⏟";
                        var top = Prop(el, "groupChrPr", "pos") == "top";
                        var e = Arg(el, "e");
                        return chr switch
                        {
                            "⏞" => @"\overbrace" + G(e),
                            "⏟" => @"\underbrace" + G(e),
                            "→" => top ? @"\xrightarrow" + G(e) : @"\underset" + G(e) + G(@"\rightarrow"),
                            "←" => top ? @"\xleftarrow" + G(e) : @"\underset" + G(e) + G(@"\leftarrow"),
                            "⇌" => @"\xrightleftharpoons" + G(e),
                            _ => top ? @"\overset" + G(Escape(chr)) + G(e) : @"\underset" + G(Escape(chr)) + G(e)
                        };
                    }
                case "borderBox": return @"\boxed" + G(Arg(el, "e"));
                case "box": return G(Arg(el, "e"));
                case "phant": return On(Prop(el, "phantPr", "show")) || Prop(el, "phantPr", "show") == null ? G(Arg(el, "e")) : "";
                case "m":
                    {
                        var rows = el.ChildElements.Where(c => c.LocalName == "mr")
                            .Select(r => string.Join(" & ", r.ChildElements.Where(c => c.LocalName == "e").Select(c => Children(c).Trim())));
                        return @"\begin{matrix}" + string.Join(@" \\ ", rows) + @"\end{matrix}";
                    }
                case "eqArr":
                    {
                        var rows = el.ChildElements.Where(c => c.LocalName == "e").Select(c => Children(c).Trim());
                        return @"\begin{aligned}" + string.Join(@" \\ ", rows) + @"\end{aligned}";
                    }
                case "oMath": return Children(el);
                // property/control elements carry no content
                case "rPr": case "ctrlPr": case "fPr": case "dPr": case "naryPr": case "radPr": case "accPr": case "barPr":
                case "groupChrPr": case "sSupPr": case "sSubPr": case "sSubSupPr": case "sPrePr": case "funcPr": case "limLowPr":
                case "limUppPr": case "mPr": case "eqArrPr": case "boxPr": case "borderBoxPr": case "phantPr": case "oMathParaPr":
                case "bookmarkStart": case "bookmarkEnd": case "proofErr":
                    return "";
                default:
                    return Children(el);
            }
        }

        private static readonly HashSet<string> Functions = new()
        {
            "sin", "cos", "tan", "cot", "sec", "csc", "arcsin", "arccos", "arctan", "sinh", "cosh", "tanh",
            "log", "ln", "lg", "exp", "lim", "max", "min", "sup", "inf", "det", "deg", "gcd", "arg", "dim", "ker", "Pr"
        };

        // A math run: its text, with \text for "normal text" runs and known
        // function names as operators.
        private static string Run(OpenXmlElement r)
        {
            var text = string.Concat(r.ChildElements.Where(c => c.LocalName == "t").Select(c => c.InnerText));
            if (text.Length == 0) return "";
            var normal = On(Prop(r, "rPr", "nor")) || Prop(r, "rPr", "sty") == "p";

            if (Functions.Contains(text.Trim())) return "\\" + text.Trim() + " ";
            if (normal && text.Any(char.IsLetter) && text.Trim().Length > 1)
                return @"\mathrm{" + Escape(text) + "}";

            var sb = new StringBuilder();
            foreach (var ch in text) sb.Append(Symbol(ch));
            return sb.ToString();
        }

        private static string Symbol(char ch) => ch switch
        {
            '{' => @"\{", '}' => @"\}", '%' => @"\%", '&' => @"\&", '#' => @"\#", '$' => @"\$", '_' => @"\_",
            '\\' => @"\backslash ", '^' => @"\wedge ", '~' => @"\sim ",
            '∞' => @"\infty ", '∂' => @"\partial ", '∇' => @"\nabla ", '·' => @"\cdot ", '⋅' => @"\cdot ", '×' => @"\times ", '÷' => @"\div ",
            '±' => @"\pm ", '∓' => @"\mp ", '≤' => @"\le ", '≥' => @"\ge ", '≠' => @"\ne ", '≈' => @"\approx ", '≡' => @"\equiv ",
            '∝' => @"\propto ", '→' => @"\rightarrow ", '←' => @"\leftarrow ", '↔' => @"\leftrightarrow ", '⇒' => @"\Rightarrow ",
            '⇔' => @"\Leftrightarrow ", '⇌' => @"\rightleftharpoons ", '∈' => @"\in ", '∉' => @"\notin ", '⊂' => @"\subset ",
            '⊆' => @"\subseteq ", '∪' => @"\cup ", '∩' => @"\cap ", '∅' => @"\emptyset ", '∀' => @"\forall ", '∃' => @"\exists ",
            '°' => @"^{\circ}", '′' => "'", '″' => "''", '…' => @"\ldots ", '⋯' => @"\cdots ", '∠' => @"\angle ", '⊥' => @"\perp ",
            '∥' => @"\parallel ", '△' => @"\triangle ", '−' => "-", '∗' => "*",
            'α' => @"\alpha ", 'β' => @"\beta ", 'γ' => @"\gamma ", 'δ' => @"\delta ", 'ε' => @"\varepsilon ", 'ϵ' => @"\epsilon ",
            'ζ' => @"\zeta ", 'η' => @"\eta ", 'θ' => @"\theta ", 'ϑ' => @"\vartheta ", 'ι' => @"\iota ", 'κ' => @"\kappa ",
            'λ' => @"\lambda ", 'μ' => @"\mu ", 'ν' => @"\nu ", 'ξ' => @"\xi ", 'π' => @"\pi ", 'ρ' => @"\rho ", 'σ' => @"\sigma ",
            'τ' => @"\tau ", 'υ' => @"\upsilon ", 'φ' => @"\varphi ", 'ϕ' => @"\phi ", 'χ' => @"\chi ", 'ψ' => @"\psi ", 'ω' => @"\omega ",
            'Γ' => @"\Gamma ", 'Δ' => @"\Delta ", 'Θ' => @"\Theta ", 'Λ' => @"\Lambda ", 'Ξ' => @"\Xi ", 'Π' => @"\Pi ",
            'Σ' => @"\Sigma ", 'Υ' => @"\Upsilon ", 'Φ' => @"\Phi ", 'Ψ' => @"\Psi ", 'Ω' => @"\Omega ",
            _ when ch >= 0x2E80 => @"\text{" + ch + "}", // CJK inside an equation
            _ => ch.ToString()
        };

        private static string Delim(string c, bool middle = false)
        {
            var d = c switch
            {
                "" => ".", "{" => @"\{", "}" => @"\}", "⟨" or "〈" => @"\langle ", "⟩" or "〉" => @"\rangle ",
                "‖" => @"\|", "⌊" => @"\lfloor ", "⌋" => @"\rfloor ", "⌈" => @"\lceil ", "⌉" => @"\rceil ",
                _ => c
            };
            if (middle) return d == "." ? "" : (d == "|" || d == @"\|" ? @"\mid " : d);
            return d;
        }

        // Plain text placed inside math (\(^{...}\) from superscript runs).
        public static string Escape(string s)
        {
            var sb = new StringBuilder();
            foreach (var ch in s) sb.Append(Symbol(ch));
            return sb.ToString();
        }
    }
}

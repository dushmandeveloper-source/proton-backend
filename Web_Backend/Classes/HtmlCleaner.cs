using Ganss.Xss;

namespace Web_Backend.Classes
{
    // Staff-written rich text (course "About", university admission/docs
    // sections) is rendered with Html.Raw on the admin/student portals and
    // dangerouslySetInnerHTML on the public site. Cleaned whenever the
    // model property is set -- form post or DB read -- so old rows are
    // safe too. Keeps normal formatting (incl. inline styles and classes
    // the editor emits); drops scripts, event handlers, iframes, forms and
    // non-http(s)/mailto links.
    public static class HtmlCleaner
    {
        private static readonly HtmlSanitizer RichSanitizer = CreateRich();

        private static HtmlSanitizer CreateRich()
        {
            var s = new HtmlSanitizer();
            s.AllowedAttributes.Add("class");
            s.AllowedSchemes.Clear();
            s.AllowedSchemes.Add("https");
            s.AllowedSchemes.Add("http");
            s.AllowedSchemes.Add("mailto");
            return s;
        }

        public static string Rich(string? html) =>
            string.IsNullOrEmpty(html) ? "" : RichSanitizer.Sanitize(html);
    }
}

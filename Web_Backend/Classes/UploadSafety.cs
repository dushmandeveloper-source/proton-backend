namespace Web_Backend.Classes
{
    // Uploaded files are served from the admin origin (/Uploads/...), so a
    // file a browser would execute (SVG, HTML, XML) would run with an admin's
    // cookies when opened. Such types are refused at upload, and every
    // /Uploads response is locked down in case an old one is still on disk.
    public static class UploadSafety
    {
        private static readonly string[] ActiveExtensions =
            { ".svg", ".svgz", ".html", ".htm", ".xhtml", ".xml", ".xsl", ".js", ".mjs" };

        public static bool IsActiveContent(string extension) =>
            ActiveExtensions.Contains(extension.ToLowerInvariant());

        public static void ApplyHeaders(HttpContext context)
        {
            var headers = context.Response.Headers;
            headers["X-Content-Type-Options"] = "nosniff";

            var ext = Path.GetExtension(context.Request.Path.Value ?? "");
            if (IsActiveContent(ext))
            {
                // Download instead of render, and no script even if rendered.
                headers["Content-Security-Policy"] = "sandbox; default-src 'none'";
                headers.ContentDisposition = "attachment";
            }
        }
    }
}

namespace Web_Backend.Classes
{
    // Where uploaded files live on disk. Public URLs never change: they're
    // always "/Uploads/<folder>/<file>" whatever folder is configured here.
    //
    // appsettings.json → ApplicationSettings:Uploads
    //   "Path":          folder for uploads. Empty = wwwroot/Uploads (default).
    //                    Set it to a folder OUTSIDE the deploy folder (e.g. on
    //                    SmarterASP: h:\root\home\<user>\uploads) so a backend
    //                    redeploy can never overwrite or delete uploads. On IIS
    //                    that folder can also be mapped as a virtual directory
    //                    /Uploads, so IIS serves images itself without waking
    //                    .NET — this class writes the folder's web.config for
    //                    that. Without a virtual directory the app serves it.
    //   "OriginalsPath": full-size originals kept by ImageOptimizer. Empty =
    //                    App_Data/originals. Never web-served; must not be
    //                    inside Path.
    public class UploadPaths
    {
        public string Root { get; }
        public string Originals { get; }
        public string DefaultRoot { get; }
        public string DefaultOriginals { get; }
        public bool IsCustom { get; }

        public UploadPaths(IWebHostEnvironment env, IConfiguration config, ILogger<UploadPaths> log)
        {
            DefaultRoot = Path.GetFullPath(Path.Combine(env.WebRootPath, "Uploads"));
            DefaultOriginals = Path.GetFullPath(Path.Combine(env.ContentRootPath, "App_Data", "originals"));

            var custom = config["ApplicationSettings:Uploads:Path"];
            var originals = config["ApplicationSettings:Uploads:OriginalsPath"];
            IsCustom = !string.IsNullOrWhiteSpace(custom);
            Root = IsCustom ? Path.GetFullPath(Resolve(env, custom!)) : DefaultRoot;
            Originals = string.IsNullOrWhiteSpace(originals) ? DefaultOriginals : Path.GetFullPath(Resolve(env, originals));

            if (IsInside(Originals, Root))
                throw new InvalidOperationException("ApplicationSettings:Uploads:OriginalsPath must not be inside Uploads:Path (originals would become public).");

            Directory.CreateDirectory(Root);
            if (IsCustom) WriteIisConfig(log);
        }

        // Relative paths are relative to the app's content root.
        private static string Resolve(IWebHostEnvironment env, string path) =>
            Path.IsPathRooted(path) ? path : Path.Combine(env.ContentRootPath, path);

        private static bool IsInside(string path, string root) =>
            (path.TrimEnd(Path.DirectorySeparatorChar) + Path.DirectorySeparatorChar)
                .StartsWith(root.TrimEnd(Path.DirectorySeparatorChar) + Path.DirectorySeparatorChar, StringComparison.OrdinalIgnoreCase);

        // web.config for when IIS serves this folder directly as virtual
        // directory /Uploads: static files only, no scripts, cached a year
        // (upload names are random GUIDs, never reused), nosniff.
        private void WriteIisConfig(ILogger log)
        {
            const string xml = """
                <?xml version="1.0" encoding="utf-8"?>
                <!-- Written by Web_Backend (Classes/UploadPaths.cs) for the /Uploads virtual directory. -->
                <configuration>
                  <system.webServer>
                    <handlers>
                      <clear />
                      <add name="StaticFile" path="*" verb="GET,HEAD" modules="StaticFileModule" resourceType="File" requireAccess="Read" />
                    </handlers>
                    <staticContent>
                      <clientCache cacheControlMode="UseMaxAge" cacheControlMaxAge="365.00:00:00" cacheControlCustom="public, immutable" />
                    </staticContent>
                    <httpProtocol>
                      <customHeaders>
                        <add name="X-Content-Type-Options" value="nosniff" />
                      </customHeaders>
                    </httpProtocol>
                  </system.webServer>
                </configuration>
                """;
            try
            {
                var file = Path.Combine(Root, "web.config");
                if (!File.Exists(file) || File.ReadAllText(file) != xml) File.WriteAllText(file, xml);
            }
            catch (Exception ex) { log.LogWarning(ex, "Could not write web.config into {Root}", Root); }
        }

        // Maps "/Uploads/a/b.jpg" to its file on disk, or null if it would escape Root.
        public string? PhysicalPathFor(string? webUrl)
        {
            if (string.IsNullOrWhiteSpace(webUrl) || !webUrl.StartsWith("/Uploads/", StringComparison.OrdinalIgnoreCase)) return null;
            var rel = webUrl["/Uploads/".Length..].Replace('/', Path.DirectorySeparatorChar);
            var full = Path.GetFullPath(Path.Combine(Root, rel));
            return IsInside(full, Root) ? full : null;
        }
    }
}

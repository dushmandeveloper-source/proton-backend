using Microsoft.AspNetCore.Mvc;

namespace Web_Backend.Controllers
{
    // The Android student app, offered on the Student portal (phones/tablets).
    //  * /app/proton-student.apk -- the current release. The file lives in
    //    {ContentRoot}/AppRelease (not wwwroot: static files don't serve .apk,
    //    and a backend publish never touches this folder). Public, because
    //    the app's own "Check for updates" opens it in a signed-out browser.
    //  * /student-app.webmanifest -- links the site to the app's package so
    //    Chrome's navigator.getInstalledRelatedApps() can tell the portal the
    //    app is already installed (the app declares the site back in its
    //    asset_statements).
    public class StudentAppDownloadController : Controller
    {
        public const string PackageId = "com.protonbusiness.proton_student";
        public const string ApkRoute = "/app/proton-student.apk";

        public static string ApkPath(IWebHostEnvironment env) =>
            Path.Combine(env.ContentRootPath, "AppRelease", "proton-student.apk");

        [HttpGet("app/proton-student.apk")]
        public IActionResult Apk([FromServices] IWebHostEnvironment env)
        {
            var path = ApkPath(env);
            if (!System.IO.File.Exists(path)) return NotFound();
            Response.Headers.CacheControl = "no-cache";
            return PhysicalFile(path, "application/vnd.android.package-archive", "Proton Student.apk", enableRangeProcessing: true);
        }

        [HttpGet("student-app.webmanifest")]
        public IActionResult Manifest()
        {
            Response.Headers.CacheControl = "public, max-age=86400";
            return new JsonResult(new
            {
                name = "Proton Student",
                short_name = "Proton",
                start_url = "/Student/Dashboard/Index",
                display = "browser",
                related_applications = new[] { new { platform = "play", id = PackageId } }
            })
            { ContentType = "application/manifest+json" };
        }
    }
}

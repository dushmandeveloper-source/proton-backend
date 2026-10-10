using System.Text.Json;
using System.Text.RegularExpressions;
using Ganss.Xss;
using Microsoft.AspNetCore.Mvc;
using Web_Backend.Areas.Admin.Data;
using Web_Backend.Areas.Admin.Models;
using Web_Backend.Classes;

namespace Web_Backend.Areas.Admin.Controllers
{
    // Admin → Website → Study Guides: blog-style posts for the public site's
    // /guides section, written per language in a rich-text editor.
    // Served by GET /api/guides(/{slug}); every save clears PublicApiCache.
    [Area("Admin")]
    public class GuidesController : Controller
    {
        private static readonly string[] ImageExtensions = { ".jpg", ".jpeg", ".png", ".webp", ".avif", ".gif" };
        private const long MaxImageBytes = 10 * 1024 * 1024;

        // Rich-text body: formatting, lists, links and images only — no
        // scripts, styles, iframes or event handlers can reach the public site.
        private static readonly HtmlSanitizer Sanitizer = CreateSanitizer();

        private static HtmlSanitizer CreateSanitizer()
        {
            var s = new HtmlSanitizer();
            s.AllowedTags.Clear();
            foreach (var t in new[] { "p", "br", "h2", "h3", "h4", "strong", "b", "em", "i", "u", "s", "blockquote", "ul", "ol", "li", "a", "img", "hr", "span" })
                s.AllowedTags.Add(t);
            s.AllowedAttributes.Clear();
            foreach (var a in new[] { "href", "src", "alt", "title", "target", "rel" })
                s.AllowedAttributes.Add(a);
            s.AllowedSchemes.Clear();
            s.AllowedSchemes.Add("https");
            s.AllowedSchemes.Add("http");
            s.AllowedSchemes.Add("mailto");
            s.AllowedCssProperties.Clear();
            return s;
        }

        private readonly IGuideData rep;
        private readonly IImageUploader uploader;

        public GuidesController(IGuideData rep, IImageUploader uploader)
        {
            this.rep = rep;
            this.uploader = uploader;
        }

        public async Task<IActionResult> Index()
        {
            Auth.CheckPermission(PermissionCode.SiteContent, 'V');
            ViewBag.CurrentUser = Auth.GetUser();
            ViewBag.PublicSiteUrl = PublicSiteUrl();
            return View(await rep.List());
        }

        public async Task<IActionResult> Edit(int id = 0)
        {
            Auth.CheckPermission(PermissionCode.SiteContent, id == 0 ? 'A' : 'E');
            ViewBag.CurrentUser = Auth.GetUser();
            ViewBag.PublicSiteUrl = PublicSiteUrl();
            if (id == 0) return View(new Guide { ContentJSON = "{\"en\":{}}" });
            var g = await rep.Get(id);
            if (g == null) return RedirectToAction("Index");
            return View(g);
        }

        [HttpPost, ValidateAntiForgeryToken]
        public async Task<IActionResult> Save(int guideId, string slug, string contentJson, string isActive, IFormFile? cover, bool removeCover = false)
        {
            Auth.CheckPermission(PermissionCode.SiteContent, guideId == 0 ? 'A' : 'E');

            Dictionary<string, GuideText> content;
            try { content = JsonSerializer.Deserialize<Dictionary<string, GuideText>>(contentJson ?? "{}", Guide.Json) ?? new(); }
            catch (JsonException) { return Fail("Could not read the guide text — please try again.", guideId); }

            // keep only known languages, trim, sanitise bodies, drop empty FAQ rows
            var clean = new Dictionary<string, GuideText>();
            foreach (var (code, _) in GuideLanguages.All)
            {
                if (!content.TryGetValue(code, out var t) || t == null) continue;
                t.Title = (t.Title ?? "").Trim();
                t.SeoTitle = (t.SeoTitle ?? "").Trim();
                t.Description = (t.Description ?? "").Trim();
                t.BodyHtml = Sanitizer.Sanitize(t.BodyHtml ?? "");
                if (Regex.IsMatch(t.BodyHtml, @"^\s*(<p>\s*(<br\s*/?>)?\s*</p>\s*)*$")) t.BodyHtml = "";
                t.Faq = (t.Faq ?? new()).Where(f => !string.IsNullOrWhiteSpace(f.Q) && !string.IsNullOrWhiteSpace(f.A))
                    .Select(f => new GuideFaq { Q = f.Q.Trim(), A = f.A.Trim() }).ToList();
                if (!t.IsEmpty) clean[code] = t;
            }

            if (!clean.TryGetValue("en", out var en) || string.IsNullOrWhiteSpace(en.Title))
                return Fail("The English title is required.", guideId);
            if (string.IsNullOrWhiteSpace(en.BodyHtml))
                return Fail("Please write the English article.", guideId);

            slug = Slugify(string.IsNullOrWhiteSpace(slug) ? en.Title : slug);
            if (slug.Length < 3) return Fail("Please give the guide a longer web address.", guideId);

            var existing = guideId == 0 ? null : await rep.Get(guideId);
            if (guideId != 0 && existing == null) return RedirectToAction("Index");
            var coverUrl = existing?.CoverImageURL ?? "";
            if (removeCover && !string.IsNullOrEmpty(coverUrl)) { uploader.Delete(coverUrl); coverUrl = ""; }
            if (cover != null && cover.Length > 0)
            {
                try
                {
                    var url = await uploader.SaveMediaAsync(cover, "Guides", ImageExtensions, MaxImageBytes);
                    if (url != null) { uploader.Delete(coverUrl); coverUrl = url; }
                }
                catch (InvalidOperationException ex) { return Fail(ex.Message, guideId); }
            }

            try
            {
                await rep.Save(new Guide
                {
                    GuideID = guideId,
                    Slug = slug,
                    CoverImageURL = coverUrl,
                    ContentJSON = JsonSerializer.Serialize(clean, Guide.Json),
                    IsActive = isActive == "I" ? "I" : "A",
                });
            }
            catch (Exception ex) when (ex.Message.Contains("already uses this web address"))
            {
                return Fail("Another guide already uses this web address — change it and save again.", guideId);
            }

            TempData["SuccessMessage"] = guideId == 0 ? "Guide published." : "Guide saved.";
            return RedirectToAction("Index");
        }

        [HttpPost, ValidateAntiForgeryToken]
        public async Task<IActionResult> Delete(int id)
        {
            Auth.CheckPermission(PermissionCode.SiteContent, 'D');
            var g = await rep.Get(id);
            if (g != null)
            {
                await rep.Delete(id);
                uploader.Delete(g.CoverImageURL);
                TempData["SuccessMessage"] = "Guide deleted.";
            }
            return RedirectToAction("Index");
        }

        [HttpPost, ValidateAntiForgeryToken]
        public async Task<IActionResult> Move(int id, int direction)
        {
            Auth.CheckPermission(PermissionCode.SiteContent, 'E');
            await rep.Move(id, direction < 0 ? -1 : 1);
            return RedirectToAction("Index");
        }

        [HttpPost, ValidateAntiForgeryToken]
        public async Task<IActionResult> Toggle(int id)
        {
            Auth.CheckPermission(PermissionCode.SiteContent, 'E');
            var g = await rep.Get(id);
            if (g != null)
            {
                g.IsActive = g.IsActive == "A" ? "I" : "A";
                await rep.Save(g);
                TempData["SuccessMessage"] = g.IsActive == "A" ? "Guide is now on the website." : "Guide hidden from the website.";
            }
            return RedirectToAction("Index");
        }

        // Image inserted from the editor toolbar. Returns an absolute URL so the
        // picture loads on the public site (a different host from this backend).
        [HttpPost, ValidateAntiForgeryToken]
        public async Task<IActionResult> UploadImage(IFormFile? image)
        {
            Auth.CheckPermission(PermissionCode.SiteContent, 'E');
            try
            {
                var url = await uploader.SaveMediaAsync(image, "Guides", ImageExtensions, MaxImageBytes);
                if (url == null) return BadRequest(new { message = "Please choose an image." });
                return Ok(new { url = $"{Request.Scheme}://{Request.Host}{url}" });
            }
            catch (InvalidOperationException ex) { return BadRequest(new { message = ex.Message }); }
        }

        private IActionResult Fail(string message, int guideId)
        {
            TempData["ErrorMessage"] = message;
            return guideId == 0 ? RedirectToAction("Edit") : RedirectToAction("Edit", new { id = guideId });
        }

        private static string Slugify(string s)
        {
            s = Regex.Replace((s ?? "").ToLowerInvariant(), @"[^a-z0-9]+", "-").Trim('-');
            return s.Length > 120 ? s[..120].Trim('-') : s;
        }

        private static string PublicSiteUrl()
        {
            var u = SettingHelper.Configuration["ApplicationSettings:PublicSiteUrl"];
            return (string.IsNullOrWhiteSpace(u) ? "http://localhost:5173" : u).TrimEnd('/');
        }
    }
}

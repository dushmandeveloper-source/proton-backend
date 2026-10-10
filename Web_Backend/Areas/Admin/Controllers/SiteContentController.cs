using Microsoft.AspNetCore.Mvc;
using Web_Backend.Areas.Admin.Data;
using Web_Backend.Areas.Admin.Models;
using Web_Backend.Classes;

namespace Web_Backend.Areas.Admin.Controllers
{
    // Admin → Site Content: everything on the public marketing site (frontend2)
    // that admins can change without a code deploy — hero banner slides and
    // text animation, the 3D wheel photos, the top announcement bar, fixed
    // home-page images, and the upload image optimizer.
    //
    // Public site reads it all through GET /api/site/content
    // (Controllers/Api/SiteApiController.cs). Every successful POST here clears
    // PublicApiCache, so changes appear on the site immediately.
    [Area("Admin")]
    public class SiteContentController : Controller
    {
        private static readonly string[] ImageExtensions = { ".jpg", ".jpeg", ".png", ".webp", ".avif", ".gif" };
        private const long MaxImageBytes = 10 * 1024 * 1024; // shrunk on save by ImageOptimizer anyway

        private readonly ISiteContentData rep;
        private readonly IImageUploader uploader;
        private readonly ImageOptimizer optimizer;

        public SiteContentController(ISiteContentData rep, IImageUploader uploader, ImageOptimizer optimizer)
        {
            this.rep = rep;
            this.uploader = uploader;
            this.optimizer = optimizer;
        }

        public async Task<IActionResult> Index(string tab = "hero")
        {
            Auth.CheckPermission(PermissionCode.SiteContent, 'V');
            ViewBag.CurrentUser = Auth.GetUser();
            ViewBag.Tab = tab;
            ViewBag.Settings = await rep.GetSettings();
            ViewBag.ImageStats = optimizer.Stats();
            // Built-in images (e.g. /images/hero/...) live on the public site, not
            // here, so previews of those are loaded from the public site's host.
            var siteUrl = SettingHelper.Configuration["ApplicationSettings:PublicSiteUrl"];
            ViewBag.PublicSiteUrl = (string.IsNullOrWhiteSpace(siteUrl) ? "http://localhost:5173" : siteUrl).TrimEnd('/');
            return View(await rep.ListBanners());
        }

        // ---------- Banner rows (hero slides, wheel photos, announcements) ----------

        [HttpPost, ValidateAntiForgeryToken]
        public async Task<IActionResult> SaveBanner(SiteBanner form, IFormFile? image)
        {
            var isNew = form.BannerID == 0;
            Auth.CheckPermission(PermissionCode.SiteContent, isNew ? 'A' : 'E');
            var tab = TabFor(form.Placement);

            if (!SiteContentCatalog.Placements.Contains(form.Placement))
                return Fail("Unknown placement.", tab);
            if (!IsSafeLink(form.LinkURL))
                return Fail("Link must start with / (a page on this site) or https://.", tab);
            if (form.StartsAt.HasValue && form.EndsAt.HasValue && form.EndsAt <= form.StartsAt)
                return Fail("End date must be after the start date.", tab);

            var existing = isNew ? null : await rep.GetBanner(form.BannerID);
            if (!isNew && existing == null) return Fail("That item no longer exists.", tab);
            form.ImageURL = existing?.ImageURL ?? "";

            if (image != null && image.Length > 0)
            {
                try
                {
                    var url = await uploader.SaveMediaAsync(image, "SiteContent", ImageExtensions, MaxImageBytes);
                    if (url != null)
                    {
                        if (existing != null) uploader.Delete(existing.ImageURL); // only ever deletes under /Uploads
                        form.ImageURL = url;
                    }
                }
                catch (InvalidOperationException ex) { return Fail(ex.Message, tab); }
            }

            if (form.Placement == SiteContentCatalog.Festival)
            {
                if (!SiteContentCatalog.IsValid(SiteContentCatalog.FestivalThemes, form.Title)) return Fail("Please choose a festival theme.", tab);
            }
            else if (form.Placement == SiteContentCatalog.Announcement)
            {
                if (string.IsNullOrWhiteSpace(form.Title)) return Fail("Announcement text is required.", tab);
            }
            else if (string.IsNullOrWhiteSpace(form.ImageURL))
            {
                return Fail("Please choose an image.", tab);
            }

            await rep.SaveBanner(form);
            TempData["SuccessMessage"] = isNew ? "Added." : "Saved.";
            return RedirectToAction("Index", new { tab });
        }

        [HttpPost, ValidateAntiForgeryToken]
        public async Task<IActionResult> DeleteBanner(int id)
        {
            Auth.CheckPermission(PermissionCode.SiteContent, 'D');
            var b = await rep.GetBanner(id);
            if (b == null) return RedirectToAction("Index");
            await rep.DeleteBanner(id);
            uploader.Delete(b.ImageURL);
            TempData["SuccessMessage"] = "Deleted.";
            return RedirectToAction("Index", new { tab = TabFor(b.Placement) });
        }

        [HttpPost, ValidateAntiForgeryToken]
        public async Task<IActionResult> MoveBanner(int id, int direction)
        {
            Auth.CheckPermission(PermissionCode.SiteContent, 'E');
            var b = await rep.GetBanner(id);
            if (b == null) return RedirectToAction("Index");
            await rep.MoveBanner(id, direction < 0 ? -1 : 1);
            return RedirectToAction("Index", new { tab = TabFor(b.Placement) });
        }

        [HttpPost, ValidateAntiForgeryToken]
        public async Task<IActionResult> ToggleBanner(int id)
        {
            Auth.CheckPermission(PermissionCode.SiteContent, 'E');
            var b = await rep.GetBanner(id);
            if (b == null) return RedirectToAction("Index");
            b.IsActive = b.IsActive == "A" ? "I" : "A";
            await rep.SaveBanner(b);
            TempData["SuccessMessage"] = b.IsActive == "A" ? "Shown on the site." : "Hidden from the site.";
            return RedirectToAction("Index", new { tab = TabFor(b.Placement) });
        }

        // ---------- Settings (animations, speeds, colours) ----------

        [HttpPost, ValidateAntiForgeryToken]
        public async Task<IActionResult> SaveHeroSettings(string heroTextAnimation, string heroTransition, int heroSlideSeconds, int heroTextRepeatSeconds)
        {
            Auth.CheckPermission(PermissionCode.SiteContent, 'E');
            if (!SiteContentCatalog.IsValid(SiteContentCatalog.HeroTextAnimations, heroTextAnimation)
                || !SiteContentCatalog.IsValid(SiteContentCatalog.HeroTransitions, heroTransition))
                return Fail("Please choose a valid option.", "hero");

            await rep.SetSetting("HeroTextAnimation", heroTextAnimation);
            await rep.SetSetting("HeroTransition", heroTransition);
            await rep.SetSetting("HeroSlideSeconds", Math.Clamp(heroSlideSeconds, 3, 20).ToString());
            await rep.SetSetting("HeroTextRepeatSeconds", Math.Clamp(heroTextRepeatSeconds, 0, 60).ToString());
            TempData["SuccessMessage"] = "Banner settings saved.";
            return RedirectToAction("Index", new { tab = "hero" });
        }

        [HttpPost, ValidateAntiForgeryToken]
        public async Task<IActionResult> SaveAnnouncementSettings(bool enabled, string animation, string speed, string bgColor, string textColor)
        {
            Auth.CheckPermission(PermissionCode.SiteContent, 'E');
            if (!SiteContentCatalog.IsValid(SiteContentCatalog.AnnouncementAnimations, animation)
                || !SiteContentCatalog.IsValid(SiteContentCatalog.Speeds, speed)
                || !IsHexColor(bgColor) || !IsHexColor(textColor))
                return Fail("Please choose valid options and colours.", "announcement");

            await rep.SetSetting("AnnouncementEnabled", enabled ? "1" : "0");
            await rep.SetSetting("AnnouncementAnimation", animation);
            await rep.SetSetting("AnnouncementSpeed", speed);
            await rep.SetSetting("AnnouncementBgColor", bgColor.ToUpperInvariant());
            await rep.SetSetting("AnnouncementTextColor", textColor.ToUpperInvariant());
            TempData["SuccessMessage"] = "Announcement bar settings saved.";
            return RedirectToAction("Index", new { tab = "announcement" });
        }

        [HttpPost, ValidateAntiForgeryToken]
        public async Task<IActionResult> SaveFestivalSettings(string density)
        {
            Auth.CheckPermission(PermissionCode.SiteContent, 'E');
            if (!SiteContentCatalog.IsValid(SiteContentCatalog.FestivalDensities, density)) return Fail("Please choose a valid option.", "festival");
            await rep.SetSetting("FestivalDensity", density);
            TempData["SuccessMessage"] = "Festival settings saved.";
            return RedirectToAction("Index", new { tab = "festival" });
        }

        // ---------- Fixed home-page images ----------

        [HttpPost, ValidateAntiForgeryToken]
        public async Task<IActionResult> SaveHomeImage(string slot, IFormFile? image)
        {
            Auth.CheckPermission(PermissionCode.SiteContent, 'E');
            if (!SiteContentCatalog.HomeImages.Any(s => s.Key == slot)) return Fail("Unknown image slot.", "images");
            if (image == null || image.Length == 0) return Fail("Please choose an image.", "images");

            string? url;
            try { url = await uploader.SaveMediaAsync(image, "SiteContent", ImageExtensions, MaxImageBytes); }
            catch (InvalidOperationException ex) { return Fail(ex.Message, "images"); }

            var key = SiteContentCatalog.HomeImagePrefix + slot;
            var settings = await rep.GetSettings();
            if (settings.TryGetValue(key, out var old)) uploader.Delete(old);
            await rep.SetSetting(key, url);
            TempData["SuccessMessage"] = "Image replaced.";
            return RedirectToAction("Index", new { tab = "images" });
        }

        [HttpPost, ValidateAntiForgeryToken]
        public async Task<IActionResult> ResetHomeImage(string slot)
        {
            Auth.CheckPermission(PermissionCode.SiteContent, 'E');
            var key = SiteContentCatalog.HomeImagePrefix + slot;
            var settings = await rep.GetSettings();
            if (settings.TryGetValue(key, out var old)) uploader.Delete(old);
            await rep.SetSetting(key, null);
            TempData["SuccessMessage"] = "Back to the original image.";
            return RedirectToAction("Index", new { tab = "images" });
        }

        // ---------- Upload image optimizer ----------

        [HttpPost, ValidateAntiForgeryToken]
        public async Task<IActionResult> OptimizeImages(CancellationToken ct)
        {
            Auth.CheckPermission(PermissionCode.SiteContent, 'E');
            var shrunk = await optimizer.OptimizeAll(ct, force: true);
            TempData[shrunk == null ? "ErrorMessage" : "SuccessMessage"] = shrunk == null
                ? "Images are already being shrunk — try again in a minute."
                : $"Done — {shrunk} image(s) shrunk.";
            return RedirectToAction("Index", new { tab = "speed" });
        }

        [HttpPost, ValidateAntiForgeryToken]
        public async Task<IActionResult> MoveUploads(CancellationToken ct)
        {
            Auth.CheckPermission(PermissionCode.SiteContent, 'E');
            var moved = await optimizer.MoveFromDefaultFolder(ct);
            TempData[moved == null ? "ErrorMessage" : "SuccessMessage"] = moved == null
                ? "Images are being processed — try again in a minute."
                : $"Moved {moved} file(s) to the uploads folder.";
            return RedirectToAction("Index", new { tab = "speed" });
        }

        // ---------- helpers ----------

        private IActionResult Fail(string message, string tab)
        {
            TempData["ErrorMessage"] = message;
            return RedirectToAction("Index", new { tab });
        }

        private static string TabFor(string placement) => placement switch
        {
            SiteContentCatalog.HeroWheel => "wheel",
            SiteContentCatalog.Announcement => "announcement",
            SiteContentCatalog.Festival => "festival",
            _ => "hero",
        };

        private static bool IsSafeLink(string? url) =>
            string.IsNullOrWhiteSpace(url)
            || (url.StartsWith('/') && !url.StartsWith("//"))
            || url.StartsWith("https://", StringComparison.OrdinalIgnoreCase)
            || url.StartsWith("http://", StringComparison.OrdinalIgnoreCase);

        private static bool IsHexColor(string? c) =>
            c != null && System.Text.RegularExpressions.Regex.IsMatch(c, "^#[0-9A-Fa-f]{6}$");
    }
}

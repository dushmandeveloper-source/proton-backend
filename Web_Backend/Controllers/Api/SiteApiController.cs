using Microsoft.AspNetCore.Mvc;
using Web_Backend.Areas.Admin.Data;
using Web_Backend.Areas.Admin.Models;

namespace Web_Backend.Controllers.Api
{
    // Everything the public site (frontend2) needs from Admin → Site Content in
    // one anonymous call. Cached in memory by PublicApiCache (/api/site prefix)
    // and cleared on any admin save, so this costs one DB round-trip per two
    // minutes at most.
    //
    // Image URLs are returned as stored: "/Uploads/..." (served by this
    // backend — the frontend prefixes its API base) or a site-relative
    // "/images/..." built-in file shipped with the frontend itself.
    [ApiController]
    [Route("api/site")]
    public class SiteApiController : ControllerBase
    {
        private readonly ISiteContentData rep;

        public SiteApiController(ISiteContentData rep)
        {
            this.rep = rep;
        }

        [HttpGet("content")]
        public async Task<IActionResult> Content()
        {
            var settings = await rep.GetSettings();
            var banners = await rep.ListBanners(publicOnly: true);
            string S(string key) => settings.TryGetValue(key, out var v) ? v : "";

            object Images(string placement) => banners
                .Where(b => b.Placement == placement && !string.IsNullOrEmpty(b.ImageURL))
                .Select(b => new { imageUrl = b.ImageURL, title = b.Title, link = b.LinkURL })
                .ToList();

            return Ok(new
            {
                hero = new
                {
                    textAnimation = S("HeroTextAnimation"),
                    transition = S("HeroTransition"),
                    slideSeconds = int.TryParse(S("HeroSlideSeconds"), out var secs) ? secs : 6,
                    textRepeatSeconds = int.TryParse(S("HeroTextRepeatSeconds"), out var repeatSecs) ? repeatSecs : 0,
                    reveal = S("HeroReveal"),
                    slides = Images(SiteContentCatalog.HeroSlide),
                },
                wheel = Images(SiteContentCatalog.HeroWheel),
                wheelSettings = new
                {
                    style = S("WheelStyle"),
                    shape = S("WheelShape"),
                    speed = S("WheelSpeed"),
                    direction = S("WheelDirection"),
                },
                announcement = new
                {
                    enabled = S("AnnouncementEnabled") == "1",
                    animation = S("AnnouncementAnimation"),
                    speed = S("AnnouncementSpeed"),
                    bgColor = S("AnnouncementBgColor"),
                    textColor = S("AnnouncementTextColor"),
                    items = banners
                        .Where(b => b.Placement == SiteContentCatalog.Announcement && !string.IsNullOrWhiteSpace(b.Title))
                        .Select(b => new { text = b.Title, textChinese = b.TitleChinese, link = b.LinkURL })
                        .ToList(),
                },
                // Most recently saved active, in-schedule festival effect (null = none running).
                festival = banners
                    .Where(b => b.Placement == SiteContentCatalog.Festival && !string.IsNullOrEmpty(b.Title))
                    .OrderByDescending(b => b.UpdatedDate)
                    .Select(b => new { theme = b.Title, density = double.TryParse(S("FestivalDensity"), System.Globalization.NumberStyles.Float, System.Globalization.CultureInfo.InvariantCulture, out var d) ? d : 1 })
                    .FirstOrDefault(),
                // Admin-edited wording (English); missing key = frontend default.
                texts = settings
                    .Where(kv => kv.Key.StartsWith(SiteContentCatalog.TextPrefix) && !string.IsNullOrEmpty(kv.Value))
                    .ToDictionary(kv => kv.Key[SiteContentCatalog.TextPrefix.Length..], kv => kv.Value),
                // Only slots an admin has replaced; the frontend keeps its own default otherwise.
                homeImages = settings
                    .Where(kv => kv.Key.StartsWith(SiteContentCatalog.HomeImagePrefix) && !string.IsNullOrEmpty(kv.Value))
                    .ToDictionary(kv => kv.Key[SiteContentCatalog.HomeImagePrefix.Length..], kv => kv.Value),
            });
        }
    }
}

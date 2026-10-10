namespace Web_Backend.Areas.Admin.Models
{
    // syst.SiteBanner (0098): one row per hero slide / wheel photo / announcement.
    public class SiteBanner
    {
        public int BannerID { get; set; }
        public string Placement { get; set; } = "";
        public string Title { get; set; } = "";
        public string TitleChinese { get; set; } = "";
        public string ImageURL { get; set; } = "";
        public string LinkURL { get; set; } = "";
        public int SortOrder { get; set; }
        public DateTime? StartsAt { get; set; }
        public DateTime? EndsAt { get; set; }
        public string IsActive { get; set; } = "A";
        public DateTime CreatedDate { get; set; }
        public DateTime UpdatedDate { get; set; }

        // Shown in admin lists: active but outside its schedule window.
        public bool IsScheduledOut =>
            (StartsAt.HasValue && StartsAt > DateTime.Now) || (EndsAt.HasValue && EndsAt <= DateTime.Now);
    }

    public class SiteSettingRow
    {
        public string SettingKey { get; set; } = "";
        public string SettingValue { get; set; } = "";
    }

    public record SiteOption(string Value, string Label, string Hint = "");

    // View model for Views/SiteContent/_BannerList.cshtml.
    public record SiteContentListModel(string Placement, string Heading, string Help, List<SiteBanner> Items,
                                       string SiteUrl, bool CanAdd, bool CanEdit, bool CanDelete);

    public record HomeImageSlot(string Key, string Label, string Section, string DefaultUrl);

    // Everything the admin can choose, plus code defaults (a missing
    // syst.SiteSetting row means "use the default" — no seed rows needed).
    // The public site (frontend2) implements each option Value by name, so
    // adding a value here also needs its CSS/JS on the frontend.
    public static class SiteContentCatalog
    {
        public const string HeroSlide = "HeroSlide";
        public const string HeroWheel = "HeroWheel";
        public const string Announcement = "Announcement";
        // Title holds the theme key (FestivalThemes) — runs while active and inside StartsAt/EndsAt.
        public const string Festival = "Festival";
        public static readonly string[] Placements = { HeroSlide, HeroWheel, Announcement, Festival };

        public const string HomeImagePrefix = "HomeImage:";

        public static readonly SiteOption[] HeroTextAnimations =
        {
            new("RiseTilt",   "3D Rise",        "Letters swing up out of a 3D tilt and blur, one by one"),
            new("Typewriter", "Typewriter",     "Typed out letter by letter with a blinking cursor"),
            new("BlurIn",     "Blur Focus",     "Words sharpen from a soft blur, word by word"),
            new("FadeUp",     "Fade Up",        "Each line fades and slides up in turn"),
            new("SlideIn",    "Slide In",       "Lines sweep in alternately from the left and right"),
            new("Flip",       "Flip",           "Letters flip over on their vertical axis"),
            new("Zoom",       "Zoom Pop",       "Words pop in from large to normal size"),
            new("Wave",       "Wave",           "Letters rise in, then ripple in a gentle continuous wave"),
            new("None",       "No animation",   "Heading is shown immediately"),
        };

        public static readonly SiteOption[] HeroTransitions =
        {
            new("KenBurns", "Ken Burns",  "Crossfade with a slow zoom on each photo"),
            new("Fade",     "Fade",       "Simple crossfade"),
            new("Slide",    "Slide",      "Photos slide in from the right"),
            new("Zoom",     "Zoom Out",   "Next photo zooms out into place"),
            new("Curtain",  "Curtain",    "Next photo is revealed left to right"),
        };

        public static readonly SiteOption[] AnnouncementAnimations =
        {
            new("Scroll",  "Scrolling ticker", "All messages scroll right to left in one line"),
            new("Fade",    "Fade rotate",      "Messages fade between each other"),
            new("SlideUp", "Slide-up rotate",  "Messages slide up one after another"),
            new("Pulse",   "Pulse",            "First message only, with a soft glow pulse"),
            new("Static",  "Static",           "First message only, no motion"),
        };

        // Keys must match frontend2/src/lib/festivalFx.js THEMES (and wwwroot/js/festival-fx.js).
        public static readonly SiteOption[] FestivalThemes =
        {
            new("Christmas",            "Christmas",                  "Falling snowflakes"),
            new("NewYear",              "New Year",                   "Fireworks bursting over the page"),
            new("ChineseNewYear",       "Chinese New Year",           "Red lanterns, red envelopes and sparkles"),
            new("SinhalaTamilNewYear",  "Sinhala & Tamil New Year",   "Falling flowers and leaves"),
            new("Vesak",                "Vesak",                      "Lanterns and lotus flowers rising"),
            new("Deepavali",            "Deepavali",                  "Oil lamps and sparkles rising"),
            new("MidAutumn",            "Mid-Autumn Festival",        "Lanterns, mooncakes and full moons"),
            new("Valentine",            "Valentine's Day",            "Floating hearts"),
            new("Eid",                  "Eid",                        "Crescent moons and stars"),
            new("SriLankaIndependence", "Sri Lanka Independence Day", "Confetti in the flag colours"),
            new("ChinaNationalDay",     "China National Day",         "Red and gold confetti"),
        };

        public static readonly SiteOption[] FestivalDensities =
        {
            new("0.6", "Light"), new("1", "Normal"), new("1.6", "Heavy"),
        };

        public static readonly SiteOption[] Speeds =
        {
            new("Slow", "Slow"), new("Normal", "Normal"), new("Fast", "Fast"),
        };

        // Key, default — for every non-image setting.
        public static readonly Dictionary<string, string> Defaults = new()
        {
            ["HeroTextAnimation"] = "RiseTilt",
            ["HeroTransition"] = "KenBurns",
            ["HeroSlideSeconds"] = "6",
            ["HeroTextRepeatSeconds"] = "0",
            ["AnnouncementEnabled"] = "1",
            ["AnnouncementAnimation"] = "Scroll",
            ["AnnouncementSpeed"] = "Normal",
            ["AnnouncementBgColor"] = "#0F172A",
            ["AnnouncementTextColor"] = "#FFFFFF",
            ["FestivalDensity"] = "1",
        };

        // Fixed images on the home page. DefaultUrl is the file shipped in
        // frontend2/public; an uploaded override is stored as HomeImage:<Key>.
        public static readonly HomeImageSlot[] HomeImages =
        {
            new("about-main",          "About section photo",          "About",              "/images/business.jpg"),
            new("service-education",   "Education card",               "Services",           "/images/education.jpg"),
            new("service-healthcare",  "Healthcare card",              "Services",           "/images/healthcare.jpg"),
            new("service-business",    "Business card",                "Services",           "/images/business.jpg"),
            new("service-industrial",  "Industrial card",              "Services",           "/images/industrial.jpg"),
            new("why-1",               "Why choose us — card 1",       "Why choose us",      "/images/why-licensed.jpg"),
            new("why-2",               "Why choose us — card 2",       "Why choose us",      "/images/why-network.jpg"),
            new("why-3",               "Why choose us — card 3",       "Why choose us",      "/images/why-onestop.jpg"),
            new("why-4",               "Why choose us — card 4",       "Why choose us",      "/images/why-partnership.jpg"),
            new("cta-bg",              "Call-to-action background",    "Call to action",     "/images/why-network-original.jpg"),
            new("footer-whatsapp-qr",  "WhatsApp QR code",             "Footer",             "/images/whatsapp-qr.jpeg"),
            new("footer-wechat-qr",    "WeChat QR code",               "Footer",             "/images/wechat-qr.png"),
        };

        public static bool IsValid(SiteOption[] options, string? value) => options.Any(o => o.Value == value);
    }
}

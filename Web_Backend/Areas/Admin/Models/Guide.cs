using System.Text.Json;
using System.Text.Json.Serialization;

namespace Web_Backend.Areas.Admin.Models
{
    // syst.Guide (0100): a study guide / blog post for the public site.
    public class Guide
    {
        public int GuideID { get; set; }
        public string Slug { get; set; } = "";
        public string CoverImageURL { get; set; } = "";
        public string Icon { get; set; } = "";   // lucide name, see GuideStyles
        public string Color { get; set; } = "";  // GuideStyles.Colors key
        public string ContentJSON { get; set; } = "{}";
        public int SortOrder { get; set; }
        public string IsActive { get; set; } = "A";
        public DateTime PublishedDate { get; set; }
        public DateTime UpdatedDate { get; set; }

        public static readonly JsonSerializerOptions Json = new()
        {
            PropertyNamingPolicy = JsonNamingPolicy.CamelCase,
            DefaultIgnoreCondition = JsonIgnoreCondition.WhenWritingNull,
        };

        // Language code ("en", "zh", "si", "ta") → that language's text.
        public Dictionary<string, GuideText> Content
        {
            get
            {
                try { return JsonSerializer.Deserialize<Dictionary<string, GuideText>>(ContentJSON, Json) ?? new(); }
                catch (JsonException) { return new(); }
            }
        }

        public GuideText En => Content.TryGetValue("en", out var t) ? t : new GuideText();
    }

    public class GuideText
    {
        public string Title { get; set; } = "";
        public string SeoTitle { get; set; } = "";
        public string Description { get; set; } = "";
        public string BodyHtml { get; set; } = "";
        public List<GuideFaq> Faq { get; set; } = new();

        public bool IsEmpty => string.IsNullOrWhiteSpace(Title) && string.IsNullOrWhiteSpace(BodyHtml);
    }

    public class GuideFaq
    {
        public string Q { get; set; } = "";
        public string A { get; set; } = "";
    }

    public static class GuideLanguages
    {
        public static readonly (string Code, string Label)[] All =
        {
            ("en", "English"), ("zh", "中文 Chinese"), ("si", "සිංහල Sinhala"), ("ta", "தமிழ் Tamil"),
        };
    }
}

namespace Web_Backend.Areas.Admin.Models
{
    // Card icon/colour choices for a guide without a cover photo. Keep in
    // sync with frontend2/src/components/GuidesPage.jsx (ICONS / COLORS).
    public static class GuideStyles
    {
        public static readonly (string Key, string Label)[] Icons =
        {
            ("graduation-cap", "Graduation cap"), ("book-open", "Book"), ("plane", "Plane"), ("award", "Award"),
            ("stethoscope", "Medicine"), ("languages", "Languages"), ("wallet", "Money"), ("briefcase", "Career"),
            ("building-2", "University"), ("globe", "Globe"), ("map-pin", "Location"), ("file-text", "Documents"),
            ("users", "People"), ("calendar", "Dates"), ("lightbulb", "Tips"), ("heart-pulse", "Health"),
            ("house", "Accommodation"), ("shield-check", "Visa & safety"),
        };
        public static readonly (string Key, string Label, string From, string To)[] Colors =
        {
            ("navy", "Navy", "#0f172a", "#1e3a5f"), ("blue", "Blue", "#1e3a5f", "#38c6f6"),
            ("purple", "Purple", "#0b1220", "#7c3aed"), ("teal", "Teal", "#131313", "#2bb9da"),
            ("green", "Green", "#1e293b", "#10b981"), ("amber", "Amber", "#0f172a", "#f59e0b"),
            ("rose", "Rose", "#1e1b2e", "#e11d48"), ("slate", "Slate", "#0f172a", "#64748b"),
        };
    }
}

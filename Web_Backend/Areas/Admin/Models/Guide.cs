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

namespace Web_Backend.Areas.Admin.Models
{
    // Dapper mapping target for edu.Course_Get: the 8 child collections come
    // back as raw JSON strings (FOR JSON PATH) rather than as List<T>, since
    // Dapper can't materialize nested collections from a single flat row.
    // CourseData.Get deserializes each into the real Course model below.
    public class CourseRaw : Course
    {
        public string? PricingJSON { get; set; }
        public string? DescriptionJSON { get; set; }
        public string? PathwayJSON { get; set; }
        public string? ComboOfferJSON { get; set; }
        public string? TrainingPointJSON { get; set; }
        public string? OutcomeJSON { get; set; }
        public string? RequirementJSON { get; set; }
        public string? FeeChargeJSON { get; set; }
    }
}

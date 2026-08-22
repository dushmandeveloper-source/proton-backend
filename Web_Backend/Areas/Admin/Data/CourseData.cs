using System.Text.Json;
using DBAccess;
using Web_Backend.Areas.Admin.Models;
using Web_Backend.Classes;

namespace Web_Backend.Areas.Admin.Data
{
    public class CourseData : ICourseData
    {
        private readonly IDBAccess db;

        // OPENJSON WITH paths on the SQL side are camelCase ($.pricingTier,
        // $.sortOrder, ...) so child lists must be serialized the same way,
        // matching the LMS_System reference's CamelCasePropertyNamesContractResolver.
        private static readonly JsonSerializerOptions CamelCase = new()
        {
            PropertyNamingPolicy = JsonNamingPolicy.CamelCase
        };

        public CourseData(IDBAccess db)
        {
            this.db = db;
        }

        // ---------- Course ----------
        public Task<List<Course>> GetList(CourseSearchView search) =>
            db.GetList<Course, object>("edu.Course_List", new
            {
                APIKey = AppData.GetAPIKey(),
                search.KeyW,
                search.CategoryID,
                search.CourseType,
                search.IsActive
            });

        public async Task<Course?> Get(string id)
        {
            var raw = await db.Get<CourseRaw, object>("edu.Course_Get", new { APIKey = AppData.GetAPIKey(), ID = id });
            if (raw == null) return null;

            raw.PricingDetails = Deserialize<CoursePricing>(raw.PricingJSON);
            raw.Descriptions = Deserialize<CourseDescription>(raw.DescriptionJSON);
            raw.Pathways = Deserialize<CoursePathway>(raw.PathwayJSON);
            raw.ComboOffers = Deserialize<CourseComboOfferDetail>(raw.ComboOfferJSON);
            raw.TrainingPoints = Deserialize<CourseTrainingPoint>(raw.TrainingPointJSON);
            raw.Outcomes = Deserialize<CourseOutcome>(raw.OutcomeJSON);
            raw.Requirements = Deserialize<CourseRequirement>(raw.RequirementJSON);
            raw.FeeCharges = Deserialize<CourseFeeCharge>(raw.FeeChargeJSON);
            return raw;
        }

        private static List<T> Deserialize<T>(string? json) =>
            string.IsNullOrWhiteSpace(json) ? new List<T>() : JsonSerializer.Deserialize<List<T>>(json) ?? new List<T>();

        public Task<string> AddEdit(Course c) =>
            db.Execute("edu.Course_AddEdit", new
            {
                APIKey = AppData.GetAPIKey(),
                c.CourseID,
                c.CourseCode,
                c.CourseTitle,
                c.CategoryID,
                c.CourseType,
                c.Duration,
                c.CertificateValidity,
                c.DeliveryMethod,
                c.LocationID,
                c.CourseImageURL,
                c.HandbookTitle,
                c.HandbookFileURL,
                c.EnableExperiencePricing,
                c.EnableComboOffer,
                c.ShortDescription,
                c.AboutHtml,
                c.CurrencyCode,
                c.Fee,
                c.SortOrder,
                c.IsActive,
                PricingJSON = JsonSerializer.Serialize(c.PricingDetails, CamelCase),
                DescriptionJSON = JsonSerializer.Serialize(c.Descriptions, CamelCase),
                PathwayJSON = JsonSerializer.Serialize(c.Pathways, CamelCase),
                ComboOfferJSON = JsonSerializer.Serialize(c.ComboOffers, CamelCase),
                TrainingPointJSON = JsonSerializer.Serialize(c.TrainingPoints, CamelCase),
                OutcomeJSON = JsonSerializer.Serialize(c.Outcomes, CamelCase),
                RequirementJSON = JsonSerializer.Serialize(c.Requirements, CamelCase),
                FeeChargeJSON = JsonSerializer.Serialize(c.FeeCharges, CamelCase)
            });

        public Task Delete(string id) =>
            db.ExecuteNonQuery("edu.Course_Delete", new { APIKey = AppData.GetAPIKey(), ID = id });

        // ---------- Subjects (CSCA only) ----------
        public Task<List<CourseSubject>> GetSubjects(string courseId) =>
            db.GetList<CourseSubject, object>("edu.CourseSubject_List",
                new { APIKey = AppData.GetAPIKey(), CourseID = courseId, IsActive = "A" });

        public Task<string> AddEditSubject(CourseSubject s) =>
            db.Execute("edu.CourseSubject_AddEdit", new
            {
                APIKey = AppData.GetAPIKey(),
                s.SubjectID,
                s.CourseID,
                s.SubjectName,
                s.Language,
                s.DurationMinutes,
                s.IsCompulsory,
                s.SortOrder,
                s.IsActive
            });

        public Task DeleteSubject(string id) =>
            db.ExecuteNonQuery("edu.CourseSubject_Delete", new { APIKey = AppData.GetAPIKey(), ID = id });

        // ---------- Locations ----------
        public Task<List<CourseLocation>> GetLocations() =>
            db.GetList<CourseLocation, object>("edu.CourseLocation_List", new { APIKey = AppData.GetAPIKey(), IsActive = "A" });

        public Task<string> AddEditLocation(CourseLocation l) =>
            db.Execute("edu.CourseLocation_AddEdit", new
            {
                APIKey = AppData.GetAPIKey(),
                l.LocationID,
                l.LocationName,
                l.IsActive
            });
    }
}

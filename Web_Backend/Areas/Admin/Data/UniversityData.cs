using DBAccess;
using Web_Backend.Areas.Admin.Models;
using Web_Backend.Classes;

namespace Web_Backend.Areas.Admin.Data
{
    public class UniversityData : IUniversityData
    {
        private readonly IDBAccess db;

        public UniversityData(IDBAccess db)
        {
            this.db = db;
        }

        // ---------- University ----------
        public Task<List<University>> GetList(UniversitySearchView search) =>
            db.GetList<University, object>("edu.University_List", new
            {
                APIKey = AppData.GetAPIKey(),
                search.KeyW,
                search.City,
                search.Province,
                search.IsFeatured,
                search.IsActive
            });

        public Task<University?> Get(string id) =>
            db.Get<University, object>("edu.University_Get", new { APIKey = AppData.GetAPIKey(), ID = id });

        public Task<string> AddEdit(University u) =>
            db.Execute("edu.University_AddEdit", new
            {
                APIKey = AppData.GetAPIKey(),
                u.UniversityID,
                u.Name,
                u.NameChinese,
                u.ShortName,
                u.City,
                u.Province,
                u.Country,
                u.Address,
                u.Latitude,
                u.Longitude,
                u.EstablishedYear,
                u.WebsiteURL,
                u.LogoURL,
                u.CoverImageURL,
                u.ShortDescription,
                u.AboutHtml,
                u.StudentCount,
                u.InternationalStudentCount,
                u.WorldRanking,
                u.NationalRanking,
                u.IsMOERecognized,
                u.Accreditation,
                u.CurrencyCode,
                u.TuitionMin,
                u.TuitionMax,
                u.AccommodationCostMin,
                u.AccommodationCostMax,
                u.LivingCostMin,
                u.LivingCostMax,
                u.AdmissionRequirementsHtml,
                u.RequiredDocumentsHtml,
                u.LanguageRequirement,
                u.IsFeatured,
                u.SortOrder,
                u.IsActive
            });

        public Task Delete(string id) =>
            db.ExecuteNonQuery("edu.University_Delete", new { APIKey = AppData.GetAPIKey(), ID = id });

        // ---------- Gallery ----------
        public Task<List<UniversityGalleryItem>> GetGallery(string universityId) =>
            db.GetList<UniversityGalleryItem, object>("edu.UniversityGallery_List",
                new { APIKey = AppData.GetAPIKey(), UniversityID = universityId, IsActive = "A" });

        public Task<string> AddEditGallery(UniversityGalleryItem g) =>
            db.Execute("edu.UniversityGallery_AddEdit", new
            {
                APIKey = AppData.GetAPIKey(),
                g.GalleryID,
                g.UniversityID,
                g.ImageURL,
                g.Caption,
                g.SortOrder,
                g.IsActive
            });

        public Task DeleteGallery(string id) =>
            db.ExecuteNonQuery("edu.UniversityGallery_Delete", new { APIKey = AppData.GetAPIKey(), ID = id });

        // ---------- Features ----------
        public Task<List<UniversityFeature>> GetFeatures(string universityId) =>
            db.GetList<UniversityFeature, object>("edu.UniversityFeature_List",
                new { APIKey = AppData.GetAPIKey(), UniversityID = universityId, IsActive = "A" });

        public Task<string> AddEditFeature(UniversityFeature f) =>
            db.Execute("edu.UniversityFeature_AddEdit", new
            {
                APIKey = AppData.GetAPIKey(),
                f.FeatureID,
                f.UniversityID,
                f.Title,
                f.Description,
                f.Icon,
                f.SortOrder,
                f.IsActive
            });

        public Task DeleteFeature(string id) =>
            db.ExecuteNonQuery("edu.UniversityFeature_Delete", new { APIKey = AppData.GetAPIKey(), ID = id });

        // ---------- Programs ----------
        public Task<List<UniversityProgram>> GetPrograms(string universityId) =>
            db.GetList<UniversityProgram, object>("edu.UniversityProgram_List",
                new { APIKey = AppData.GetAPIKey(), UniversityID = universityId, IsActive = "A" });

        public Task<string> AddEditProgram(UniversityProgram p) =>
            db.Execute("edu.UniversityProgram_AddEdit", new
            {
                APIKey = AppData.GetAPIKey(),
                p.ProgramID,
                p.UniversityID,
                p.ProgramLevel,
                p.ProgramName,
                p.DurationText,
                p.LanguageOfInstruction,
                p.TuitionPerYear,
                p.SortOrder,
                p.IsActive
            });

        public Task DeleteProgram(string id) =>
            db.ExecuteNonQuery("edu.UniversityProgram_Delete", new { APIKey = AppData.GetAPIKey(), ID = id });

        // ---------- Intakes ----------
        public Task<List<UniversityIntake>> GetIntakes(string universityId) =>
            db.GetList<UniversityIntake, object>("edu.UniversityIntake_List",
                new { APIKey = AppData.GetAPIKey(), UniversityID = universityId, IsActive = "A" });

        public Task<string> AddEditIntake(UniversityIntake i) =>
            db.Execute("edu.UniversityIntake_AddEdit", new
            {
                APIKey = AppData.GetAPIKey(),
                i.IntakeID,
                i.UniversityID,
                i.IntakeName,
                i.IntakeMonth,
                i.ApplicationDeadline,
                i.Notes,
                i.SortOrder,
                i.IsActive
            });

        public Task DeleteIntake(string id) =>
            db.ExecuteNonQuery("edu.UniversityIntake_Delete", new { APIKey = AppData.GetAPIKey(), ID = id });
    }
}

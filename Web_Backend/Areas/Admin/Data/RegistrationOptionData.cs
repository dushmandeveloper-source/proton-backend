using DBAccess;
using Web_Backend.Classes;

namespace Web_Backend.Areas.Admin.Data
{
    // mst.ProgrammeLevel / mst.CSCAPurpose (0106): admin-managed lookup lists
    // picked at student registration (Admin → Registration Options).
    public enum RegistrationOptionType { ProgrammeLevel, CSCAPurpose }

    public class RegistrationOption
    {
        public int ID { get; set; }
        public string Name { get; set; } = "";
        public int SortOrder { get; set; }
        public string IsActive { get; set; } = "A";
        public DateTime CreatedDate { get; set; }
        public int InUseCount { get; set; }
        // ProgrammeLevel only (0107): students picking this level must register
        // for at least one CSCA course (no skipping course registration).
        public bool RequiresCSCA { get; set; }
    }

    public interface IRegistrationOptionData
    {
        Task<List<RegistrationOption>> List(RegistrationOptionType type, bool activeOnly = false);
        Task<RegistrationOption?> Get(RegistrationOptionType type, int id);
        Task Save(RegistrationOptionType type, RegistrationOption o);

        // Server-side check for a submitted student form. Returns an error
        // message, or null when valid. A non-null ID must reference an ACTIVE
        // row -- or equal currentX, the value already stored on the student
        // being edited (still acceptable after the admin deactivates it).
        // requireX: the field must be filled -- but only while that list has at
        // least one active row, so registration never breaks before the admin
        // has set the list up.
        Task<string?> Validate(int? programmeLevelId, int? cscaPurposeId, bool requireProgrammeLevel, bool requireCscaPurpose,
            int? currentProgrammeLevelId = null, int? currentCscaPurposeId = null);

        // RequiresCSCA rule (0107). Returns an error message when the given level
        // is flagged "CSCA course mandatory" and hasCscaCourse is false, else null.
        // levelId may be inactive (stored value) -- the flag still applies.
        Task<string?> CheckRequiresCsca(int? programmeLevelId, bool hasCscaCourse);

        // Public enrolment path: store whichever values were supplied (NULL keeps).
        Task SetOnStudent(string studentId, int? programmeLevelId, int? cscaPurposeId);
    }

    public class RegistrationOptionData : IRegistrationOptionData
    {
        private readonly IDBAccess db;
        public RegistrationOptionData(IDBAccess db) { this.db = db; }

        private static string Proc(RegistrationOptionType type, string action) =>
            $"mst.{(type == RegistrationOptionType.ProgrammeLevel ? "ProgrammeLevel" : "CSCAPurpose")}_{action}";

        public Task<List<RegistrationOption>> List(RegistrationOptionType type, bool activeOnly = false) =>
            db.GetList<RegistrationOption, object>(Proc(type, "List"), new { APIKey = AppData.GetAPIKey(), ActiveOnly = activeOnly });

        public Task<RegistrationOption?> Get(RegistrationOptionType type, int id) =>
            db.Get<RegistrationOption, object>(Proc(type, "Get"), new { APIKey = AppData.GetAPIKey(), ID = id });

        public Task Save(RegistrationOptionType type, RegistrationOption o)
        {
            var sortOrder = o.ID == 0 && o.SortOrder <= 0 ? (int?)null : o.SortOrder;
            var isActive = o.IsActive == "I" ? "I" : "A";
            // CSCAPurpose_AddEdit has no @RequiresCSCA parameter.
            return type == RegistrationOptionType.ProgrammeLevel
                ? db.ExecuteNonQuery(Proc(type, "AddEdit"), new { APIKey = AppData.GetAPIKey(), o.ID, o.Name, SortOrder = sortOrder, IsActive = isActive, o.RequiresCSCA })
                : db.ExecuteNonQuery(Proc(type, "AddEdit"), new { APIKey = AppData.GetAPIKey(), o.ID, o.Name, SortOrder = sortOrder, IsActive = isActive });
        }

        public async Task<string?> CheckRequiresCsca(int? programmeLevelId, bool hasCscaCourse)
        {
            if (programmeLevelId == null || hasCscaCourse) return null;
            var level = await Get(RegistrationOptionType.ProgrammeLevel, programmeLevelId.Value);
            return level?.RequiresCSCA == true
                ? $"The “{level.Name}” programme requires the CSCA course — please select at least one CSCA course."
                : null;
        }

        public Task SetOnStudent(string studentId, int? programmeLevelId, int? cscaPurposeId) =>
            db.ExecuteNonQuery("mst.Student_SetRegistrationOptions", new
            {
                APIKey = AppData.GetAPIKey(),
                StudentID = studentId,
                ProgrammeLevelID = programmeLevelId,
                CSCAPurposeID = cscaPurposeId,
            });

        public async Task<string?> Validate(int? programmeLevelId, int? cscaPurposeId, bool requireProgrammeLevel, bool requireCscaPurpose,
            int? currentProgrammeLevelId = null, int? currentCscaPurposeId = null)
        {
            var levels = await List(RegistrationOptionType.ProgrammeLevel, activeOnly: true);
            if (programmeLevelId != null)
            {
                if (programmeLevelId != currentProgrammeLevelId && !levels.Any(l => l.ID == programmeLevelId))
                    return "Please select a valid programme level.";
            }
            else if (requireProgrammeLevel && levels.Count > 0)
                return "Please select your programme level.";

            var purposes = await List(RegistrationOptionType.CSCAPurpose, activeOnly: true);
            if (cscaPurposeId != null)
            {
                if (cscaPurposeId != currentCscaPurposeId && !purposes.Any(p => p.ID == cscaPurposeId))
                    return "Please select a valid CSCA purpose.";
            }
            else if (requireCscaPurpose && purposes.Count > 0)
                return "Please select your purpose for taking the CSCA.";

            return null;
        }
    }
}
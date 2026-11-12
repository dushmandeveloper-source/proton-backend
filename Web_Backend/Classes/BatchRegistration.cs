using DBAccess;
using Web_Backend.Areas.Admin.Models;

namespace Web_Backend.Classes
{
    // Batch registration deadline (migration 0126), one rule for every
    // registration path: public site, mobile app, student portal, admin, agent.
    //
    //  * Open    -- no RegistrationEndDate, or today (in the batch's zone) is on
    //               or before it.
    //  * Closed  -- after the date: still listed, marked "Registration closed",
    //               cannot be picked.
    //  * Hidden  -- closed for more than a month: left out of pickers so long
    //               batch lists stay short.
    // Existing registrations are never touched.
    public static class BatchRegistration
    {
        public const string ClosedMessage = "Registration for this batch is closed. Please choose another batch.";
        public const string AllClosedMessage = "Registration is closed for every batch of this course.";

        private static DateTime Today(CourseSchedule s) => ScheduleTime.Now(s.TimeZone).Date;

        public static bool IsClosed(CourseSchedule s) =>
            s.RegistrationEndDate.HasValue && Today(s) > s.RegistrationEndDate.Value.Date;

        public static bool IsHidden(CourseSchedule s) =>
            s.RegistrationEndDate.HasValue && Today(s) > s.RegistrationEndDate.Value.Date.AddMonths(1);

        // Batches to show in a registration picker (closed ones included, flagged).
        public static List<CourseSchedule> Visible(IEnumerable<CourseSchedule> batches) =>
            batches.Where(b => !b.HiddenFromRegistration).ToList();

        // Server-side check for a new registration. `active` = the course's
        // active batches. Returns an error message, or null when OK; clears
        // scheduleId when the course has no batches (existing behaviour).
        public static string? Check(IReadOnlyCollection<CourseSchedule> active, ref string? scheduleId)
        {
            if (active.Count == 0) { scheduleId = ""; return null; }
            if (active.All(b => b.RegistrationClosed)) return AllClosedMessage;
            var id = scheduleId;
            var chosen = active.FirstOrDefault(b => b.ScheduleID == id);
            if (chosen == null) return "Please choose a batch.";
            return chosen.RegistrationClosed ? ClosedMessage : null;
        }

        // Deadline-only check for callers that keep their own "batch required"
        // rule. `active` = the course's active batches.
        public static string? CheckChosen(IReadOnlyCollection<CourseSchedule> active, string? scheduleId)
        {
            if (active.Count > 0 && active.All(b => b.RegistrationClosed)) return AllClosedMessage;
            if (string.IsNullOrEmpty(scheduleId)) return null;
            var chosen = active.FirstOrDefault(b => b.ScheduleID == scheduleId);
            return chosen != null && chosen.RegistrationClosed ? ClosedMessage : null;
        }

        // ---- ScheduleID -> RegistrationEndDate, cached like ScheduleTime.Zones ----
        private static Dictionary<string, DateTime> _ends = new();
        private static DateTime _loadedUtc = DateTime.MinValue;
        private static readonly SemaphoreSlim _lock = new(1, 1);
        private class EndRow { public string ScheduleID { get; set; } = ""; public DateTime RegistrationEndDate { get; set; } }

        public static async Task<Dictionary<string, DateTime>> Ends(IDBAccess db)
        {
            if (DateTime.UtcNow - _loadedUtc < TimeSpan.FromMinutes(2)) return _ends;
            await _lock.WaitAsync();
            try
            {
                if (DateTime.UtcNow - _loadedUtc < TimeSpan.FromMinutes(2)) return _ends;
                var rows = await db.GetList<EndRow, object>("edu.CourseSchedule_RegistrationEndList", new { APIKey = AppData.GetAPIKey() });
                _ends = rows.GroupBy(r => r.ScheduleID).ToDictionary(g => g.Key, g => g.First().RegistrationEndDate);
                _loadedUtc = DateTime.UtcNow;
                return _ends;
            }
            finally { _lock.Release(); }
        }

        public static Task SetEnd(IDBAccess db, string scheduleId, DateTime? endDate)
        {
            _loadedUtc = DateTime.MinValue;
            return db.ExecuteNonQuery("edu.CourseSchedule_SetRegistrationEndDate", new
            {
                APIKey = AppData.GetAPIKey(), ScheduleID = scheduleId, RegistrationEndDate = endDate?.Date
            });
        }
    }
}

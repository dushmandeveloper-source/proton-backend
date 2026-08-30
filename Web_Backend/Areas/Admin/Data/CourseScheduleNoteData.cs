using DBAccess;
using Web_Backend.Areas.Admin.Models;
using Web_Backend.Classes;

namespace Web_Backend.Areas.Admin.Data
{
    public class CourseScheduleNoteData : ICourseScheduleNoteData
    {
        private readonly IDBAccess db;

        public CourseScheduleNoteData(IDBAccess db)
        {
            this.db = db;
        }

        public async Task<List<CourseScheduleNote>> GetByDateRange(DateTime from, DateTime to, string scheduleID = "")
        {
            var list = await db.GetList<CourseScheduleNote, object>("edu.CourseScheduleNote_ListByDateRange", new
            {
                APIKey = AppData.GetAPIKey(),
                FromDate = from,
                ToDate = to
            });
            return string.IsNullOrEmpty(scheduleID)
                ? list
                : list.Where(n => n.ScheduleID == scheduleID).ToList();
        }

        public Task<string> AddEdit(CourseScheduleNote note) =>
            db.Execute("edu.CourseScheduleNote_AddEdit", new
            {
                APIKey = AppData.GetAPIKey(),
                note.NoteID,
                note.NoteDate,
                note.ScheduleID,
                note.NoteText,
                note.IsActive
            });

        public Task Delete(string id) =>
            db.ExecuteNonQuery("edu.CourseScheduleNote_Delete", new { APIKey = AppData.GetAPIKey(), ID = id });
    }
}

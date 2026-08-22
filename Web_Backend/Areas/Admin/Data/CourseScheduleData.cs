using DBAccess;
using Web_Backend.Areas.Admin.Models;
using Web_Backend.Classes;

namespace Web_Backend.Areas.Admin.Data
{
    public class CourseScheduleData : ICourseScheduleData
    {
        private readonly IDBAccess db;

        public CourseScheduleData(IDBAccess db)
        {
            this.db = db;
        }

        public Task<List<CourseSchedule>> GetList(CourseScheduleSearchView search) =>
            db.GetList<CourseSchedule, object>("edu.CourseSchedule_List", new
            {
                APIKey = AppData.GetAPIKey(),
                search.CourseID,
                search.KeyW,
                search.FromDate,
                search.ToDate,
                search.IsActive
            });

        public Task<CourseSchedule?> Get(string id) =>
            db.Get<CourseSchedule, object>("edu.CourseSchedule_Get", new { APIKey = AppData.GetAPIKey(), ID = id });

        public Task<string> AddEdit(CourseSchedule s) =>
            db.Execute("edu.CourseSchedule_AddEdit", new
            {
                APIKey = AppData.GetAPIKey(),
                s.ScheduleID,
                s.CourseID,
                s.ScheduleName,
                s.ScheduleDate,
                s.StartTime,
                s.EndTime,
                s.Location,
                s.Capacity,
                s.TrainerName,
                s.Notes,
                s.IsActive
            });

        public Task Delete(string id) =>
            db.ExecuteNonQuery("edu.CourseSchedule_Delete", new { APIKey = AppData.GetAPIKey(), ID = id });
    }
}

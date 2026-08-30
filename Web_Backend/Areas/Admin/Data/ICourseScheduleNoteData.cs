using Web_Backend.Areas.Admin.Models;

namespace Web_Backend.Areas.Admin.Data
{
    public interface ICourseScheduleNoteData
    {
        Task<List<CourseScheduleNote>> GetByDateRange(DateTime from, DateTime to, string scheduleID = "");
        Task<string> AddEdit(CourseScheduleNote note);
        Task Delete(string id);
    }
}

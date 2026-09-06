using Web_Backend.Areas.Admin.Models;

namespace Web_Backend.Areas.Admin.Data
{
    public interface ICourseScheduleData
    {
        Task<List<CourseSchedule>> GetList(CourseScheduleSearchView search);
        Task<CourseSchedule?> Get(string id);
        Task<string> AddEdit(CourseSchedule schedule);
        Task<List<StudentScheduleSegment>> GetSegmentsForStudent(string studentId, DateTime fromDate, DateTime toDate);
        Task<List<CourseSchedule>> GetListForInstructor(string userId);
        Task<List<StudentScheduleSegment>> GetSegmentsForInstructor(string userId, DateTime fromDate, DateTime toDate);
        // Roster (name/email/DOB/profile photo) for a batch, scoped to a
        // lecturer's own assignment (edu.CourseSchedule_ListStudentRoster
        // throws if @UserID isn't actually assigned to @ScheduleID via
        // CourseScheduleInstructor).
        Task<List<StudentRosterEntry>> GetStudentRosterForInstructor(string scheduleId, string userId);
        Task Delete(string id);
    }
}

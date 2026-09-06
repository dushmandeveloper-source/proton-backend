using Web_Backend.Areas.Admin.Models;

namespace Web_Backend.Areas.Admin.Data
{
    public interface ICourseScheduleRescheduleData
    {
        Task<string> Create(CourseScheduleReschedule request);
        Task<List<CourseScheduleReschedule>> ListPending();
        Task<List<CourseScheduleReschedule>> ListForLecturer(string userId);
        Task<List<CourseScheduleReschedule>> ListForSchedule(string scheduleId);
        Task Approve(string rescheduleId, string approvedByUserId, string adminRemark);
        Task Reject(string rescheduleId, string approvedByUserId, string adminRemark);
    }
}

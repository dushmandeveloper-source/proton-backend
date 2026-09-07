using Web_Backend.Areas.Admin.Models;

namespace Web_Backend.Areas.Admin.Data
{
    public interface IExamScheduleRescheduleData
    {
        Task<string> Create(ExamScheduleReschedule request);
        Task<List<ExamScheduleReschedule>> ListPending();
        Task<List<ExamScheduleReschedule>> ListForLecturer(string userId);
        Task<List<ExamScheduleReschedule>> ListForSchedule(string scheduleId);
        Task Approve(string rescheduleId, string approvedByUserId, string adminRemark);
        Task Reject(string rescheduleId, string approvedByUserId, string adminRemark);
    }
}

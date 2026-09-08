using Web_Backend.Areas.Admin.Models;

namespace Web_Backend.Areas.Admin.Data
{
    public interface IExamScheduleData
    {
        Task<List<ExamSchedule>> GetList(ExamScheduleSearchView search);
        Task<ExamSchedule?> Get(string id);
        Task<string> AddEdit(ExamSchedule schedule);
        Task<List<ExamSchedule>> GetListForInstructor(string userId);
        Task<List<ExamScheduleInstructorSegment>> GetSegmentsForInstructor(string userId, DateTime fromDate, DateTime toDate);
        // Student-facing analogue: only returns exam sittings linked (via
        // edu.ExamSchedule.CourseScheduleID, 0029) to a course batch the
        // student is registered in (edu.ExamScheduleSegment_ListForStudent,
        // 0030). userId here is actually the student's mst.Student.StudentID
        // (matches ICourseScheduleData.GetSegmentsForStudent's convention).
        Task<List<ExamScheduleInstructorSegment>> GetSegmentsForStudent(string userId, DateTime fromDate, DateTime toDate);
        // Admin-only: sets one segment's meeting link directly.
        Task SetSegmentMeetingLink(string segmentId, string meetingLink);
        Task Deactivate(string id);
        Task DeletePermanently(string id);
    }
}

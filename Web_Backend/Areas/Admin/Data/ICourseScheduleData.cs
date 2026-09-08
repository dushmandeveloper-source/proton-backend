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
        // Lets an assigned lecturer set/change the meeting link on one or
        // more of their own batch's periods without the full Admin AddEdit.
        // Throws (via edu.CourseScheduleSegment_UpdateMeetingLinks) if
        // userId isn't actually assigned to scheduleId.
        Task UpdateSegmentMeetingLinks(string scheduleId, string userId, List<string> segmentIds, string meetingLink);
        // Admin-only: sets one segment's meeting link directly, without the
        // "must be an assigned instructor" check UpdateSegmentMeetingLinks
        // enforces — used from the Admin schedule calendar's day popup.
        Task SetSegmentMeetingLink(string segmentId, string meetingLink);
        Task Deactivate(string id);
        // Genuine permanent delete (edu.CourseSchedule_DeletePermanently) —
        // cascades its own pure child rows (segments/instructors/notes) but
        // refuses when real history (reschedule requests, or an ExamSchedule
        // still linked to this batch) hangs off it.
        Task DeletePermanently(string id);
    }
}

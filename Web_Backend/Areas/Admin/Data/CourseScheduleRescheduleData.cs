using DBAccess;
using Web_Backend.Areas.Admin.Models;
using Web_Backend.Classes;

namespace Web_Backend.Areas.Admin.Data
{
    public class CourseScheduleRescheduleData : ICourseScheduleRescheduleData
    {
        private readonly IDBAccess db;

        public CourseScheduleRescheduleData(IDBAccess db)
        {
            this.db = db;
        }

        public Task<string> Create(CourseScheduleReschedule r) =>
            db.Execute("edu.CourseScheduleReschedule_Create", new
            {
                APIKey = AppData.GetAPIKey(),
                r.ScheduleID,
                r.SegmentID,
                r.OriginalDate,
                r.ProposedNewDate,
                Remark = r.Remark ?? "",
                r.RequestedByUserID
            });

        public Task<List<CourseScheduleReschedule>> ListPending() =>
            db.GetList<CourseScheduleReschedule, object>("edu.CourseScheduleReschedule_ListPending", new { APIKey = AppData.GetAPIKey() });

        public Task<List<CourseScheduleReschedule>> ListForLecturer(string userId) =>
            db.GetList<CourseScheduleReschedule, object>("edu.CourseScheduleReschedule_ListForLecturer", new { APIKey = AppData.GetAPIKey(), UserID = userId });

        public Task<List<CourseScheduleReschedule>> ListForSchedule(string scheduleId) =>
            db.GetList<CourseScheduleReschedule, object>("edu.CourseScheduleReschedule_ListForSchedule", new { APIKey = AppData.GetAPIKey(), ScheduleID = scheduleId });

        public Task Approve(string rescheduleId, string approvedByUserId, string adminRemark) =>
            db.ExecuteNonQuery("edu.CourseScheduleReschedule_Approve", new
            {
                APIKey = AppData.GetAPIKey(),
                RescheduleID = rescheduleId,
                ApprovedByUserID = approvedByUserId,
                AdminRemark = adminRemark ?? ""
            });

        public Task Reject(string rescheduleId, string approvedByUserId, string adminRemark) =>
            db.ExecuteNonQuery("edu.CourseScheduleReschedule_Reject", new
            {
                APIKey = AppData.GetAPIKey(),
                RescheduleID = rescheduleId,
                ApprovedByUserID = approvedByUserId,
                AdminRemark = adminRemark ?? ""
            });
    }
}

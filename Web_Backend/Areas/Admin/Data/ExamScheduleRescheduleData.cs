using DBAccess;
using Web_Backend.Areas.Admin.Models;
using Web_Backend.Classes;

namespace Web_Backend.Areas.Admin.Data
{
    public class ExamScheduleRescheduleData : IExamScheduleRescheduleData
    {
        private readonly IDBAccess db;

        public ExamScheduleRescheduleData(IDBAccess db)
        {
            this.db = db;
        }

        public Task<string> Create(ExamScheduleReschedule r) =>
            db.Execute("edu.ExamScheduleReschedule_Create", new
            {
                APIKey = AppData.GetAPIKey(),
                r.ScheduleID,
                r.SegmentID,
                r.OriginalDate,
                r.ProposedNewDate,
                Remark = r.Remark ?? "",
                r.RequestedByUserID
            });

        public Task<List<ExamScheduleReschedule>> ListPending() =>
            db.GetList<ExamScheduleReschedule, object>("edu.ExamScheduleReschedule_ListPending", new { APIKey = AppData.GetAPIKey() });

        public Task<List<ExamScheduleReschedule>> ListForLecturer(string userId) =>
            db.GetList<ExamScheduleReschedule, object>("edu.ExamScheduleReschedule_ListForLecturer", new { APIKey = AppData.GetAPIKey(), UserID = userId });

        public Task<List<ExamScheduleReschedule>> ListForSchedule(string scheduleId) =>
            db.GetList<ExamScheduleReschedule, object>("edu.ExamScheduleReschedule_ListForSchedule", new { APIKey = AppData.GetAPIKey(), ScheduleID = scheduleId });

        public Task Approve(string rescheduleId, string approvedByUserId, string adminRemark) =>
            db.ExecuteNonQuery("edu.ExamScheduleReschedule_Approve", new
            {
                APIKey = AppData.GetAPIKey(),
                RescheduleID = rescheduleId,
                ApprovedByUserID = approvedByUserId,
                AdminRemark = adminRemark ?? ""
            });

        public Task Reject(string rescheduleId, string approvedByUserId, string adminRemark) =>
            db.ExecuteNonQuery("edu.ExamScheduleReschedule_Reject", new
            {
                APIKey = AppData.GetAPIKey(),
                RescheduleID = rescheduleId,
                ApprovedByUserID = approvedByUserId,
                AdminRemark = adminRemark ?? ""
            });
    }
}

using System.Threading.Tasks;
using System.Collections.Generic;
using DBAccess;
using Web_Backend.Areas.Admin.Models;
using Web_Backend.Classes;

namespace Web_Backend.Areas.Admin.Data
{
    public class ExamAttemptData : IExamAttemptData
    {
        private readonly IDBAccess db;

        public ExamAttemptData(IDBAccess db)
        {
            this.db = db;
        }

        public Task<string> Start(string examId, string studentId) =>
            db.Execute("edu.ExamAttempt_Start", new { APIKey = AppData.GetAPIKey(), ExamID = examId, StudentID = studentId });

        public Task<ExamAttempt?> Get(string attemptId) =>
            db.Get<ExamAttempt, object>("edu.ExamAttempt_Get", new { APIKey = AppData.GetAPIKey(), ID = attemptId });

        public Task SaveAnswer(string attemptId, string questionId, string? selectedOptionId, string? writtenAnswerText) =>
            db.ExecuteNonQuery("edu.ExamAttemptAnswer_Save", new
            {
                APIKey = AppData.GetAPIKey(),
                AttemptID = attemptId,
                QuestionID = questionId,
                SelectedOptionID = selectedOptionId,
                WrittenAnswerText = writtenAnswerText
            });

        public Task<List<ExamAttemptAnswer>> ListAnswers(string attemptId) =>
            db.GetList<ExamAttemptAnswer, object>("edu.ExamAttemptAnswer_List", new { APIKey = AppData.GetAPIKey(), AttemptID = attemptId });

        public Task Submit(string attemptId, bool isForced = false, bool terminate = false) =>
            db.ExecuteNonQuery("edu.ExamAttempt_Submit", new { APIKey = AppData.GetAPIKey(), AttemptID = attemptId, IsForced = isForced, Terminate = terminate });

        public Task<List<ExamAttempt>> ListPendingGrading() =>
            db.GetList<ExamAttempt, object>("edu.ExamAttempt_ListPendingGrading", new { APIKey = AppData.GetAPIKey() });

        public Task GradeWritten(string attemptId, string questionId, decimal marksAwarded) =>
            db.ExecuteNonQuery("edu.ExamAttemptAnswer_GradeWritten", new
            {
                APIKey = AppData.GetAPIKey(),
                AttemptID = attemptId,
                QuestionID = questionId,
                MarksAwarded = marksAwarded
            });

        public Task<int> CountByExamAndStudent(string examId, string studentId) =>
            db.GetCount<object>("edu.ExamAttempt_CountByExamAndStudent", new { APIKey = AppData.GetAPIKey(), ExamID = examId, StudentID = studentId });

        // edu.ExamAttemptViolation_Report declares @StrikeCount/@Status as OUT
        // params (see the migration), but IDBAccess has no generic helper for
        // reading back multiple named OUT params -- only Execute<T> (a single
        // @RetValue OUT) and Get<T,U> (a SELECT result set). So the proc was
        // extended to ALSO emit `SELECT @StrikeCount AS StrikeCount, @Status
        // AS Status` as its final statement, and this calls it the same way
        // Get() above calls edu.ExamAttempt_Get.
        public async Task<(int StrikeCount, string Status)> ReportViolation(string attemptId, string violationType)
        {
            var result = await db.Get<ViolationReportResult, object>("edu.ExamAttemptViolation_Report", new
            {
                APIKey = AppData.GetAPIKey(),
                AttemptID = attemptId,
                ViolationType = violationType
            });
            return (result?.StrikeCount ?? 0, result?.Status ?? "InProgress");
        }

        public Task<List<ExamAttemptViolation>> ListViolations(string attemptId) =>
            db.GetList<ExamAttemptViolation, object>("edu.ExamAttemptViolation_ListByAttempt", new { APIKey = AppData.GetAPIKey(), AttemptID = attemptId });

        private class ViolationReportResult
        {
            public int StrikeCount { get; set; }
            public string Status { get; set; } = "";
        }

        public Task<List<ExamAttempt>> ListTeacherReviewQueue() =>
            db.GetList<ExamAttempt, object>("edu.ExamAttempt_ListTeacherReviewQueue", new { APIKey = AppData.GetAPIKey() });

        public Task TeacherApprove(string attemptId, string reviewedByUserId) =>
            db.ExecuteNonQuery("edu.ExamAttempt_TeacherApprove", new
            {
                APIKey = AppData.GetAPIKey(),
                AttemptID = attemptId,
                ReviewedByUserID = reviewedByUserId
            });

        public Task TeacherReject(string attemptId, string reviewedByUserId, string remark) =>
            db.ExecuteNonQuery("edu.ExamAttempt_TeacherReject", new
            {
                APIKey = AppData.GetAPIKey(),
                AttemptID = attemptId,
                ReviewedByUserID = reviewedByUserId,
                Remark = remark
            });

        public Task<List<ExamAttempt>> ListAdminReviewQueue() =>
            db.GetList<ExamAttempt, object>("edu.ExamAttempt_ListAdminReviewQueue", new { APIKey = AppData.GetAPIKey() });

        public Task<ExamAttempt?> AdminApprove(string attemptId, string reviewedByUserId) =>
            db.Get<ExamAttempt, object>("edu.ExamAttempt_AdminApprove", new
            {
                APIKey = AppData.GetAPIKey(),
                AttemptID = attemptId,
                ReviewedByUserID = reviewedByUserId
            });

        public Task AdminReject(string attemptId, string reviewedByUserId, string remark) =>
            db.ExecuteNonQuery("edu.ExamAttempt_AdminReject", new
            {
                APIKey = AppData.GetAPIKey(),
                AttemptID = attemptId,
                ReviewedByUserID = reviewedByUserId,
                Remark = remark
            });

        public Task<List<ExamAttempt>> ListForStudent(string studentId) =>
            db.GetList<ExamAttempt, object>("edu.ExamAttempt_ListForStudent", new { APIKey = AppData.GetAPIKey(), StudentID = studentId });

        public Task<List<ExamAttempt>> ListAllForAdmin() =>
            db.GetList<ExamAttempt, object>("edu.ExamAttempt_ListAllForAdmin", new { APIKey = AppData.GetAPIKey() });

        public Task<List<ExamAttempt>> ListInProgressForInstructor(string userId) =>
            db.GetList<ExamAttempt, object>("edu.ExamAttempt_ListInProgressForInstructor", new { APIKey = AppData.GetAPIKey(), UserID = userId });
    }
}

using DBAccess;
using Web_Backend.Areas.Admin.Models;
using Web_Backend.Classes;

namespace Web_Backend.Areas.Admin.Data
{
    public class HomeworkSubmissionData : IHomeworkSubmissionData
    {
        private readonly IDBAccess db;

        public HomeworkSubmissionData(IDBAccess db)
        {
            this.db = db;
        }

        public Task<string> Upsert(string materialId, string studentId, string fileUrl) =>
            db.Execute("edu.HomeworkSubmission_Upsert", new
            {
                APIKey = AppData.GetAPIKey(),
                MaterialID = materialId,
                StudentID = studentId,
                FileURL = fileUrl
            });

        public Task<List<HomeworkSubmission>> ListForStudent(string studentId) =>
            db.GetList<HomeworkSubmission, object>("edu.HomeworkSubmission_ListForStudent", new { APIKey = AppData.GetAPIKey(), StudentID = studentId });

        public Task<List<HomeworkSubmission>> ListForMaterial(string materialId) =>
            db.GetList<HomeworkSubmission, object>("edu.HomeworkSubmission_ListForMaterial", new { APIKey = AppData.GetAPIKey(), MaterialID = materialId });

        public Task Grade(string submissionId, decimal? marksAwarded, string? feedback, string gradedByUserId) =>
            db.ExecuteNonQuery("edu.HomeworkSubmission_Grade", new
            {
                APIKey = AppData.GetAPIKey(),
                SubmissionID = submissionId,
                MarksAwarded = marksAwarded,
                Feedback = feedback ?? "",
                GradedByUserID = gradedByUserId
            });

        public Task RequestResubmission(string submissionId, string? remark) =>
            db.ExecuteNonQuery("edu.HomeworkSubmission_RequestResubmission", new
            {
                APIKey = AppData.GetAPIKey(),
                SubmissionID = submissionId,
                Remark = remark ?? ""
            });
    }
}

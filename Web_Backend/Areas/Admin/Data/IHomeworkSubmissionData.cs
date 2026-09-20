using Web_Backend.Areas.Admin.Models;

namespace Web_Backend.Areas.Admin.Data
{
    public interface IHomeworkSubmissionData
    {
        Task<string> Upsert(string materialId, string studentId, string fileUrl);
        Task<List<HomeworkSubmission>> ListForStudent(string studentId);
        Task<List<HomeworkSubmission>> ListForMaterial(string materialId);
        Task Grade(string submissionId, decimal? marksAwarded, string? feedback, string gradedByUserId);
        Task RequestResubmission(string submissionId, string? remark);
    }
}

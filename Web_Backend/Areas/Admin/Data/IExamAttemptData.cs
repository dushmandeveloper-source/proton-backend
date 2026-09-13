using System.Threading.Tasks;
using System.Collections.Generic;
using Web_Backend.Areas.Admin.Models;

namespace Web_Backend.Areas.Admin.Data
{
    public interface IExamAttemptData
    {
        Task<string> Start(string examId, string studentId);
        Task<ExamAttempt?> Get(string attemptId);
        Task SaveAnswer(string attemptId, string questionId, string? selectedOptionId, string? writtenAnswerText);
        Task<List<ExamAttemptAnswer>> ListAnswers(string attemptId);
        Task Submit(string attemptId, bool isForced = false);
        Task<List<ExamAttempt>> ListPendingGrading();
        Task GradeWritten(string attemptId, string questionId, decimal marksAwarded);
        Task<int> CountByExamAndStudent(string examId, string studentId);
    }
}

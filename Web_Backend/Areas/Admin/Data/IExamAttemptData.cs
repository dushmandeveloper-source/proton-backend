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
        Task Submit(string attemptId, bool isForced = false, bool terminate = false);
        Task<List<ExamAttempt>> ListPendingGrading();
        Task GradeWritten(string attemptId, string questionId, decimal marksAwarded);
        Task<int> CountByExamAndStudent(string examId, string studentId);

        // Phase 3: server-authoritative violation reporting. Returns the
        // running strike count (0-3) and the attempt's Status AFTER this
        // report is applied -- the caller (ExamAttemptController.ReportViolation)
        // never re-queries the attempt separately, it trusts these two values.
        Task<(int StrikeCount, string Status)> ReportViolation(string attemptId, string violationType);
        Task<List<ExamAttemptViolation>> ListViolations(string attemptId);
    }
}

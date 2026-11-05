using Web_Backend.Areas.Admin.Models;

namespace Web_Backend.Areas.Admin.Data
{
    public interface IExamData
    {
        Task<List<Exam>> GetList(ExamSearchView search);
        Task<Exam?> Get(string id);
        Task<string> AddEdit(Exam exam);
        Task Deactivate(string id);
        Task DeletePermanently(string id);
        Task SetAssignment(string examId, string scheduleId, DateTime openDate, DateTime dueDate, string createdByUserId, string? moduleId);
        Task SetAssignmentStudents(string examId, IEnumerable<string> studentIds);
        Task<List<ExamScheduleStudentRow>> ListAssignmentStudents(string examId);

        Task<List<ExamQuestion>> GetQuestions(string examId);
        Task<ExamQuestion?> GetQuestion(string id);
        Task<string> AddEditQuestion(ExamQuestion question);
        Task DeleteQuestion(string id);

        Task<List<ExamQuestionOption>> GetOptions(string questionId);
        Task<string> AddEditOption(ExamQuestionOption option);
        Task DeleteOption(string id);
    }
}

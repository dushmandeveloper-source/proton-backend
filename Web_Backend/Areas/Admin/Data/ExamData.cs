using DBAccess;
using Web_Backend.Areas.Admin.Models;
using Web_Backend.Classes;

namespace Web_Backend.Areas.Admin.Data
{
    public class ExamData : IExamData
    {
        private readonly IDBAccess db;

        public ExamData(IDBAccess db)
        {
            this.db = db;
        }

        // ---------- Exam ----------
        public Task<List<Exam>> GetList(ExamSearchView search) =>
            db.GetList<Exam, object>("edu.Exam_List", new
            {
                APIKey = AppData.GetAPIKey(),
                search.KeyW,
                search.CourseID,
                search.IsActive
            });

        public Task<Exam?> Get(string id) =>
            db.Get<Exam, object>("edu.Exam_Get", new { APIKey = AppData.GetAPIKey(), ID = id });

        public Task<string> AddEdit(Exam e) =>
            db.Execute("edu.Exam_AddEdit", new
            {
                APIKey = AppData.GetAPIKey(),
                e.ExamID,
                e.ExamTitle,
                CourseID = string.IsNullOrEmpty(e.CourseID) ? null : e.CourseID,
                SubjectID = string.IsNullOrEmpty(e.SubjectID) ? null : e.SubjectID,
                e.Description,
                e.DurationMinutes,
                e.MaxAttempts,
                e.PassingMarks,
                e.PassingPercentage,
                e.IsActive
            });

        public Task Deactivate(string id) =>
            db.ExecuteNonQuery("edu.Exam_Deactivate", new { APIKey = AppData.GetAPIKey(), ID = id });

        public Task DeletePermanently(string id) =>
            db.ExecuteNonQuery("edu.Exam_DeletePermanently", new { APIKey = AppData.GetAPIKey(), ID = id });

        // ---------- Questions ----------
        public Task<List<ExamQuestion>> GetQuestions(string examId) =>
            db.GetList<ExamQuestion, object>("edu.ExamQuestion_List",
                new { APIKey = AppData.GetAPIKey(), ExamID = examId, IsActive = "A" });

        public Task<ExamQuestion?> GetQuestion(string id) =>
            db.Get<ExamQuestion, object>("edu.ExamQuestion_Get", new { APIKey = AppData.GetAPIKey(), ID = id });

        public Task<string> AddEditQuestion(ExamQuestion q) =>
            db.Execute("edu.ExamQuestion_AddEdit", new
            {
                APIKey = AppData.GetAPIKey(),
                q.QuestionID,
                q.ExamID,
                q.QuestionType,
                q.QuestionTextLatex,
                q.ImageURL,
                q.AudioURL,
                q.VideoURL,
                q.Marks,
                q.SortOrder,
                q.IsActive
            });

        public Task DeleteQuestion(string id) =>
            db.ExecuteNonQuery("edu.ExamQuestion_Delete", new { APIKey = AppData.GetAPIKey(), ID = id });

        // ---------- Options (MCQ only) ----------
        public Task<List<ExamQuestionOption>> GetOptions(string questionId) =>
            db.GetList<ExamQuestionOption, object>("edu.ExamQuestionOption_List",
                new { APIKey = AppData.GetAPIKey(), QuestionID = questionId });

        public Task<string> AddEditOption(ExamQuestionOption o) =>
            db.Execute("edu.ExamQuestionOption_AddEdit", new
            {
                APIKey = AppData.GetAPIKey(),
                o.OptionID,
                o.QuestionID,
                o.OptionTextLatex,
                o.IsCorrect,
                o.SortOrder
            });

        public Task DeleteOption(string id) =>
            db.ExecuteNonQuery("edu.ExamQuestionOption_Delete", new { APIKey = AppData.GetAPIKey(), ID = id });
    }
}

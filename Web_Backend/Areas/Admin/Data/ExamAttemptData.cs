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

        public Task Submit(string attemptId, bool isForced = false) =>
            db.ExecuteNonQuery("edu.ExamAttempt_Submit", new { APIKey = AppData.GetAPIKey(), AttemptID = attemptId, IsForced = isForced });

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
    }
}

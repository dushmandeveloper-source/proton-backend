using Web_Backend.Areas.Admin.Data;
using Web_Backend.Areas.Admin.Models;

namespace Web_Backend.Classes
{
    // Options for every MCQ question of an attempt, keyed by QuestionID, so
    // the grading screens can show the chosen and correct answer text
    // (Views/Shared/_McqAnswerReview.cshtml) instead of a raw option id.
    // ExamAttemptAnswer_List doesn't return options, hence one call per MCQ
    // question -- the same approach Student/ExamAttempt/Take already uses.
    public static class ExamAnswerOptions
    {
        public static async Task<Dictionary<string, List<ExamQuestionOption>>> ForMcq(
            IEnumerable<ExamAttemptAnswer> answers, IExamData examRep)
        {
            var result = new Dictionary<string, List<ExamQuestionOption>>();
            foreach (var ans in answers.Where(a => a.IsMCQ))
                if (!result.ContainsKey(ans.QuestionID))
                    result[ans.QuestionID] = await examRep.GetOptions(ans.QuestionID);
            return result;
        }
    }
}

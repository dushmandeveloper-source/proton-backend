using Microsoft.AspNetCore.Mvc;
using System.Collections.Generic;
using System.Linq;
using System.Threading.Tasks;
using Web_Backend.Areas.Admin.Data;
using Web_Backend.Areas.Admin.Models;
using Web_Backend.Classes;

namespace Web_Backend.Areas.StudentPortal.Controllers
{
    [Area("Student")]
    public class ExamAttemptController : Controller
    {
        private readonly IStudentData studentRep;
        private readonly IExamAttemptData attemptRep;
        private readonly IExamData examRep;

        public ExamAttemptController(IStudentData studentRep, IExamAttemptData attemptRep, IExamData examRep)
        {
            this.studentRep = studentRep;
            this.attemptRep = attemptRep;
            this.examRep = examRep;
        }

        [HttpGet]
        public async Task<IActionResult> Start(string examId)
        {
            Auth.CheckUser();
            var userId = Auth.GetUserId();
            var student = await studentRep.GetByUserID(userId);
            if (student == null)
                return RedirectToAction("Index", "Dashboard", new { area = "Admin" });

            string attemptId;
            try
            {
                attemptId = await attemptRep.Start(examId, student.StudentID);
            }
            catch (System.Exception ex)
            {
                TempData["ErrorMessage"] = "Could not start exam: " + ex.Message;
                return RedirectToAction("Index", "Dashboard");
            }

            return RedirectToAction("Take", new { attemptId });
        }

        [HttpGet]
        public async Task<IActionResult> Take(string attemptId)
        {
            Auth.CheckUser();
            var userId = Auth.GetUserId();
            var student = await studentRep.GetByUserID(userId);
            if (student == null)
                return RedirectToAction("Index", "Dashboard", new { area = "Admin" });

            var attempt = await attemptRep.Get(attemptId);
            if (attempt == null || attempt.StudentID != student.StudentID)
                return RedirectToAction("Index", "Dashboard");

            if (!attempt.IsInProgress)
                return RedirectToAction("Result", new { attemptId });

            var answers = await attemptRep.ListAnswers(attemptId);

            // MCQ options aren't part of ExamAttemptAnswer_List's own result
            // (that proc returns question/answer state, not the option catalog)
            // -- fetched here, one call per MCQ question, so Take.cshtml can
            // render real selectable choices instead of a raw OptionID input.
            var optionsByQuestion = new Dictionary<string, List<ExamQuestionOption>>();
            foreach (var ans in answers.Where(a => a.IsMCQ))
                optionsByQuestion[ans.QuestionID] = await examRep.GetOptions(ans.QuestionID);

            ViewBag.CurrentUser = Auth.GetUser();
            ViewBag.Attempt = attempt;
            ViewBag.Answers = answers;
            ViewBag.OptionsByQuestion = optionsByQuestion;
            return View();
        }

        [HttpPost]
        [ValidateAntiForgeryToken]
        public async Task<IActionResult> SaveAnswer(string attemptId, string questionId, string? selectedOptionId, string? writtenAnswerText)
        {
            Auth.CheckUser();
            var userId = Auth.GetUserId();
            var student = await studentRep.GetByUserID(userId);
            if (student == null)
                return Json(new { success = false, message = "Not authenticated" });

            var attempt = await attemptRep.Get(attemptId);
            if (attempt == null || attempt.StudentID != student.StudentID)
                return Json(new { success = false, message = "Attempt not found" });

            try
            {
                await attemptRep.SaveAnswer(attemptId, questionId, selectedOptionId, writtenAnswerText);
                return Json(new { success = true });
            }
            catch (System.Exception ex)
            {
                return Json(new { success = false, message = ex.Message });
            }
        }

        [HttpPost]
        [ValidateAntiForgeryToken]
        public async Task<IActionResult> Submit(string attemptId)
        {
            Auth.CheckUser();
            var userId = Auth.GetUserId();
            var student = await studentRep.GetByUserID(userId);
            if (student == null)
                return RedirectToAction("Index", "Dashboard", new { area = "Admin" });

            var attempt = await attemptRep.Get(attemptId);
            if (attempt == null || attempt.StudentID != student.StudentID)
                return RedirectToAction("Index", "Dashboard");

            try
            {
                await attemptRep.Submit(attemptId);
            }
            catch (System.Exception ex)
            {
                TempData["ErrorMessage"] = "Could not submit: " + ex.Message;
            }

            return RedirectToAction("Result", new { attemptId });
        }

        [HttpGet]
        public async Task<IActionResult> Result(string attemptId)
        {
            Auth.CheckUser();
            var userId = Auth.GetUserId();
            var student = await studentRep.GetByUserID(userId);
            if (student == null)
                return RedirectToAction("Index", "Dashboard", new { area = "Admin" });

            var attempt = await attemptRep.Get(attemptId);
            if (attempt == null || attempt.StudentID != student.StudentID)
                return RedirectToAction("Index", "Dashboard");

            ViewBag.CurrentUser = Auth.GetUser();
            return View(attempt);
        }
    }
}

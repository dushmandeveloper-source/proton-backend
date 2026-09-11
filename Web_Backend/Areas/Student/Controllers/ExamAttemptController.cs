using Microsoft.AspNetCore.Mvc;
using System.Threading.Tasks;
using Web_Backend.Areas.Admin.Data;
using Web_Backend.Classes;

namespace Web_Backend.Areas.StudentPortal.Controllers
{
    [Area("Student")]
    public class ExamAttemptController : Controller
    {
        private readonly IStudentData studentRep;
        private readonly IExamAttemptData attemptRep;

        public ExamAttemptController(IStudentData studentRep, IExamAttemptData attemptRep)
        {
            this.studentRep = studentRep;
            this.attemptRep = attemptRep;
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

            ViewBag.CurrentUser = Auth.GetUser();
            ViewBag.Attempt = attempt;
            ViewBag.Answers = answers;
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

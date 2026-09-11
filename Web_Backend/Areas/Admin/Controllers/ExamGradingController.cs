using Microsoft.AspNetCore.Mvc;
using System.Threading.Tasks;
using Web_Backend.Areas.Admin.Data;
using Web_Backend.Classes;

namespace Web_Backend.Areas.Admin.Controllers
{
    // Admin-side grading queue for submitted exam attempts with ungraded
    // Written answers. Reuses PermissionCode.Exams (not a new permission
    // code) — grading is an operational extension of exam management
    // already governed by that grid entry (see ExamScheduleController).
    [Area("Admin")]
    public class ExamGradingController : Controller
    {
        private readonly IExamAttemptData attemptRep;

        public ExamGradingController(IExamAttemptData attemptRep)
        {
            this.attemptRep = attemptRep;
        }

        [HttpGet]
        public async Task<IActionResult> Index()
        {
            Auth.CheckPermission(PermissionCode.Exams, 'V');
            ViewBag.CurrentUser = Auth.GetUser();
            var pending = await attemptRep.ListPendingGrading();
            return View(pending);
        }

        [HttpGet]
        public async Task<IActionResult> Grade(string attemptId)
        {
            Auth.CheckPermission(PermissionCode.Exams, 'V');
            var attempt = await attemptRep.Get(attemptId);
            if (attempt == null)
                return RedirectToAction("Index");

            var answers = await attemptRep.ListAnswers(attemptId);

            ViewBag.CurrentUser = Auth.GetUser();
            ViewBag.Attempt = attempt;
            ViewBag.Answers = answers;
            return View();
        }

        [HttpPost]
        [ValidateAntiForgeryToken]
        public async Task<IActionResult> SaveGrade(string attemptId, string questionId, decimal marksAwarded)
        {
            Auth.CheckPermission(PermissionCode.Exams, 'E');

            try
            {
                await attemptRep.GradeWritten(attemptId, questionId, marksAwarded);
                TempData["SuccessMessage"] = "Grade saved.";
            }
            catch (System.Exception ex)
            {
                TempData["ErrorMessage"] = "Could not save grade: " + ex.Message;
            }

            return RedirectToAction("Grade", new { attemptId });
        }
    }
}

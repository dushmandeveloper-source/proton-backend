using Microsoft.AspNetCore.Mvc;
using System.Linq;
using Web_Backend.Areas.Admin.Data;
using Web_Backend.Classes;

namespace Web_Backend.Areas.StudentPortal.Controllers
{
    // Phase 3 Task 7 (Part 2, user-requested): a persistent "My Results" page
    // a student can navigate to anytime via the sidebar, listing every exam
    // attempt they've ever made and its status -- Pending (not yet released),
    // or Pass/Fail (released), computed from the same ExamAttempt.Passed
    // property used everywhere else in this feature (Task 5's model, Task 6's
    // release email, Task 7 Part 1's Result.cshtml). Never shows any numeric
    // mark. Kept as its own small controller rather than folded into
    // DashboardController, matching this codebase's one-controller-per-concept
    // convention already seen in the Student area (EnrollmentController,
    // ExamScheduleController are separate from DashboardController).
    [Area("Student")]
    public class MyResultsController : Controller
    {
        private readonly IStudentData studentRep;
        private readonly IExamAttemptData attemptRep;

        public MyResultsController(IStudentData studentRep, IExamAttemptData attemptRep)
        {
            this.studentRep = studentRep;
            this.attemptRep = attemptRep;
        }

        [HttpGet]
        public async Task<IActionResult> Index()
        {
            Auth.CheckUser();
            var userId = Auth.GetUserId();
            var student = await studentRep.GetByUserID(userId);
            if (student == null)
                return RedirectToAction("Index", "Dashboard", new { area = "Admin" });

            var attempts = await attemptRep.ListForStudent(student.StudentID);

            ViewBag.CurrentUser = Auth.GetUser();
            return View(attempts.ToList());
        }
    }
}

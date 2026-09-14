using Microsoft.AspNetCore.Mvc;
using Web_Backend.Areas.Admin.Data;
using Web_Backend.Classes;

namespace Web_Backend.Areas.LecturerPortal.Controllers
{
    // Live-viewing grid (Phase 4) -- lists this lecturer's currently
    // InProgress exam attempts. Auth.CheckUser() only, matching every other
    // Lecturer-area controller's convention (no finer permission check
    // exists for this area); the actual watch authorization is re-checked
    // independently by ExamWatchHub.RequestWatch server-side, so this list
    // being merely "what to show" is not itself the security boundary --
    // the boundary is the hub.
    [Area("Lecturer")]
    public class ExamWatchController : Controller
    {
        private readonly IExamAttemptData attemptRep;

        public ExamWatchController(IExamAttemptData attemptRep)
        {
            this.attemptRep = attemptRep;
        }

        [HttpGet]
        public async Task<IActionResult> Index()
        {
            Auth.CheckUser();
            ViewBag.CurrentUser = Auth.GetUser();
            var inProgress = await attemptRep.ListInProgressForInstructor(Auth.GetUserId());
            return View(inProgress);
        }
    }
}

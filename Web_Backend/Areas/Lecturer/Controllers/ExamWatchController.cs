using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.SignalR;
using Web_Backend.Areas.Admin.Data;
using Web_Backend.Classes;
using Web_Backend.Hubs;

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
        private readonly IExamScheduleData examScheduleRep;
        private readonly IHubContext<ExamWatchHub> watchHub;

        public ExamWatchController(IExamAttemptData attemptRep, IExamScheduleData examScheduleRep, IHubContext<ExamWatchHub> watchHub)
        {
            this.attemptRep = attemptRep;
            this.examScheduleRep = examScheduleRep;
            this.watchHub = watchHub;
        }

        // Lecturer stops an attempt (accident, cheating, student left): submits
        // it with the answers saved so far, so it lands in Exam Grading &
        // Review where it can be graded, rejected or sent back for a redo.
        // Same "assigned to this exam today" rule as ExamWatchHub.RequestWatch.
        [HttpPost]
        [ValidateAntiForgeryToken]
        public async Task<IActionResult> End(string attemptId)
        {
            Auth.CheckUser();
            var userId = Auth.GetUserId();

            var attempt = await attemptRep.Get(attemptId);
            if (attempt == null)
                return Json(new { success = false, message = "Attempt not found." });

            var today = SriLankaTime.Today;
            var segments = await examScheduleRep.GetSegmentsForInstructor(userId, today, today);
            if (!segments.Any(s => s.ExamID == attempt.ExamID))
                return Json(new { success = false, message = "You are not assigned to this exam." });

            if (attempt.Status != "InProgress")
                return Json(new { success = true, message = "This exam had already ended." });

            try
            {
                await attemptRep.Submit(attemptId, isForced: true);
            }
            catch (Exception ex)
            {
                return Json(new { success = false, message = "Could not end the exam: " + ex.Message });
            }

            // If the student still has the exam open, close it for them.
            var connectionId = ExamWatchHub.StudentConnectionFor(attemptId);
            if (connectionId != null)
                await watchHub.Clients.Client(connectionId).SendAsync("ExamEndedByLecturer", attemptId);

            return Json(new { success = true });
        }

        [HttpGet]
        public async Task<IActionResult> Index()
        {
            Auth.CheckUser();
            ViewBag.CurrentUser = Auth.GetUser();
            // A closed browser never submits, so the row stays 'InProgress' --
            // drop ones whose timer has run out (ExpiresDate is UTC since 0071).
            var inProgress = (await attemptRep.ListInProgressForInstructor(Auth.GetUserId()))
                .Where(a => a.ExpiresDate > DateTime.UtcNow)
                .ToList();
            ViewBag.OnlineIds = inProgress
                .Where(a => Web_Backend.Hubs.ExamWatchHub.IsStudentConnected(a.AttemptID))
                .Select(a => a.AttemptID)
                .ToHashSet();
            return View(inProgress);
        }
    }
}

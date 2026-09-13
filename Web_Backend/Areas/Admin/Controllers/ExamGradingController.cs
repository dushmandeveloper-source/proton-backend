using Microsoft.AspNetCore.Mvc;
using System.Threading.Tasks;
using Web_Backend.Areas.Admin.Data;
using Web_Backend.Classes;

namespace Web_Backend.Areas.Admin.Controllers
{
    // Admin-side grading queue for submitted exam attempts with ungraded
    // Written answers, PLUS (Phase 3) the second-stage admin review queue
    // of the teacher-then-admin approval gate, and the violation trail for
    // terminated/flagged attempts. Reuses PermissionCode.Exams (not a new
    // permission code) for all of the above -- grading/review/violation
    // oversight are all operational extensions of exam management already
    // governed by that grid entry.
    [Area("Admin")]
    public class ExamGradingController : Controller
    {
        private readonly IExamAttemptData attemptRep;
        private readonly IEmailSender emailSender;

        public ExamGradingController(IExamAttemptData attemptRep, IEmailSender emailSender)
        {
            this.attemptRep = attemptRep;
            this.emailSender = emailSender;
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

        // ---------- Phase 3: admin review queue (2nd stage of the approval gate) ----------

        [HttpGet]
        public async Task<IActionResult> AdminReview()
        {
            Auth.CheckPermission(PermissionCode.Exams, 'V');
            ViewBag.CurrentUser = Auth.GetUser();
            var pending = await attemptRep.ListAdminReviewQueue();
            return View(pending);
        }

        [HttpPost]
        [ValidateAntiForgeryToken]
        public async Task<IActionResult> AdminApprove(string attemptId)
        {
            Auth.CheckPermission(PermissionCode.Exams, 'E');
            var user = Auth.GetUser();

            try
            {
                // edu.ExamAttempt_AdminApprove enforces server-side that
                // TeacherReviewStatus must already be 'Approved' -- this
                // action never bypasses that ordering even if reached
                // directly (e.g. a forged POST), since the enforcement
                // boundary lives in the stored procedure, not in this
                // controller.
                var released = await attemptRep.AdminApprove(attemptId, user!.Id);

                var emailSent = false;
                if (released != null)
                {
                    // Pass/Fail only -- released.Passed is computed from
                    // TotalMarksAwarded vs. PassingMarks/PassingPercentage
                    // and NEVER exposes the numeric mark itself in the
                    // email body below.
                    var verdict = released.Passed == true ? "Pass" : "Fail";
                    var description = $"Your result for \"{released.ExamTitle}\" has been released. Result: {verdict}. " +
                                      "Log in to your student dashboard for more details.";

                    emailSent = await emailSender.SendTemplateEmailAsync(
                        toEmail: released.StudentEmail,
                        toName: released.StudentName,
                        templateCode: "RESULT_RELEASED",
                        description: description);
                }

                // The approval itself already succeeded and is not rolled back
                // if the email fails to send (SendTemplateEmailAsync never
                // throws -- it returns false and logs internally), so the
                // message must reflect the email outcome accurately rather
                // than always claiming the student was notified.
                TempData["SuccessMessage"] = emailSent
                    ? "Approved and released. The student has been notified."
                    : "Approved and released, but the notification email could not be sent. Check Email Settings and notify the student manually if needed.";
            }
            catch (System.Exception ex)
            {
                TempData["ErrorMessage"] = "Could not approve: " + ex.Message;
            }

            return RedirectToAction("AdminReview");
        }

        // ---------- Phase 3: violation trail for a terminated/flagged attempt ----------

        [HttpGet]
        public async Task<IActionResult> ViolationTrail(string attemptId)
        {
            Auth.CheckPermission(PermissionCode.Exams, 'V');
            var attempt = await attemptRep.Get(attemptId);
            if (attempt == null)
                return RedirectToAction("Index");

            var violations = await attemptRep.ListViolations(attemptId);

            ViewBag.CurrentUser = Auth.GetUser();
            ViewBag.Attempt = attempt;
            return View(violations);
        }
    }
}

using Microsoft.AspNetCore.Mvc;
using System.Linq;
using System.Threading.Tasks;
using Web_Backend.Areas.Admin.Data;
using Web_Backend.Areas.Admin.Models;
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
        private readonly IStudentData studentRep;

        public ExamGradingController(IExamAttemptData attemptRep, IEmailSender emailSender, IStudentData studentRep)
        {
            this.attemptRep = attemptRep;
            this.emailSender = emailSender;
            this.studentRep = studentRep;
        }

        // Combined "Exam Grading + Review" screen -- one page, two client-
        // side tabs. Grading = read-only oversight of Written-answer marking
        // (the lecturer actually grades, see Lecturer/ExamReview). Review =
        // the admin-approval step of the two-stage grading gate. `tab` picks
        // which one shows first (defaults to "grading") so old Index/
        // AdminReview links/bookmarks still land on the right tab.
        [HttpGet]
        public async Task<IActionResult> Index(string tab = "grading")
        {
            Auth.CheckPermission(PermissionCode.Exams, 'V');
            ViewBag.CurrentUser = Auth.GetUser();
            ViewBag.InitialTab = tab == "review" ? "review" : "grading";
            var grading = await attemptRep.ListPendingGrading();
            var review = await attemptRep.ListAdminReviewQueue();
            return View((grading, review));
        }

        // Read-only: Written-answer grading itself now belongs to the
        // Lecturer area (Lecturer/ExamReview/Grade + SaveGrade) so the
        // lecturer who set the exam marks it, not the school admin. Admin
        // keeps this page purely for oversight/visibility -- no SaveGrade
        // action exists here anymore.
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

        // ---------- Phase 3: admin review queue (2nd stage of the approval gate) ----------

        // Back-compat alias for the old separate AdminReview page/links.
        [HttpGet]
        public IActionResult AdminReview() => RedirectToAction("Index", new { tab = "review" });

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

            return RedirectToAction("Index", new { tab = "review" });
        }

        // Single-attempt reject with a required remark. Sends the attempt
        // back into the TEACHER's queue (TeacherReviewStatus reset to
        // 'Pending' by edu.ExamAttempt_AdminReject) rather than back into
        // grading, since an admin rejection is about the approval decision
        // itself, not necessarily the marks -- the teacher sees the remark
        // and re-approves (or re-grades first if the remark calls for it).
        [HttpPost]
        [ValidateAntiForgeryToken]
        public async Task<IActionResult> AdminReject(string attemptId, string remark)
        {
            Auth.CheckPermission(PermissionCode.Exams, 'E');
            var user = Auth.GetUser();

            if (string.IsNullOrWhiteSpace(remark))
            {
                TempData["ErrorMessage"] = "A remark is required to reject an attempt.";
                return RedirectToAction("Index", new { tab = "review" });
            }

            try
            {
                await attemptRep.AdminReject(attemptId, user!.Id, remark);
                TempData["SuccessMessage"] = "Attempt rejected and sent back to the teacher for re-approval.";
            }
            catch (System.Exception ex)
            {
                TempData["ErrorMessage"] = "Could not reject: " + ex.Message;
            }

            return RedirectToAction("Index", new { tab = "review" });
        }

        // ---------- Exam Results History: pick a student, then see their full exam history ----------
        // Mirrors the Lecturer area's History (student picker) ->
        // StudentHistory (that student's attempts) drill-down, except Admin
        // sees every student in the system (no batch/roster ownership
        // restriction -- an admin isn't scoped to any particular lecturer's
        // batches), reusing the same student list the existing Admin/Student
        // management page already lists via IStudentData.GetList.

        [HttpGet]
        public async Task<IActionResult> History()
        {
            Auth.CheckPermission(PermissionCode.Exams, 'V');
            ViewBag.CurrentUser = Auth.GetUser();
            var students = await studentRep.GetList(new StudentSearchView());
            return View(students.OrderBy(s => s.FullName).ToList());
        }

        [HttpGet]
        public async Task<IActionResult> StudentHistory(string studentId)
        {
            Auth.CheckPermission(PermissionCode.Exams, 'V');
            var student = await studentRep.Get(studentId);
            if (student == null)
            {
                TempData["ErrorMessage"] = "Student not found.";
                return RedirectToAction("History");
            }

            var history = await attemptRep.ListForStudent(studentId);

            ViewBag.CurrentUser = Auth.GetUser();
            ViewBag.Student = student;
            return View(history);
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

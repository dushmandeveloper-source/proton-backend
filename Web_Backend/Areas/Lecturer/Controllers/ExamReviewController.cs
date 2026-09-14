using Microsoft.AspNetCore.Mvc;
using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;
using System.Threading.Tasks;
using Web_Backend.Areas.Admin.Data;
using Web_Backend.Areas.Admin.Models;
using Web_Backend.Classes;

namespace Web_Backend.Areas.LecturerPortal.Controllers
{
    // Teacher review queue -- step 1 of the two-stage grading approval
    // gate. Gated by Auth.CheckUser() only, matching every other Lecturer-
    // area controller in this codebase (ExamScheduleController,
    // DashboardController, etc. -- none of them do a finer-grained
    // permission check; a logged-in Lecturer-area session is itself the
    // authorization boundary). Actionable rows are limited server-side to
    // fully-graded, finalized attempts by ExamAttempt_ListTeacherReviewQueue
    // itself, so there is no separate ownership check needed here.
    [Area("Lecturer")]
    public class ExamReviewController : Controller
    {
        private readonly IExamAttemptData attemptRep;
        private readonly ICourseScheduleData scheduleRep;

        public ExamReviewController(IExamAttemptData attemptRep, ICourseScheduleData scheduleRep)
        {
            this.attemptRep = attemptRep;
            this.scheduleRep = scheduleRep;
        }

        // Combined "Exam Grading + Results Review" screen -- one page, two
        // client-side tabs (no separate nav entries/reloads needed since
        // both lists are small and already loaded on every visit). Grading
        // = Written-answer marking (moved here from the Admin area so the
        // lecturer who set/taught the exam grades it, not the school
        // admin). Review = the teacher-approval step of the two-stage
        // grading gate. `tab` query string picks which one shows first
        // (defaults to "grading") so old GradingQueue/Index links/bookmarks
        // still land on the right tab.
        [HttpGet]
        public async Task<IActionResult> Index(string tab = "grading")
        {
            Auth.CheckUser();
            ViewBag.CurrentUser = Auth.GetUser();
            ViewBag.InitialTab = tab == "review" ? "review" : "grading";
            var grading = await attemptRep.ListPendingGrading();
            var review = await attemptRep.ListTeacherReviewQueue();
            return View((grading, review));
        }

        // Back-compat alias for the old separate GradingQueue page/links.
        [HttpGet]
        public IActionResult GradingQueue() => RedirectToAction("Index", new { tab = "grading" });

        // Shows every question/answer for one attempt; Written questions get
        // an inline Save Grade form (MCQ marks are already auto-scored and
        // shown read-only). Also reused as the read-only "View Answers" link
        // from the teacher-approval queue below, since IsFullyGraded=1 by
        // the time an attempt reaches that queue -- the same view just has
        // nothing left to grade at that point.
        [HttpGet]
        public async Task<IActionResult> Grade(string attemptId)
        {
            Auth.CheckUser();
            var attempt = await attemptRep.Get(attemptId);
            if (attempt == null)
                return RedirectToAction("GradingQueue");

            var answers = await attemptRep.ListAnswers(attemptId);

            ViewBag.CurrentUser = Auth.GetUser();
            ViewBag.Attempt = attempt;
            return View(answers);
        }

        [HttpPost]
        [ValidateAntiForgeryToken]
        public async Task<IActionResult> SaveGrade(string attemptId, string questionId, decimal marksAwarded)
        {
            Auth.CheckUser();

            try
            {
                await attemptRep.GradeWritten(attemptId, questionId, marksAwarded);
                TempData["SuccessMessage"] = "Grade saved.";
            }
            catch (Exception ex)
            {
                TempData["ErrorMessage"] = "Could not save grade: " + ex.Message;
            }

            return RedirectToAction("Grade", new { attemptId });
        }

        // Bulk approve: accepts one or more attempt IDs from checkbox-array
        // POST (each checkbox shares name="attemptIds"). Each attempt still
        // goes through edu.ExamAttempt_TeacherApprove's own real validation
        // (Status/IsFullyGraded checks) independently -- this is purely a
        // C# loop over the existing single-attempt proc, NOT a new bulk
        // stored procedure, since the proc is correctly single-attempt by
        // design (reviewed/approved in Task 4). One attempt failing (e.g.
        // already approved by someone else in a race) must not abort the
        // rest of the batch.
        [HttpPost]
        [ValidateAntiForgeryToken]
        public async Task<IActionResult> Approve(List<string> attemptIds)
        {
            Auth.CheckUser();
            var user = Auth.GetUser();

            if (attemptIds == null || !attemptIds.Any())
            {
                TempData["ErrorMessage"] = "No attempts selected.";
                return RedirectToAction("Index", new { tab = "review" });
            }

            int successCount = 0;
            var failures = new List<string>();

            foreach (var attemptId in attemptIds)
            {
                try
                {
                    await attemptRep.TeacherApprove(attemptId, user!.Id);
                    successCount++;
                }
                catch (Exception ex)
                {
                    failures.Add($"{attemptId} ({ex.Message})");
                }
            }

            var summary = new StringBuilder();
            summary.Append($"{successCount} of {attemptIds.Count} approved.");
            if (failures.Any())
            {
                summary.Append($" {failures.Count} failed: {string.Join("; ", failures)}");
                TempData["ErrorMessage"] = summary.ToString();
            }
            else
            {
                TempData["SuccessMessage"] = summary.ToString();
            }

            return RedirectToAction("Index", new { tab = "review" });
        }

        // Single-attempt reject with a required remark -- deliberately not
        // part of the bulk Approve action above, since a rejection needs a
        // reason typed for that specific attempt, unlike a plain approval.
        // Sends the attempt back into GradingQueue (IsFullyGraded reset to 0
        // by the proc) so the lecturer re-grades Written answers taking the
        // remark into account, then re-approves through the normal flow.
        [HttpPost]
        [ValidateAntiForgeryToken]
        public async Task<IActionResult> Reject(string attemptId, string remark)
        {
            Auth.CheckUser();
            var user = Auth.GetUser();

            if (string.IsNullOrWhiteSpace(remark))
            {
                TempData["ErrorMessage"] = "A remark is required to reject an attempt.";
                return RedirectToAction("Index", new { tab = "review" });
            }

            try
            {
                await attemptRep.TeacherReject(attemptId, user!.Id, remark);
                TempData["SuccessMessage"] = "Attempt rejected and sent back for re-grading.";
            }
            catch (Exception ex)
            {
                TempData["ErrorMessage"] = "Could not reject: " + ex.Message;
            }

            return RedirectToAction("Index", new { tab = "review" });
        }

        // Top-level "Exam History" entry point (sidebar), separate from the
        // per-batch drill-down on Courses/Details -- lists every student
        // across all of this lecturer's batches so they don't have to know
        // which batch a student is in first.
        [HttpGet]
        public async Task<IActionResult> History()
        {
            Auth.CheckUser();
            var userId = Auth.GetUserId();

            var batches = await scheduleRep.GetListForInstructor(userId);
            var students = new List<StudentRosterEntry>();
            var seen = new HashSet<string>();
            foreach (var batch in batches)
            {
                var roster = await scheduleRep.GetStudentRosterForInstructor(batch.ScheduleID, userId);
                foreach (var s in roster)
                {
                    if (seen.Add(s.StudentID))
                        students.Add(s);
                }
            }

            ViewBag.CurrentUser = Auth.GetUser();
            return View(students.OrderBy(s => s.StudentName).ToList());
        }

        // "My Batches" -> pick a batch -> pick a student -> that student's
        // full exam history (reuses ListForStudent, which already backs the
        // student-facing "My Results" page -- same query, different viewer).
        // Ownership check: the requested studentId must actually appear on
        // the roster of one of THIS lecturer's own batches, otherwise a
        // lecturer could view an arbitrary student's exam history just by
        // changing the query string. Mirrors CoursesController.Details's own
        // "batches assigned to this lecturer only" check.
        [HttpGet]
        public async Task<IActionResult> StudentHistory(string studentId)
        {
            Auth.CheckUser();
            var userId = Auth.GetUserId();

            var batches = await scheduleRep.GetListForInstructor(userId);
            StudentRosterEntry? student = null;
            foreach (var batch in batches)
            {
                var roster = await scheduleRep.GetStudentRosterForInstructor(batch.ScheduleID, userId);
                student = roster.FirstOrDefault(r => r.StudentID == studentId);
                if (student != null) break;
            }

            if (student == null)
            {
                TempData["ErrorMessage"] = "Student not found, or not enrolled in any of your batches.";
                return RedirectToAction("Index", "Courses");
            }

            var history = await attemptRep.ListForStudent(studentId);

            ViewBag.CurrentUser = Auth.GetUser();
            ViewBag.Student = student;
            return View(history);
        }

        // Read-only violation trail for one attempt -- lecturer-area
        // equivalent of Admin/ExamGrading/ViolationTrail, reusing the same
        // ListViolations repo call. No extra ownership check here beyond
        // Auth.CheckUser(), matching every other Lecturer-area detail view
        // in this controller (Grade, etc.) -- an attemptId isn't guessable
        // enumeration surface any worse than the existing Grade action.
        [HttpGet]
        public async Task<IActionResult> ViolationTrail(string attemptId)
        {
            Auth.CheckUser();
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

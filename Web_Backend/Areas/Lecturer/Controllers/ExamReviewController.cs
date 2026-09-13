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

        public ExamReviewController(IExamAttemptData attemptRep)
        {
            this.attemptRep = attemptRep;
        }

        [HttpGet]
        public async Task<IActionResult> Index()
        {
            Auth.CheckUser();
            ViewBag.CurrentUser = Auth.GetUser();
            var pending = await attemptRep.ListTeacherReviewQueue();
            return View(pending);
        }

        // Written-answer grading queue -- moved here from the Admin area so
        // the lecturer who set/taught the exam grades essay/short-answer
        // questions, not the school admin. Admin's ExamGrading/Index is now
        // read-only oversight only (no SaveGrade action there anymore).
        [HttpGet]
        public async Task<IActionResult> GradingQueue()
        {
            Auth.CheckUser();
            ViewBag.CurrentUser = Auth.GetUser();
            var pending = await attemptRep.ListPendingGrading();
            return View(pending);
        }

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
                return RedirectToAction("Index");
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

            return RedirectToAction("Index");
        }
    }
}

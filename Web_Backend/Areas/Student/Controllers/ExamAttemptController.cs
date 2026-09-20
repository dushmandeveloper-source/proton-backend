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
        private readonly ICourseRegistrationData registrationRep;

        public ExamAttemptController(IStudentData studentRep, IExamAttemptData attemptRep, IExamData examRep, ICourseRegistrationData registrationRep)
        {
            this.studentRep = studentRep;
            this.attemptRep = attemptRep;
            this.examRep = examRep;
            this.registrationRep = registrationRep;
        }

        // An exam tied to a course (Exam.CourseID non-blank) is only
        // attemptable while that course's registration has FullAccess -- a
        // standalone exam (no CourseID) has nothing to check against and is
        // never gated this way. Shared by Start/ConfirmStart so the check
        // can't be bypassed by skipping straight to ConfirmStart.
        private async Task<bool> HasFullAccessForExam(Exam exam, string studentId)
        {
            if (string.IsNullOrEmpty(exam.CourseID)) return true;

            var registrations = await registrationRep.GetByStudent(studentId);
            var reg = registrations.FirstOrDefault(r => r.CourseID == exam.CourseID && r.IsActive == "A");
            return reg == null || reg.FullAccess;
        }

        // Rules + email-confirmation gate, shown BEFORE edu.ExamAttempt_Start
        // is ever called -- the timer/attempt only begins once the student
        // confirms on this page, not the moment they click "Join Exam" on
        // the dashboard.
        [HttpGet]
        public async Task<IActionResult> Start(string examId)
        {
            Auth.CheckUser();
            var userId = Auth.GetUserId();
            var student = await studentRep.GetByUserID(userId);
            if (student == null)
                return RedirectToAction("Index", "Dashboard", new { area = "Admin" });

            var exam = await examRep.Get(examId);
            if (exam == null)
                return RedirectToAction("Index", "Dashboard");

            if (!await HasFullAccessForExam(exam, student.StudentID))
            {
                TempData["ErrorMessage"] = "This exam is locked until full access is granted for its course.";
                return RedirectToAction("Index", "Dashboard");
            }

            ViewBag.CurrentUser = Auth.GetUser();
            ViewBag.Exam = exam;
            return View();
        }

        [HttpPost]
        [ValidateAntiForgeryToken]
        public async Task<IActionResult> ConfirmStart(string examId, string confirmEmail)
        {
            Auth.CheckUser();
            var user = Auth.GetUser();
            var student = await studentRep.GetByUserID(Auth.GetUserId());
            if (student == null)
                return RedirectToAction("Index", "Dashboard", new { area = "Admin" });

            if (user == null || !string.Equals(confirmEmail?.Trim(), user.Email, System.StringComparison.OrdinalIgnoreCase))
            {
                TempData["ErrorMessage"] = "The email you entered doesn't match your account email.";
                return RedirectToAction("Start", new { examId });
            }

            var exam = await examRep.Get(examId);
            if (exam == null || !await HasFullAccessForExam(exam, student.StudentID))
            {
                TempData["ErrorMessage"] = "This exam is locked until full access is granted for its course.";
                return RedirectToAction("Index", "Dashboard");
            }

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

        // Phase 3: the single write path every client-side violation
        // listener in Take.cshtml calls. The SERVER inserts the row and
        // computes the running strike count -- the client never keeps its
        // own count as truth, it only reacts to what this endpoint returns.
        [HttpPost]
        [ValidateAntiForgeryToken]
        public async Task<IActionResult> ReportViolation(string attemptId, string violationType)
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
                var (strikeCount, status) = await attemptRep.ReportViolation(attemptId, violationType);
                return Json(new { success = true, strikeCount, status });
            }
            catch (System.Exception ex)
            {
                return Json(new { success = false, message = ex.Message });
            }
        }

        [HttpPost]
        [ValidateAntiForgeryToken]
        public async Task<IActionResult> Submit(string attemptId, bool isForced = false)
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
                // isForced=true is the exam UI's own auto-submit when camera/
                // screen-share was lost and never restored within the grace
                // window -- it skips the "answer every question" completeness
                // check server-side (see edu.ExamAttempt_Submit's @IsForced),
                // since that student no longer has working proctoring and
                // trapping them behind an unmet completeness rule defeats the
                // point of ending the attempt.
                await attemptRep.Submit(attemptId, isForced);
            }
            catch (System.Exception ex)
            {
                TempData["ErrorMessage"] = "Could not submit: " + ex.Message;
                return RedirectToAction("Take", new { attemptId });
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

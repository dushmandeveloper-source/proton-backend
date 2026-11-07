using Microsoft.AspNetCore.Mvc;
using Web_Backend.Areas.Admin.Data;
using Web_Backend.Areas.Admin.Models;
using Web_Backend.Classes;

namespace Web_Backend.Areas.StudentPortal.Controllers
{
    // Online assignments (0117), opened from the student's Classroom. Same
    // attempt engine as exams (edu.ExamAttempt + answers), but none of the
    // exam proctoring: no email confirmation, fullscreen, camera, screen
    // share or strikes. The student can leave and come back until the due
    // date -- reopening resumes the same InProgress attempt. Answers are
    // saved and submitted through ExamAttemptController.SaveAnswer/Submit.
    [Area("Student")]
    public class OnlineAssignmentController : Controller
    {
        private readonly IStudentData studentRep;
        private readonly IExamData examRep;
        private readonly IExamAttemptData attemptRep;
        private readonly ICourseRegistrationData registrationRep;
        private readonly ICourseScheduleData scheduleRep;

        public OnlineAssignmentController(IStudentData studentRep, IExamData examRep, IExamAttemptData attemptRep,
            ICourseRegistrationData registrationRep, ICourseScheduleData scheduleRep)
        {
            this.studentRep = studentRep;
            this.examRep = examRep;
            this.attemptRep = attemptRep;
            this.registrationRep = registrationRep;
            this.scheduleRep = scheduleRep;
        }

        private IActionResult BackToClass(Exam? exam) => string.IsNullOrEmpty(exam?.AssignmentScheduleID)
            ? RedirectToAction("Index", "Classroom")
            : RedirectToAction("Batch", "Classroom", new { id = exam.AssignmentScheduleID });

        [HttpPost, ValidateAntiForgeryToken]
        public async Task<IActionResult> Open(string examId)
        {
            Auth.CheckUser();
            var student = await studentRep.GetByUserID(Auth.GetUserId());
            if (student == null)
                return RedirectToAction("Index", "Dashboard", new { area = "Admin" });

            var exam = await examRep.Get(examId);
            if (exam == null || !exam.IsAssignment)
            {
                TempData["ErrorMessage"] = "Assignment not found.";
                return RedirectToAction("Index", "Classroom");
            }

            // Resume an attempt already in progress (it expires at the due date).
            var inProgress = (await attemptRep.ListForStudent(student.StudentID))
                .FirstOrDefault(a => a.ExamID == examId && a.IsInProgress);
            if (inProgress != null && inProgress.SecondsRemaining > 0)
                return RedirectToAction("Take", new { attemptId = inProgress.AttemptID });

            var blocked = await OnlineAssignmentRules.WhyCannotStart(exam, student, examRep, registrationRep, scheduleRep);
            if (blocked != null)
            {
                TempData["ErrorMessage"] = blocked;
                return BackToClass(exam);
            }

            try
            {
                var attemptId = await attemptRep.Start(examId, student.StudentID);
                return RedirectToAction("Take", new { attemptId });
            }
            catch (Exception ex)
            {
                TempData["ErrorMessage"] = "Could not open the assignment: " + ex.Message;
                return BackToClass(exam);
            }
        }

        // Sidebar "Assignment marks": every online assignment set for this
        // student (all time), with status, marks and a link to the answers.
        [HttpGet]
        public async Task<IActionResult> Index()
        {
            Auth.CheckUser();
            var student = await studentRep.GetByUserID(Auth.GetUserId());
            if (student == null)
                return RedirectToAction("Index", "Dashboard", new { area = "Admin" });

            var (list, attempts) = await OnlineAssignmentRules.ForStudent(student, examRep, attemptRep, registrationRep, scheduleRep, recentDays: 36500);
            var batches = (await scheduleRep.GetList(new CourseScheduleSearchView { IsActive = "A" })).ToDictionary(b => b.ScheduleID, b => b.ScheduleName);
            ViewBag.CurrentUser = Auth.GetUser();
            ViewBag.Attempts = attempts;
            ViewBag.Redos = await OnlineAssignmentRules.RedosFor(student.StudentID, examRep);
            ViewBag.Batches = batches;
            return View(list.OrderByDescending(e => e.DueDate).ToList());
        }

        // After the lecturer releases the result: the student's own answers,
        // marks per question and, for MCQs, the correct option. Assignments
        // only -- exam results stay Pass/Fail only.
        [HttpGet]
        public async Task<IActionResult> Review(string attemptId)
        {
            Auth.CheckUser();
            var student = await studentRep.GetByUserID(Auth.GetUserId());
            if (student == null)
                return RedirectToAction("Index", "Dashboard", new { area = "Admin" });

            var attempt = await attemptRep.Get(attemptId);
            if (attempt == null || attempt.StudentID != student.StudentID)
                return RedirectToAction("Index", "Classroom");

            var exam = await examRep.Get(attempt.ExamID);
            if (exam == null || !exam.IsAssignment || !attempt.ResultReleasedDate.HasValue)
            {
                TempData["ErrorMessage"] = "Your answers can be viewed once your lecturer releases the marks.";
                return RedirectToAction("Result", "ExamAttempt", new { attemptId });
            }

            var answers = (await attemptRep.ListAnswers(attemptId)).OrderBy(a => a.SortOrder).ToList();
            ViewBag.CurrentUser = Auth.GetUser();
            ViewBag.Attempt = attempt;
            ViewBag.Exam = exam;
            ViewBag.OptionsByQuestion = await ExamAnswerOptions.ForMcq(answers, examRep);
            return View(answers);
        }

        [HttpGet]
        public async Task<IActionResult> Take(string attemptId)
        {
            Auth.CheckUser();
            var student = await studentRep.GetByUserID(Auth.GetUserId());
            if (student == null)
                return RedirectToAction("Index", "Dashboard", new { area = "Admin" });

            var attempt = await attemptRep.Get(attemptId);
            if (attempt == null || attempt.StudentID != student.StudentID)
                return RedirectToAction("Index", "Classroom");

            var exam = await examRep.Get(attempt.ExamID);
            if (exam == null || !exam.IsAssignment)
                return RedirectToAction("Take", "ExamAttempt", new { attemptId });

            if (!attempt.IsInProgress)
                return RedirectToAction("Result", "ExamAttempt", new { attemptId });

            var answers = await attemptRep.ListAnswers(attemptId);
            ViewBag.CurrentUser = Auth.GetUser();
            ViewBag.Attempt = attempt;
            ViewBag.Exam = exam;
            ViewBag.Answers = answers;
            ViewBag.OptionsByQuestion = await ExamAnswerOptions.ForMcq(answers, examRep);
            return View();
        }
    }
}

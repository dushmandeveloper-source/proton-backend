using Microsoft.AspNetCore.Mvc;
using Web_Backend.Areas.Admin.Data;
using Web_Backend.Areas.StudentPortal;
using Web_Backend.Areas.StudentPortal.Models;
using Web_Backend.Classes;

namespace Web_Backend.Areas.StudentPortal.Controllers
{
    // The student self-service dashboard landing page — this week's classes,
    // enrolled courses, and pending payments, all at a glance. Reuses the
    // Admin area's data interfaces/models (IStudentData, ICourseScheduleData,
    // ICourseRegistrationData) since students and admins share the same
    // underlying mst.Student / mst.CourseRegistration tables.
    [Area("Student")]
    public class DashboardController : Controller
    {
        private readonly IStudentData studentRep;
        private readonly ICourseScheduleData scheduleRep;
        private readonly ICourseRegistrationData registrationRep;
        private readonly IExamScheduleData examScheduleRep;
        private readonly IExamAttemptData attemptRep;
        private readonly IExamData examRep;

        public DashboardController(IStudentData studentRep, ICourseScheduleData scheduleRep, ICourseRegistrationData registrationRep, IExamScheduleData examScheduleRep, IExamAttemptData attemptRep, IExamData examRep)
        {
            this.studentRep = studentRep;
            this.scheduleRep = scheduleRep;
            this.registrationRep = registrationRep;
            this.examScheduleRep = examScheduleRep;
            this.attemptRep = attemptRep;
            this.examRep = examRep;
        }

        [HttpGet]
        public async Task<IActionResult> Index()
        {
            Auth.CheckUser();
            var userId = Auth.GetUserId();
            var student = await studentRep.GetByUserID(userId);
            if (student == null)
                return RedirectToAction("Index", "Dashboard", new { area = "Admin" });

            var today = DateTime.Today;
            var diff = (7 + (today.DayOfWeek - DayOfWeek.Monday)) % 7;
            var weekStart = today.AddDays(-diff);
            var weekEnd = weekStart.AddDays(6);

            var schedule = await scheduleRep.GetSegmentsForStudent(student.StudentID, weekStart, weekEnd);
            var summary = await registrationRep.GetSummaryForStudent(student.StudentID);
            var registrations = await registrationRep.GetByStudent(student.StudentID);

            var weekSchedule = new List<StudentScheduleDay>();
            for (var i = 0; i < ScheduleExpansion.WeekDays.Length; i++)
            {
                var (day, code, label) = ScheduleExpansion.WeekDays[i];
                var date = weekStart.AddDays(i);
                var segmentsForDay = ScheduleExpansion.ForDay(schedule, date, code);

                weekSchedule.Add(new StudentScheduleDay
                {
                    DayLabel = label,
                    Date = date,
                    Segments = segmentsForDay
                });
            }

            var model = new StudentDashboardViewModel
            {
                StudentID = student.StudentID,
                StudentName = student.FullName,
                PassportVerificationStatus = student.PassportVerificationStatus,
                IsContentRestricted = student.IsContentRestricted,
                WeekSchedule = weekSchedule,
                Summary = summary,
                Registrations = registrations
            };

            var now = System.DateTime.Now;
            var segments = await examScheduleRep.GetSegmentsForStudent(student.StudentID, now.Date.AddDays(-1), now.Date.AddDays(30));

            var joinRows = new List<Web_Backend.Areas.Admin.Models.ExamJoinRow>();
            var seenExamIds = new HashSet<string>();

            foreach (var seg in segments)
            {
                if (!seenExamIds.Add(seg.ExamID))
                    continue; // one row per exam even if it has multiple schedule segments

                var windowStart = seg.StartDate.Date + (seg.StartTime ?? System.TimeSpan.Zero);
                var windowEnd = seg.EndDate.Date + (seg.EndTime ?? new System.TimeSpan(23, 59, 59));
                var withinWindow = now >= windowStart && now <= windowEnd;

                var exam = await examRep.Get(seg.ExamID);
                if (exam == null) continue;

                var attemptsUsed = await attemptRep.CountByExamAndStudent(seg.ExamID, student.StudentID);

                joinRows.Add(new Web_Backend.Areas.Admin.Models.ExamJoinRow
                {
                    ExamID = seg.ExamID,
                    ExamTitle = seg.ExamTitle,
                    WindowStart = windowStart,
                    WindowEnd = windowEnd,
                    IsWithinWindow = withinWindow,
                    AttemptsUsed = attemptsUsed,
                    MaxAttempts = exam.MaxAttempts
                });
            }

            ViewBag.JoinableExams = joinRows;

            ViewBag.CurrentUser = Auth.GetUser();
            return View(model);
        }
    }
}

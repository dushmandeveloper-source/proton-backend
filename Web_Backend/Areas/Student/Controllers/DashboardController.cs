using Microsoft.AspNetCore.Mvc;
using System.Linq;
using Web_Backend.Areas.Admin.Data;
using Web_Backend.Areas.Admin.Models;
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
        private readonly IDocumentRequestData documentRequestRep;

        public DashboardController(IStudentData studentRep, ICourseScheduleData scheduleRep, ICourseRegistrationData registrationRep, IExamScheduleData examScheduleRep, IExamAttemptData attemptRep, IExamData examRep, IDocumentRequestData documentRequestRep)
        {
            this.studentRep = studentRep;
            this.scheduleRep = scheduleRep;
            this.registrationRep = registrationRep;
            this.examScheduleRep = examScheduleRep;
            this.attemptRep = attemptRep;
            this.examRep = examRep;
            this.documentRequestRep = documentRequestRep;
        }

        [HttpGet]
        public async Task<IActionResult> Index()
        {
            Auth.CheckUser();
            var userId = Auth.GetUserId();
            var student = await studentRep.GetByUserID(userId);
            if (student == null)
                return RedirectToAction("Index", "Dashboard", new { area = "Admin" });

            var today = Web_Backend.Classes.SriLankaTime.Today;
            var diff = (7 + (today.DayOfWeek - DayOfWeek.Monday)) % 7;
            var weekStart = today.AddDays(-diff);
            var weekEnd = weekStart.AddDays(6);

            var schedule = await scheduleRep.GetSegmentsForStudent(student.StudentID, weekStart, weekEnd);
            var summary = await registrationRep.GetSummaryForStudent(student.StudentID);
            var registrations = await registrationRep.GetByStudent(student.StudentID);

            // Merge exam sittings into the same weekly view as course classes —
            // adapted the same way Lecturer's ExamScheduleController already
            // does it (ExamScheduleInstructorSegment -> StudentScheduleSegment,
            // Kind = "Exam"), so one combined, time-sorted list renders instead
            // of a separate "Your Exams" card buried lower on the page.
            var now = Web_Backend.Classes.SriLankaTime.Now;
            var examSegments = await examScheduleRep.GetSegmentsForStudent(student.StudentID, weekStart, weekEnd);
            var adaptedExamSegments = examSegments.Select(ToStudentScheduleSegment).ToList();
            var combinedSchedule = schedule.Concat(adaptedExamSegments).ToList();

            var weekSchedule = new List<StudentScheduleDay>();
            for (var i = 0; i < ScheduleExpansion.WeekDays.Length; i++)
            {
                var (day, code, label) = ScheduleExpansion.WeekDays[i];
                var date = weekStart.AddDays(i);
                var segmentsForDay = ScheduleExpansion.ForDay(combinedSchedule, date, code)
                    .OrderBy(s => s.StartTime)
                    .ToList();

                weekSchedule.Add(new StudentScheduleDay
                {
                    DayLabel = label,
                    Date = date,
                    Segments = segmentsForDay
                });
            }

            var documentItems = await documentRequestRep.ListForStudent(student.StudentID);
            var pendingDocumentCount = documentItems.Count(i => i.CanSubmit);

            var model = new StudentDashboardViewModel
            {
                StudentID = student.StudentID,
                StudentName = student.FullName,
                PassportVerificationStatus = student.PassportVerificationStatus,
                IsContentRestricted = student.IsContentRestricted,
                WeekSchedule = weekSchedule,
                Summary = summary,
                Registrations = registrations,
                PendingDocumentRequestCount = pendingDocumentCount
            };

            // Exam Join gating (availability window + MaxAttempts), looked up by
            // ExamID (carried in the adapted segment's CourseID) when the view
            // renders each exam row — same window over which exam segments were
            // fetched above is reused here rather than querying twice.
            var joinRows = new Dictionary<string, Web_Backend.Areas.Admin.Models.ExamJoinRow>();
            var seenExamIds = new HashSet<string>();

            // Every attempt this student has ever made, any exam -- used
            // below purely to detect a still-pending-review one per exam so
            // the dashboard can show "Pending Review" instead of "Join" (no
            // point starting another attempt while one is still awaiting
            // grading/approval). Fetched once outside the loop rather than
            // per-exam, same reasoning as reusing examSegments' window above.
            var studentAttempts = await attemptRep.ListForStudent(student.StudentID);

            foreach (var seg in examSegments)
            {
                if (!seenExamIds.Add(seg.ExamID))
                    continue; // one row per exam even if it has multiple schedule segments

                var windowStart = seg.StartDate.Date + (seg.StartTime ?? TimeSpan.Zero);
                var windowEnd = seg.EndDate.Date + (seg.EndTime ?? new TimeSpan(23, 59, 59));
                var withinWindow = now >= windowStart && now <= windowEnd;

                var exam = await examRep.Get(seg.ExamID);
                if (exam == null) continue;

                var attemptsUsed = await attemptRep.CountByExamAndStudent(seg.ExamID, student.StudentID);

                var hasPendingReview = studentAttempts.Any(a =>
                    a.ExamID == seg.ExamID &&
                    a.Status != "InProgress" &&
                    !a.ResultReleasedDate.HasValue);

                var examReg = string.IsNullOrEmpty(exam.CourseID)
                    ? null
                    : registrations.FirstOrDefault(r => r.CourseID == exam.CourseID && r.IsActive == "A");
                var hasFullAccess = examReg == null || examReg.FullAccess;

                joinRows[seg.ExamID] = new Web_Backend.Areas.Admin.Models.ExamJoinRow
                {
                    ExamID = seg.ExamID,
                    ExamTitle = seg.ExamTitle,
                    WindowStart = windowStart,
                    WindowEnd = windowEnd,
                    IsWithinWindow = withinWindow,
                    AttemptsUsed = attemptsUsed,
                    MaxAttempts = exam.MaxAttempts,
                    HasPendingReview = hasPendingReview,
                    HasFullAccess = hasFullAccess
                };
            }

            ViewBag.ExamJoinRows = joinRows;

            ViewBag.CurrentUser = Auth.GetUser();
            return View(model);
        }

        // Adapter mapping: ExamScheduleInstructorSegment -> StudentScheduleSegment,
        // same shape/convention as Lecturer's ExamScheduleController — lets the
        // combined weekly list reuse StudentScheduleDay/Segment and the shared
        // view markup, distinguished at render time by Kind == "Exam".
        private static StudentScheduleSegment ToStudentScheduleSegment(ExamScheduleInstructorSegment seg)
        {
            return new StudentScheduleSegment
            {
                SegmentID = seg.SegmentID,
                ScheduleID = seg.ScheduleID,
                CourseID = seg.ExamID,
                CourseTitle = seg.ExamTitle,
                ScheduleName = seg.ScheduleName,
                BatchName = seg.BatchName,
                Location = seg.Location,
                StartDate = seg.StartDate,
                EndDate = seg.EndDate,
                DaysOfWeek = seg.DaysOfWeek,
                StartTime = seg.StartTime ?? System.TimeSpan.Zero,
                EndTime = seg.EndTime ?? System.TimeSpan.Zero,
                InstructorNames = seg.InstructorNames,
                ExceptionDates = seg.ExceptionDates,
                MeetingLink = seg.MeetingLink,
                Kind = "Exam"
            };
        }
    }
}

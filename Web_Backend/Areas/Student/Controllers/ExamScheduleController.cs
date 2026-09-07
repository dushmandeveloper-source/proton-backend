using Microsoft.AspNetCore.Mvc;
using Web_Backend.Areas.Admin.Data;
using Web_Backend.Areas.Admin.Models;
using Web_Backend.Areas.StudentPortal.Models;
using Web_Backend.Classes;

namespace Web_Backend.Areas.StudentPortal.Controllers
{
    // Read-only monthly calendar of the student's exam sittings — mirrors
    // Areas/Student/Controllers/ScheduleController.cs (the CourseSchedule
    // equivalent), sourced from IExamScheduleData.GetSegmentsForStudent
    // instead of ICourseScheduleData.GetSegmentsForStudent, plus an approved
    // makeup-date overlay the same way Lecturer's ScheduleController.cs
    // does it for courses (see plan sections 6/7).
    //
    // View-model choice: like Lecturer's ExamScheduleController, this
    // adapter-maps each ExamScheduleInstructorSegment onto a
    // StudentScheduleSegment (CourseTitle <- ExamTitle, CourseID <- ExamID)
    // so it can reuse StudentCalendarViewModel/CalendarWeek/CalendarDay and
    // Views/Schedule/Index.cshtml's markup style verbatim, rather than
    // introducing a parallel Exam-specific calendar view-model triad.
    //
    // Known gap (per plan section 3): students only see exams linked to a
    // course batch they're registered in (via GetSegmentsForStudent's join
    // through CourseScheduleID); standalone exam sittings with no
    // CourseScheduleID are not shown to students in this round, since no
    // other exam-enrollment/registration table exists yet.
    [Area("Student")]
    public class ExamScheduleController : Controller
    {
        private readonly IStudentData studentRep;
        private readonly IExamScheduleData scheduleRep;
        private readonly IHolidayEventData holidayRep;
        private readonly IExamScheduleRescheduleData rescheduleRep;

        public ExamScheduleController(IStudentData studentRep, IExamScheduleData scheduleRep, IHolidayEventData holidayRep, IExamScheduleRescheduleData rescheduleRep)
        {
            this.studentRep = studentRep;
            this.scheduleRep = scheduleRep;
            this.holidayRep = holidayRep;
            this.rescheduleRep = rescheduleRep;
        }

        [HttpGet]
        public async Task<IActionResult> Index(int? year, int? month)
        {
            Auth.CheckUser();
            var userId = Auth.GetUserId();
            var student = await studentRep.GetByUserID(userId);
            if (student == null)
                return RedirectToAction("Index", "Dashboard", new { area = "Admin" });

            var targetYear = year ?? DateTime.Today.Year;
            var targetMonth = month ?? DateTime.Today.Month;
            if (targetMonth < 1) targetMonth = 1;
            if (targetMonth > 12) targetMonth = 12;

            var firstOfMonth = new DateTime(targetYear, targetMonth, 1);
            var lastOfMonth = firstOfMonth.AddMonths(1).AddDays(-1);

            var gridStart = firstOfMonth;
            while (gridStart.DayOfWeek != DayOfWeek.Monday)
                gridStart = gridStart.AddDays(-1);

            var gridEnd = lastOfMonth;
            while (gridEnd.DayOfWeek != DayOfWeek.Sunday)
                gridEnd = gridEnd.AddDays(1);

            var examSegments = await scheduleRep.GetSegmentsForStudent(student.StudentID, gridStart, gridEnd);
            var segments = examSegments.Select(ToStudentScheduleSegment).ToList();
            var holidays = await holidayRep.GetByDateRange(gridStart, gridEnd);

            // Approved exam reschedules, overlaid as synthetic one-off
            // "segments" on their ProposedNewDate — mirrors the course
            // reschedule overlay in Areas/Student/Controllers/ScheduleController.cs.
            var scheduleIds = segments.Select(s => s.ScheduleID).Distinct().ToList();
            var makeups = new List<(DateTime Date, StudentScheduleSegment Segment)>();
            foreach (var scheduleId in scheduleIds)
            {
                var requests = await rescheduleRep.ListForSchedule(scheduleId);
                foreach (var r in requests.Where(r => r.Status == "Approved"
                    && r.ProposedNewDate.Date >= gridStart.Date && r.ProposedNewDate.Date <= gridEnd.Date))
                {
                    var original = segments.FirstOrDefault(s => s.SegmentID == r.SegmentID);
                    if (original == null) continue;

                    makeups.Add((r.ProposedNewDate.Date, new StudentScheduleSegment
                    {
                        SegmentID = original.SegmentID,
                        ScheduleID = original.ScheduleID,
                        CourseID = original.CourseID,
                        CourseTitle = original.CourseTitle + " (Makeup Exam)",
                        ScheduleName = original.ScheduleName,
                        BatchName = original.BatchName,
                        Location = original.Location,
                        StartDate = r.ProposedNewDate.Date,
                        EndDate = r.ProposedNewDate.Date,
                        DaysOfWeek = ScheduleExpansion.CodeFor(r.ProposedNewDate.DayOfWeek),
                        StartTime = original.StartTime,
                        EndTime = original.EndTime,
                        InstructorNames = original.InstructorNames,
                        MeetingLink = original.MeetingLink
                    }));
                }
            }

            var weeks = new List<CalendarWeek>();
            var cursor = gridStart;
            while (cursor <= gridEnd)
            {
                var week = new CalendarWeek();
                for (var i = 0; i < 7; i++)
                {
                    var dayCode = ScheduleExpansion.CodeFor(cursor.DayOfWeek);
                    var day = cursor;
                    var classesForDay = ScheduleExpansion.ForDay(segments, cursor, dayCode);
                    var makeupsForDay = makeups.Where(m => m.Date == day.Date).Select(m => m.Segment);

                    week.Days.Add(new CalendarDay
                    {
                        Date = cursor,
                        IsCurrentMonth = cursor.Month == targetMonth && cursor.Year == targetYear,
                        IsToday = cursor.Date == DateTime.Today,
                        Classes = classesForDay.Concat(makeupsForDay).ToList(),
                        Holidays = holidays.Where(h => h.HolidayDate.Date == day.Date).ToList()
                    });
                    cursor = cursor.AddDays(1);
                }
                weeks.Add(week);
            }

            var prevMonthDate = firstOfMonth.AddMonths(-1);
            var nextMonthDate = firstOfMonth.AddMonths(1);

            var model = new StudentCalendarViewModel
            {
                Year = targetYear,
                Month = targetMonth,
                MonthLabel = firstOfMonth.ToString("MMMM yyyy"),
                Weeks = weeks,
                PrevYear = prevMonthDate.Year,
                PrevMonth = prevMonthDate.Month,
                NextYear = nextMonthDate.Year,
                NextMonth = nextMonthDate.Month
            };

            ViewBag.CurrentUser = Auth.GetUser();
            return View(model);
        }

        // Adapter mapping: ExamScheduleInstructorSegment -> StudentScheduleSegment
        // so the shared CalendarDay/CalendarWeek/StudentCalendarViewModel and
        // Views/Schedule/Index.cshtml-style markup can be reused verbatim for
        // exam data. CourseTitle carries ExamTitle, CourseID carries ExamID —
        // same convention as Lecturer's ExamScheduleController.
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
                StartTime = seg.StartTime ?? TimeSpan.Zero,
                EndTime = seg.EndTime ?? TimeSpan.Zero,
                InstructorNames = seg.InstructorNames,
                ExceptionDates = seg.ExceptionDates,
                MeetingLink = seg.MeetingLink
            };
        }
    }
}

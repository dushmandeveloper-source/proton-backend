using Microsoft.AspNetCore.Mvc;
using Web_Backend.Areas.Admin.Data;
using Web_Backend.Areas.Admin.Models;
using Web_Backend.Areas.LecturerPortal.Models;
using Web_Backend.Areas.StudentPortal.Models;
using Web_Backend.Classes;

namespace Web_Backend.Areas.LecturerPortal.Controllers
{
    // Read-only monthly calendar of the lecturer's assigned exam-schedule
    // batches — mirrors ScheduleController.cs (the CourseSchedule
    // equivalent), including the makeup-date/reschedule overlay block: an
    // approved ExamScheduleReschedule's ProposedNewDate is synthesized as an
    // extra one-off segment so it shows up on the grid even when it falls
    // outside the segment's normal DaysOfWeek/StartDate-EndDate pattern.
    //
    // View-model choice (plan section 5 / 11 item 1): CalendarDay.Classes is
    // declared as List<StudentScheduleSegment> (see
    // Areas/Student/Models/StudentCalendarViewModel.cs), which is already a
    // thin display DTO (SegmentID/ScheduleID/CourseTitle/ScheduleName/
    // Location/StartDate/EndDate/DaysOfWeek/StartTime/EndTime/
    // InstructorNames/MeetingLink — no Course-specific business logic used
    // by the calendar view itself). Rather than introduce a parallel
    // ExamCalendarWeek/ExamCalendarDay/LecturerExamCalendarViewModel triad,
    // this controller adapter-maps each ExamScheduleInstructorSegment onto a
    // StudentScheduleSegment (CourseTitle <- ExamTitle, CourseID <- ExamID)
    // so it can reuse LecturerCalendarViewModel/CalendarWeek/CalendarDay and
    // the existing Views/Schedule/Index.cshtml markup style verbatim.
    [Area("Lecturer")]
    public class ExamScheduleController : Controller
    {
        private readonly IExamScheduleData scheduleRep;
        private readonly IHolidayEventData holidayRep;
        private readonly IExamScheduleRescheduleData rescheduleRep;

        public ExamScheduleController(IExamScheduleData scheduleRep, IHolidayEventData holidayRep, IExamScheduleRescheduleData rescheduleRep)
        {
            this.scheduleRep = scheduleRep;
            this.holidayRep = holidayRep;
            this.rescheduleRep = rescheduleRep;
        }

        [HttpGet]
        public async Task<IActionResult> Index(int? year, int? month)
        {
            Auth.CheckUser();
            var userId = Auth.GetUserId();

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

            var segments = await scheduleRep.GetSegmentsForInstructor(userId, gridStart, gridEnd);
            var holidays = await holidayRep.GetByDateRange(gridStart, gridEnd);

            var batches = await scheduleRep.GetListForInstructor(userId);

            // Approved makeup dates for this lecturer's exam schedules,
            // overlaid as synthetic one-off "segments" on their
            // ProposedNewDate so they show up on the grid even when that
            // date falls outside the segment's normal DaysOfWeek/StartDate-
            // EndDate pattern. Mirrors ScheduleController.cs's course-side
            // overlay logic.
            var batchScheduleIds = batches.Select(b => b.ScheduleID).ToHashSet();
            var makeups = new List<(DateTime Date, StudentScheduleSegment Segment)>();
            foreach (var scheduleId in batchScheduleIds)
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
                        CourseID = original.ExamID,
                        CourseTitle = original.ExamTitle + " (Makeup Exam)",
                        ScheduleName = original.ScheduleName,
                        BatchName = original.BatchName,
                        Location = original.Location,
                        StartDate = r.ProposedNewDate.Date,
                        EndDate = r.ProposedNewDate.Date,
                        DaysOfWeek = ExamScheduleExpansion.CodeFor(r.ProposedNewDate.DayOfWeek),
                        StartTime = original.StartTime ?? TimeSpan.Zero,
                        EndTime = original.EndTime ?? TimeSpan.Zero,
                        InstructorNames = original.InstructorNames,
                        MeetingLink = original.MeetingLink,
                        Kind = "Exam"
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
                    var dayCode = ExamScheduleExpansion.CodeFor(cursor.DayOfWeek);
                    var day = cursor;
                    var classesForDay = ExamScheduleExpansion.ForDay(segments, cursor, dayCode).Select(ToStudentScheduleSegment);
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

            var model = new LecturerCalendarViewModel
            {
                Year = targetYear,
                Month = targetMonth,
                MonthLabel = firstOfMonth.ToString("MMMM yyyy"),
                Weeks = weeks,
                PrevYear = prevMonthDate.Year,
                PrevMonth = prevMonthDate.Month,
                NextYear = nextMonthDate.Year,
                NextMonth = nextMonthDate.Month,
                // Distinguishes "no batches assigned at all" from "assigned,
                // just nothing scheduled this month".
                HasAssignedBatches = batches.Count > 0
            };

            ViewBag.CurrentUser = Auth.GetUser();
            return View(model);
        }

        // Adapter mapping: ExamScheduleInstructorSegment -> StudentScheduleSegment
        // so the shared CalendarDay/CalendarWeek/LecturerCalendarViewModel and
        // Views/Schedule/Index.cshtml-style markup can be reused verbatim for
        // exam data. CourseTitle carries ExamTitle, CourseID carries ExamID.
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
                MeetingLink = seg.MeetingLink,
                Kind = "Exam"
            };
        }
    }
}

using Microsoft.AspNetCore.Mvc;
using Web_Backend.Areas.Admin.Data;
using Web_Backend.Areas.Admin.Models;
using Web_Backend.Areas.LecturerPortal.Models;
using Web_Backend.Areas.StudentPortal;
using Web_Backend.Areas.StudentPortal.Models;
using Web_Backend.Classes;

namespace Web_Backend.Areas.LecturerPortal.Controllers
{
    // Monthly calendar view of the lecturer's assigned-batch schedule — near-
    // identical to the Student portal's ScheduleController, built on
    // GetSegmentsForInstructor + ScheduleExpansion instead of
    // GetSegmentsForStudent. Also overlays Approved reschedule rows'
    // ProposedNewDate as an extra calendar entry: a makeup date outside the
    // segment's normal weekly pattern won't appear from ScheduleExpansion
    // alone, since Approve() only ever adds the ORIGINAL date to
    // ExceptionDates (a skip), never the new date to any recurring pattern.
    [Area("Lecturer")]
    public class ScheduleController : Controller
    {
        private readonly ICourseScheduleData scheduleRep;
        private readonly IHolidayEventData holidayRep;
        private readonly ICourseScheduleRescheduleData rescheduleRep;

        public ScheduleController(ICourseScheduleData scheduleRep, IHolidayEventData holidayRep, ICourseScheduleRescheduleData rescheduleRep)
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

            // Approved makeup dates for this lecturer's batches, overlaid as
            // synthetic one-off "segments" on their ProposedNewDate so they
            // show up on the grid even when that date falls outside the
            // segment's normal DaysOfWeek/StartDate-EndDate pattern.
            var batches = await scheduleRep.GetListForInstructor(userId);
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
                        CourseID = original.CourseID,
                        CourseTitle = original.CourseTitle + " (Makeup Class)",
                        ScheduleName = original.ScheduleName,
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
                // just nothing scheduled this month" — an empty grid reads as
                // a bug otherwise, since there's no batch data to explain it.
                HasAssignedBatches = batches.Count > 0
            };

            ViewBag.CurrentUser = Auth.GetUser();
            return View(model);
        }
    }
}

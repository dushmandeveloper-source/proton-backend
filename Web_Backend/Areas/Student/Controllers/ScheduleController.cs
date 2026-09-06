using Microsoft.AspNetCore.Mvc;
using Web_Backend.Areas.Admin.Data;
using Web_Backend.Areas.StudentPortal.Models;
using Web_Backend.Classes;

namespace Web_Backend.Areas.StudentPortal.Controllers
{
    // Monthly calendar view of the student's class schedule — a wider-angle
    // companion to Dashboard's "This Week's Classes" widget, built on the
    // same ICourseScheduleData.GetSegmentsForStudent + ScheduleExpansion
    // day-matching helper.
    [Area("Student")]
    public class ScheduleController : Controller
    {
        private readonly IStudentData studentRep;
        private readonly ICourseScheduleData scheduleRep;
        private readonly IHolidayEventData holidayRep;

        public ScheduleController(IStudentData studentRep, ICourseScheduleData scheduleRep, IHolidayEventData holidayRep)
        {
            this.studentRep = studentRep;
            this.scheduleRep = scheduleRep;
            this.holidayRep = holidayRep;
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

            var segments = await scheduleRep.GetSegmentsForStudent(student.StudentID, gridStart, gridEnd);
            var holidays = await holidayRep.GetByDateRange(gridStart, gridEnd);

            var weeks = new List<CalendarWeek>();
            var cursor = gridStart;
            while (cursor <= gridEnd)
            {
                var week = new CalendarWeek();
                for (var i = 0; i < 7; i++)
                {
                    var dayCode = ScheduleExpansion.CodeFor(cursor.DayOfWeek);
                    var day = cursor;
                    week.Days.Add(new CalendarDay
                    {
                        Date = cursor,
                        IsCurrentMonth = cursor.Month == targetMonth && cursor.Year == targetYear,
                        IsToday = cursor.Date == DateTime.Today,
                        Classes = ScheduleExpansion.ForDay(segments, cursor, dayCode),
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
    }
}

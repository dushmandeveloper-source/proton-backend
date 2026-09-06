using Web_Backend.Areas.Admin.Models;

namespace Web_Backend.Areas.StudentPortal.Models
{
    // One day cell in the monthly calendar grid — see
    // Areas/Student/Controllers/ScheduleController.cs for how this is built.
    public class CalendarDay
    {
        public DateTime Date { get; set; }
        public bool IsCurrentMonth { get; set; }
        public bool IsToday { get; set; }
        public List<StudentScheduleSegment> Classes { get; set; } = new();
        // Global holidays/events on this date (edu.HolidayEvent) — not
        // student-specific, same source the Admin calendar already reads.
        public List<HolidayEvent> Holidays { get; set; } = new();
    }

    // One row (Mon..Sun) of the monthly calendar grid.
    public class CalendarWeek
    {
        public List<CalendarDay> Days { get; set; } = new();
    }

    // Backs Areas/Student/Views/Schedule/Index.cshtml.
    public class StudentCalendarViewModel
    {
        public int Year { get; set; }
        public int Month { get; set; }
        public string MonthLabel { get; set; } = "";

        public List<CalendarWeek> Weeks { get; set; } = new();

        public int PrevYear { get; set; }
        public int PrevMonth { get; set; }
        public int NextYear { get; set; }
        public int NextMonth { get; set; }
    }
}

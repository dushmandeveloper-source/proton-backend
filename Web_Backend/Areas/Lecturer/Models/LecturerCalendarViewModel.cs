using Web_Backend.Areas.StudentPortal.Models;

namespace Web_Backend.Areas.LecturerPortal.Models
{
    // Backs Areas/Lecturer/Views/Schedule/Index.cshtml. Reuses the Student
    // portal's CalendarDay/CalendarWeek directly (per the plan) — they're
    // already generic (built from StudentScheduleSegment + HolidayEvent,
    // neither of which is Student-specific).
    public class LecturerCalendarViewModel
    {
        public int Year { get; set; }
        public int Month { get; set; }
        public string MonthLabel { get; set; } = "";

        public List<CalendarWeek> Weeks { get; set; } = new();

        public int PrevYear { get; set; }
        public int PrevMonth { get; set; }
        public int NextYear { get; set; }
        public int NextMonth { get; set; }

        // False when the lecturer has no assigned batches at all — the view
        // uses this to explain an empty grid instead of leaving it looking
        // broken with no indication of why nothing is scheduled.
        public bool HasAssignedBatches { get; set; }
    }
}

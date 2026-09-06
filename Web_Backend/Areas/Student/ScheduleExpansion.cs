using Web_Backend.Areas.Admin.Models;

namespace Web_Backend.Areas.StudentPortal
{
    // Shared day-matching logic for expanding a student's schedule segments
    // onto a calendar. Factored out of DashboardController.Index so the same
    // Mon..Sun code table and StartDate/EndDate/DaysOfWeek matching rule is
    // used by both the "This Week's Classes" widget and the ScheduleController
    // monthly calendar, instead of duplicating the Where/Split/Contains logic.
    public static class ScheduleExpansion
    {
        // Mon..Sun order, matching the 3-letter day codes stored in
        // StudentScheduleSegment.DaysOfWeek (CSV, e.g. "Mon,Wed,Fri").
        public static readonly (DayOfWeek Day, string Code, string Label)[] WeekDays =
        {
            (DayOfWeek.Monday, "Mon", "Monday"),
            (DayOfWeek.Tuesday, "Tue", "Tuesday"),
            (DayOfWeek.Wednesday, "Wed", "Wednesday"),
            (DayOfWeek.Thursday, "Thu", "Thursday"),
            (DayOfWeek.Friday, "Fri", "Friday"),
            (DayOfWeek.Saturday, "Sat", "Saturday"),
            (DayOfWeek.Sunday, "Sun", "Sunday"),
        };

        // 3-letter code for a given DayOfWeek, per the table above.
        public static string CodeFor(DayOfWeek day)
        {
            foreach (var wd in WeekDays)
            {
                if (wd.Day == day)
                    return wd.Code;
            }
            return "";
        }

        // True when `segment` applies on `date` — the date falls within the
        // segment's [StartDate, EndDate] range (inclusive, date-only),
        // `dayCode` (the 3-letter code for date.DayOfWeek) is one of the
        // segment's DaysOfWeek CSV entries, and `date` is not one of the
        // segment's ExceptionDates (CSV of yyyy-MM-dd, e.g. an approved
        // reschedule's skipped original date, or a holiday/trainer-
        // unavailability day authored on the Admin schedule edit screen).
        public static bool AppliesOn(StudentScheduleSegment segment, DateTime date, string dayCode)
        {
            if (date < segment.StartDate.Date || date > segment.EndDate.Date) return false;
            if (!segment.DaysOfWeek.Split(',', StringSplitOptions.RemoveEmptyEntries).Contains(dayCode)) return false;
            if (!string.IsNullOrWhiteSpace(segment.ExceptionDates))
            {
                var iso = date.ToString("yyyy-MM-dd");
                if (segment.ExceptionDates.Split(',', StringSplitOptions.RemoveEmptyEntries)
                    .Select(d => d.Trim())
                    .Contains(iso))
                    return false;
            }
            return true;
        }

        // Convenience overload: derives the day code from date.DayOfWeek.
        public static bool AppliesOn(StudentScheduleSegment segment, DateTime date)
        {
            return AppliesOn(segment, date, CodeFor(date.DayOfWeek));
        }

        // All segments (from `segments`) applicable on `date`.
        public static List<StudentScheduleSegment> ForDay(List<StudentScheduleSegment> segments, DateTime date, string dayCode)
        {
            return segments.Where(s => AppliesOn(s, date, dayCode)).ToList();
        }
    }
}

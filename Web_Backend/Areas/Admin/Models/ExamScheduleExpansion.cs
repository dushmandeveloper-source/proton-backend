namespace Web_Backend.Areas.Admin.Models
{
    // Parallel to Areas/Student/ScheduleExpansion.cs, retyped against
    // ExamScheduleInstructorSegment instead of StudentScheduleSegment.
    // Deliberately duplicated rather than generifying the Student-area
    // helper — see plan section 7: keeps ExamSchedule fully decoupled from
    // CourseSchedule/Student-portal code, at the cost of ~30 duplicated
    // lines of stable, unlikely-to-change day-matching logic.
    public static class ExamScheduleExpansion
    {
        // Mon..Sun order, matching the 3-letter day codes stored in
        // ExamScheduleInstructorSegment.DaysOfWeek (CSV, e.g. "Mon,Wed,Fri").
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
        // segment's ExceptionDates (CSV of yyyy-MM-dd).
        public static bool AppliesOn(ExamScheduleInstructorSegment segment, DateTime date, string dayCode)
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
        public static bool AppliesOn(ExamScheduleInstructorSegment segment, DateTime date)
        {
            return AppliesOn(segment, date, CodeFor(date.DayOfWeek));
        }

        // All segments (from `segments`) applicable on `date`.
        public static List<ExamScheduleInstructorSegment> ForDay(List<ExamScheduleInstructorSegment> segments, DateTime date, string dayCode)
        {
            return segments.Where(s => AppliesOn(s, date, dayCode)).ToList();
        }
    }
}

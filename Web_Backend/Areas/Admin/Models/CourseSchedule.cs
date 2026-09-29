using System.ComponentModel.DataAnnotations;

namespace Web_Backend.Areas.Admin.Models
{
    // Maps edu.CourseSchedule. One batch (course intake, or CSCA exam
    // sitting) made up of one or more time periods (Segments) — e.g. "Jan
    // 5-30, Mon/Wed, 6-8pm" then "Feb 2-27, Mon/Wed/Fri, 6-8pm" under the
    // same batch. Two batches can share identical dates but run at
    // different times by being separate CourseSchedule rows (e.g. morning
    // vs evening batch).
    public class CourseSchedule
    {
        public string ScheduleID { get; set; } = "";

        [Required(ErrorMessage = "Course is required.")]
        public string CourseID { get; set; } = "";
        public string ScheduleName { get; set; } = "";

        public string Location { get; set; } = "";
        public int? Capacity { get; set; }
        public string Notes { get; set; } = "";

        public string IsActive { get; set; } = "A";
        public DateTime CreatedDate { get; set; }
        public DateTime? UpdatedDate { get; set; }

        // Joined from edu.Course.
        public string CourseTitle { get; set; } = "";
        public string CourseType { get; set; } = "";

        public string StatusLabel => IsActive == "A" ? "Active" : "Inactive";

        // Child collection, JSON-serialized on save (see
        // CourseScheduleData.AddEdit) and reassembled server-side via
        // OPENJSON — same mechanism as edu.Course's child tables.
        public List<CourseScheduleSegment> Segments { get; set; } = new();

        // Instructors/invigilators assigned to this batch, shared across all
        // its periods (not per-segment) — replaces the old free-text
        // TrainerName field. Same JSON child-list mechanism as Segments.
        public List<ScheduleInstructor> Instructors { get; set; } = new();
        public string InstructorsLabel => Instructors.Count == 0 ? "" : string.Join(", ", Instructors.Select(i => i.FullName));

        // "05 Jan 2026 - 30 Jan 2026 · Mon, Wed · 18:00 - 20:00 (1 day off); 02 Feb ..."
        public string SegmentsSummary => string.Join("; ", Segments
            .OrderBy(s => s.SortOrder)
            .Select(s => string.Join(" · ", new[] { s.DateRangeText, s.DaysOfWeekLabel, s.TimeRangeText }
                .Where(part => !string.IsNullOrEmpty(part)))
                + (s.ExceptionCount > 0 ? $" ({s.ExceptionCount} day{(s.ExceptionCount == 1 ? "" : "s")} off)" : "")));

        public DateTime? EarliestStartDate => Segments.Count == 0 ? null : Segments.Min(s => s.StartDate);
        public DateTime? LatestEndDate => Segments.Count == 0 ? null : Segments.Max(s => s.EndDate);

        // Populated only by edu.CourseSchedule_ListForInstructor (Lecturer
        // "My Batches" list) — a headcount only, never the roster/PII, per
        // the Lecturer Portal plan's explicit privacy constraint.
        public int EnrolledCount { get; set; }
    }

    public class ScheduleInstructor
    {
        public string UserID { get; set; } = "";
        public string FullName { get; set; } = "";
    }

    public class CourseScheduleSegment
    {
        public string SegmentID { get; set; } = "";

        [Required(ErrorMessage = "Start date is required.")]
        public DateTime StartDate { get; set; }

        [Required(ErrorMessage = "End date is required.")]
        public DateTime EndDate { get; set; }

        // CSV of 3-letter day codes in Mon..Sun order, e.g. "Mon,Wed,Fri".
        [Required(ErrorMessage = "At least one day of week is required.")]
        public string DaysOfWeek { get; set; } = "";

        public TimeSpan? StartTime { get; set; }
        public TimeSpan? EndTime { get; set; }
        public int SortOrder { get; set; }

        // CSV of ISO dates (yyyy-MM-dd) within [StartDate, EndDate] that are
        // skipped despite falling on an active weekday — holidays, trainer
        // unavailability, etc. Same CSV style as DaysOfWeek.
        public string ExceptionDates { get; set; } = "";

        // Optional Zoom/VooV/Teams (or any other) online meeting URL for
        // this period. Set by Admin (full batch edit) or by an assigned
        // lecturer (CourseScheduleSegment_UpdateMeetingLinks, scoped to
        // their own batches) — one link can be pasted once and applied to
        // several selected periods, or set per-period.
        public string MeetingLink { get; set; } = "";

        // Per-date time overrides — see SegmentTimeOverrides for the format.
        public string TimeOverrides { get; set; } = "";

        // "18:00 - 20:00" for `date` — the override if one exists, else the
        // period's own TimeRangeText.
        public string TimeRangeTextOn(DateTime date) =>
            SegmentTimeOverrides.Parse(TimeOverrides).TryGetValue(date.ToString("yyyy-MM-dd"), out var t)
                ? $"{t.Start:hh\\:mm} - {t.End:hh\\:mm}"
                : TimeRangeText;

        public string DateRangeText => $"{StartDate:dd MMM yyyy} - {EndDate:dd MMM yyyy}";
        public string DaysOfWeekLabel => string.Join(", ", DaysOfWeek.Split(',', StringSplitOptions.RemoveEmptyEntries));
        public string TimeRangeText => StartTime.HasValue && EndTime.HasValue
            ? $"{StartTime:hh\\:mm} - {EndTime:hh\\:mm}"
            : "";

        public int ExceptionCount => ExceptionDates.Split(',', StringSplitOptions.RemoveEmptyEntries).Length;
    }

    // edu.CourseScheduleSegment.TimeOverrides (0081): CSV of
    // "yyyy-MM-dd@HH:mm-HH:mm" — a single date within a period that runs at
    // a different time from the period's own StartTime/EndTime.
    public static class SegmentTimeOverrides
    {
        public static Dictionary<string, (TimeSpan Start, TimeSpan End)> Parse(string? csv)
        {
            var result = new Dictionary<string, (TimeSpan, TimeSpan)>();
            foreach (var entry in (csv ?? "").Split(',', StringSplitOptions.RemoveEmptyEntries))
            {
                var parts = entry.Trim().Split('@');
                if (parts.Length != 2) continue;
                var times = parts[1].Split('-');
                if (times.Length == 2 && TimeSpan.TryParse(times[0], out var start) && TimeSpan.TryParse(times[1], out var end))
                    result[parts[0]] = (start, end);
            }
            return result;
        }

        // "22 Sep 18:00-20:00, 29 Sep 17:00-19:00" for list/summary views.
        public static string Describe(string? csv) => string.Join(", ", Parse(csv)
            .OrderBy(kv => kv.Key)
            .Select(kv => DateTime.TryParse(kv.Key, out var d)
                ? $"{d:dd MMM} {kv.Value.Start:hh\\:mm}-{kv.Value.End:hh\\:mm}"
                : ""));
    }

    public class CourseScheduleSearchView
    {
        public string CourseID { get; set; } = "";
        public string KeyW { get; set; } = "";
        public DateTime? FromDate { get; set; }
        public DateTime? ToDate { get; set; }
        public string IsActive { get; set; } = "";
    }

    // Counts every row a permanent delete of one batch would touch. Unlike
    // Course, two of these can still block the delete outright (reschedule
    // requests, or a linked exam sitting) — see edu.CourseSchedule_DeletePermanently.
    public class CourseScheduleDeleteImpact
    {
        public int RegistrationCount { get; set; }
        public int ExamSittingCount { get; set; }
        public int RescheduleCount { get; set; }
    }
}

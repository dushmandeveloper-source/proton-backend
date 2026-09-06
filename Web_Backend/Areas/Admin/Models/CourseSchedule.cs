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

        public string DateRangeText => $"{StartDate:dd MMM yyyy} - {EndDate:dd MMM yyyy}";
        public string DaysOfWeekLabel => string.Join(", ", DaysOfWeek.Split(',', StringSplitOptions.RemoveEmptyEntries));
        public string TimeRangeText => StartTime.HasValue && EndTime.HasValue
            ? $"{StartTime:hh\\:mm} - {EndTime:hh\\:mm}"
            : "";

        public int ExceptionCount => ExceptionDates.Split(',', StringSplitOptions.RemoveEmptyEntries).Length;
    }

    public class CourseScheduleSearchView
    {
        public string CourseID { get; set; } = "";
        public string KeyW { get; set; } = "";
        public DateTime? FromDate { get; set; }
        public DateTime? ToDate { get; set; }
        public string IsActive { get; set; } = "";
    }
}

using System.ComponentModel.DataAnnotations;

namespace Web_Backend.Areas.Admin.Models
{
    // Maps edu.ExamSchedule. Mirrors CourseSchedule.cs's shape almost 1:1,
    // scoped to edu.Exam instead of edu.Course — one exam sitting made up of
    // one or more time periods (Segments). No ExamScheduleReschedule/
    // ExamScheduleNote concept exists (out of scope for this phase — see
    // 0028_exam_schedule.sql's header).
    public class ExamSchedule
    {
        public string ScheduleID { get; set; } = "";

        [Required(ErrorMessage = "Exam is required.")]
        public string ExamID { get; set; } = "";
        public string ScheduleName { get; set; } = "";

        // Optional link to the edu.CourseSchedule batch this sitting is
        // attached to (e.g. a CSCA exam tied to a specific course intake).
        // Not required — plenty of exam schedules are standalone.
        public string CourseScheduleID { get; set; } = "";

        public string Location { get; set; } = "";
        public int? Capacity { get; set; }
        public string Notes { get; set; } = "";

        public string IsActive { get; set; } = "A";
        public DateTime CreatedDate { get; set; }
        public DateTime? UpdatedDate { get; set; }

        // Joined from edu.Exam.
        public string ExamTitle { get; set; } = "";

        // Joined from edu.CourseSchedule via CourseScheduleID, when set.
        public string BatchName { get; set; } = "";

        public string StatusLabel => IsActive == "A" ? "Active" : "Inactive";

        // Child collection, JSON-serialized on save (see
        // ExamScheduleData.AddEdit) and reassembled server-side via OPENJSON
        // — same mechanism as edu.CourseSchedule's segments.
        public List<ExamScheduleSegment> Segments { get; set; } = new();

        // Instructors/invigilators assigned to this sitting, shared across
        // all its periods (not per-segment). Reuses ScheduleInstructor from
        // CourseSchedule.cs — a bare UserID/FullName DTO with no
        // Course-specific coupling — rather than duplicating it.
        public List<ScheduleInstructor> Instructors { get; set; } = new();
        public string InstructorsLabel => Instructors.Count == 0 ? "" : string.Join(", ", Instructors.Select(i => i.FullName));

        public string SegmentsSummary => string.Join("; ", Segments
            .OrderBy(s => s.SortOrder)
            .Select(s => string.Join(" · ", new[] { s.DateRangeText, s.DaysOfWeekLabel, s.TimeRangeText }
                .Where(part => !string.IsNullOrEmpty(part)))
                + (s.ExceptionCount > 0 ? $" ({s.ExceptionCount} day{(s.ExceptionCount == 1 ? "" : "s")} off)" : "")));

        public DateTime? EarliestStartDate => Segments.Count == 0 ? null : Segments.Min(s => s.StartDate);
        public DateTime? LatestEndDate => Segments.Count == 0 ? null : Segments.Max(s => s.EndDate);

        // Populated only by edu.ExamSchedule_ListForInstructor (Lecturer "My
        // Exams" list) — kept for shape parity with CourseSchedule, but
        // always 0: no exam-registration/enrollment table exists yet.
        public int EnrolledCount { get; set; }
    }

    public class ExamScheduleSegment
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
        // skipped despite falling on an active weekday.
        public string ExceptionDates { get; set; } = "";

        // Optional Zoom/VooV/Teams (or any other) online meeting URL for
        // this period. Set by Admin only in this phase (no Lecturer
        // self-service link editing — read-only Lecturer calendar).
        public string MeetingLink { get; set; } = "";

        public string DateRangeText => $"{StartDate:dd MMM yyyy} - {EndDate:dd MMM yyyy}";
        public string DaysOfWeekLabel => string.Join(", ", DaysOfWeek.Split(',', StringSplitOptions.RemoveEmptyEntries));
        public string TimeRangeText => StartTime.HasValue && EndTime.HasValue
            ? $"{StartTime:hh\\:mm} - {EndTime:hh\\:mm}"
            : "";

        public int ExceptionCount => ExceptionDates.Split(',', StringSplitOptions.RemoveEmptyEntries).Length;
    }

    public class ExamScheduleSearchView
    {
        public string ExamID { get; set; } = "";
        public string KeyW { get; set; } = "";
        public DateTime? FromDate { get; set; }
        public DateTime? ToDate { get; set; }
        public string IsActive { get; set; } = "";
    }

    // Flat per-occurrence row used by GetSegmentsForInstructor (Lecturer
    // read-only calendar). Deliberately not reusing Student's
    // StudentScheduleSegment (which has CourseID/CourseTitle baked into its
    // shape and is genuinely course-specific) — a parallel, small DTO here
    // keeps ExamSchedule fully decoupled from the Course-side model.
    public class ExamScheduleInstructorSegment
    {
        public string SegmentID { get; set; } = "";
        public string ScheduleID { get; set; } = "";
        public string ExamID { get; set; } = "";
        public string ExamTitle { get; set; } = "";
        public string ScheduleName { get; set; } = "";
        public string CourseScheduleID { get; set; } = "";
        public string BatchName { get; set; } = "";
        public string Location { get; set; } = "";
        public DateTime StartDate { get; set; }
        public DateTime EndDate { get; set; }
        public string DaysOfWeek { get; set; } = "";
        public TimeSpan? StartTime { get; set; }
        public TimeSpan? EndTime { get; set; }
        public string ExceptionDates { get; set; } = "";
        public string MeetingLink { get; set; } = "";
        public string InstructorNames { get; set; } = "";

        // Discriminator distinguishing this exam-schedule segment from an
        // ordinary course-schedule segment — see StudentScheduleSegment.Kind.
        public string Kind { get; set; } = "Exam";
    }
}

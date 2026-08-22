using System.ComponentModel.DataAnnotations;

namespace Web_Backend.Areas.Admin.Models
{
    // Maps edu.CourseSchedule. One dated/timed offering ("batch") of a
    // course. For CSCA this row is a real exam sitting (e.g. the official
    // Jan/Mar/Apr/Jun/Dec sessions); for General courses it's a regular
    // intake/batch. Same shape serves both — no CourseType branching needed.
    public class CourseSchedule
    {
        public string ScheduleID { get; set; } = "";

        [Required(ErrorMessage = "Course is required.")]
        public string CourseID { get; set; } = "";
        public string ScheduleName { get; set; } = "";

        public DateTime? ScheduleDate { get; set; }
        public TimeSpan? StartTime { get; set; }
        public TimeSpan? EndTime { get; set; }
        public string Location { get; set; } = "";
        public int? Capacity { get; set; }
        public string TrainerName { get; set; } = "";
        public string Notes { get; set; } = "";

        public string IsActive { get; set; } = "A";
        public DateTime CreatedDate { get; set; }
        public DateTime? UpdatedDate { get; set; }

        // Joined from edu.Course.
        public string CourseTitle { get; set; } = "";
        public string CourseType { get; set; } = "";

        public string StatusLabel => IsActive == "A" ? "Active" : "Inactive";
        public string TimeRangeText => StartTime.HasValue && EndTime.HasValue
            ? $"{StartTime:hh\\:mm} - {EndTime:hh\\:mm}"
            : "";
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

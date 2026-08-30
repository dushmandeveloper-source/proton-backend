namespace Web_Backend.Areas.Admin.Models
{
    // Maps edu.CourseScheduleNote. A remark attached to a specific calendar
    // DATE — separate from CourseSchedule.Notes (which is per-batch free
    // text edited via the add/edit form). A calendar note can optionally
    // reference one CourseSchedule batch that occurs on that date
    // (ScheduleID set), or stand alone as a general remark such as
    // "Public holiday — no classes today" (ScheduleID null).
    public class CourseScheduleNote
    {
        public string NoteID { get; set; } = "";
        public DateTime NoteDate { get; set; }

        // Optional link to the batch this note is about. Null/empty means a
        // general, date-only remark not tied to any specific batch.
        public string? ScheduleID { get; set; }

        public string NoteText { get; set; } = "";
        public string IsActive { get; set; } = "A";
        public DateTime CreatedDate { get; set; }
        public DateTime? UpdatedDate { get; set; }

        // Joined from edu.CourseSchedule / edu.Course when ScheduleID is set.
        public string? ScheduleName { get; set; }
        public string? CourseTitle { get; set; }

        public bool IsLinked => !string.IsNullOrEmpty(ScheduleID);
    }
}

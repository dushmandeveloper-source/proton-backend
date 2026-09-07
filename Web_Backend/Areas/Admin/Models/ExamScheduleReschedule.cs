namespace Web_Backend.Areas.Admin.Models
{
    // Maps edu.ExamScheduleReschedule (Database/migrations/0030_exam_schedule_reschedule.sql)
    // -- a lecturer/invigilator-submitted request to move ONE occurrence of a
    // recurring exam segment to a different date. Admin-approved before it
    // takes effect; on approval, OriginalDate is appended into the segment's
    // ExceptionDates CSV so every calendar view skips it automatically.
    // Mirrors CourseScheduleReschedule.cs 1:1, Exam-flavored.
    public class ExamScheduleReschedule
    {
        public string RescheduleID { get; set; } = "";
        public string ScheduleID { get; set; } = "";
        public string SegmentID { get; set; } = "";
        public DateTime OriginalDate { get; set; }
        public DateTime ProposedNewDate { get; set; }
        public string? Remark { get; set; }
        public string RequestedByUserID { get; set; } = "";

        // 'Pending' | 'Approved' | 'Rejected'
        public string Status { get; set; } = "Pending";
        public string? AdminRemark { get; set; }
        public string? ApprovedByUserID { get; set; }
        public DateTime? ApprovedDate { get; set; }

        public DateTime CreatedDate { get; set; }
        public DateTime? UpdatedDate { get; set; }

        // Joined display fields (present depending on which list sproc populated this row).
        public string ScheduleName { get; set; } = "";
        public string ExamTitle { get; set; } = "";
        public string RequestedByName { get; set; } = "";

        public string StatusLabel => Status;
    }
}

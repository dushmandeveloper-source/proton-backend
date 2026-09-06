namespace Web_Backend.Areas.Admin.Models
{
    // Maps edu.CourseScheduleReschedule (Database/migrations/0021_lecturer_portal.sql)
    // -- a lecturer-submitted request to move ONE occurrence of a recurring
    // segment to a different date. Admin-approved before it takes effect;
    // on approval, OriginalDate is appended into the segment's
    // ExceptionDates CSV so every calendar view skips it automatically.
    public class CourseScheduleReschedule
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
        public string CourseTitle { get; set; } = "";
        public string RequestedByName { get; set; } = "";

        public string StatusLabel => Status;
    }
}

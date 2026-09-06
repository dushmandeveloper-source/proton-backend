using System.ComponentModel.DataAnnotations;

namespace Web_Backend.Areas.LecturerPortal.Models
{
    // Backs Areas/Lecturer/Views/Reschedule/Create.cshtml — a lecturer's
    // request to move one occurrence of a segment to a different date.
    public class RescheduleRequestFormModel
    {
        [Required]
        public string ScheduleID { get; set; } = "";

        [Required]
        public string SegmentID { get; set; } = "";

        [Required(ErrorMessage = "Select the original class date to reschedule.")]
        public DateTime? OriginalDate { get; set; }

        [Required(ErrorMessage = "Select the proposed new date.")]
        public DateTime? ProposedNewDate { get; set; }

        [MaxLength(500)]
        public string Remark { get; set; } = "";

        // Display-only, populated by the controller for the confirmation form.
        public string ScheduleName { get; set; } = "";
        public string CourseTitle { get; set; } = "";
    }
}

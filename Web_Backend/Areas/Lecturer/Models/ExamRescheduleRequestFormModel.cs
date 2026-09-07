using System.ComponentModel.DataAnnotations;

namespace Web_Backend.Areas.LecturerPortal.Models
{
    // Backs Areas/Lecturer/Views/ExamReschedule/Create.cshtml — a lecturer's
    // request to move one occurrence of an exam segment to a different date.
    // Mirrors RescheduleRequestFormModel.cs, ExamTitle instead of CourseTitle.
    public class ExamRescheduleRequestFormModel
    {
        [Required]
        public string ScheduleID { get; set; } = "";

        [Required]
        public string SegmentID { get; set; } = "";

        [Required(ErrorMessage = "Select the original exam date to reschedule.")]
        public DateTime? OriginalDate { get; set; }

        [Required(ErrorMessage = "Select the proposed new date.")]
        public DateTime? ProposedNewDate { get; set; }

        [MaxLength(500)]
        public string Remark { get; set; } = "";

        // Display-only, populated by the controller for the confirmation form.
        public string ScheduleName { get; set; } = "";
        public string ExamTitle { get; set; } = "";
    }
}

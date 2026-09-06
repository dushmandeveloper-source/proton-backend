using System.ComponentModel.DataAnnotations;

namespace Web_Backend.Areas.LecturerPortal.Models
{
    // Backs Areas/Lecturer/Views/Notes/Upload.cshtml.
    public class LectureMaterialFormModel
    {
        [Required]
        public string ScheduleID { get; set; } = "";

        // Optional: blank means a batch-wide note not tied to one date.
        public string SegmentID { get; set; } = "";

        [Required(ErrorMessage = "Select the class date this material is for.")]
        public DateTime? MaterialDate { get; set; }

        [Required(ErrorMessage = "Title is required.")]
        [MaxLength(200)]
        public string Title { get; set; } = "";

        [MaxLength(1000)]
        public string Description { get; set; } = "";

        // Display-only, populated by the controller for the upload form.
        public string ScheduleName { get; set; } = "";
        public string CourseTitle { get; set; } = "";
    }
}

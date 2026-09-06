namespace Web_Backend.Areas.Admin.Models
{
    // One row from edu.CourseSchedule_ListStudentRoster — a lecturer's view
    // of who is in their own assigned batch. Deliberately narrower than the
    // full Student/CourseRegistration models (no address, passport,
    // payment, or emergency-contact fields) since a lecturer only needs
    // enough to recognize/contact their own students, not admin-level detail.
    public class StudentRosterEntry
    {
        public string StudentID { get; set; } = "";
        public string StudentName { get; set; } = "";
        public string StudentEmail { get; set; } = "";
        public DateTime? DateOfBirth { get; set; }
        public string ProfileImageUrl { get; set; } = "";
    }
}

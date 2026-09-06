using Web_Backend.Areas.Admin.Models;

namespace Web_Backend.Areas.StudentPortal.Models
{
    // Backs Areas/Student/Views/Courses/Details.cshtml — one registration
    // plus its course details, payment history, and applicable schedule
    // segments. See CoursesController.Details for how each part is fetched.
    public class CourseDetailsViewModel
    {
        public CourseRegistration Registration { get; set; } = new();
        public Course? Course { get; set; }
        public List<CourseRegistrationPayment> Payments { get; set; } = new();
        public List<StudentScheduleSegment> Segments { get; set; } = new();

        // Lecture notes/materials visible to this student for this
        // registration's batch — see ILectureMaterialData.ListForStudent,
        // which joins mst.CourseRegistration so ownership is already
        // enforced by the sproc, not filtered again here.
        public List<LectureMaterial> Materials { get; set; } = new();
    }
}

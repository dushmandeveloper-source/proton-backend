using Web_Backend.Areas.Admin.Models;

namespace Web_Backend.Areas.StudentPortal.Models
{
    // Backs Areas/Student/Views/Enrollment/Info.cshtml — a pre-enrollment,
    // read-only course detail page. Same data shape as the public
    // GET api/courses/{id} endpoint (Controllers/Api/CoursesApiController.Get)
    // that frontend/src/CourseDetailPage.jsx renders, so this page shows a
    // student the exact same information the public marketing site does.
    public class CourseInfoViewModel
    {
        public Course Course { get; set; } = new();
        public List<CourseSubject> Subjects { get; set; } = new();
        public List<CourseSchedule> Schedules { get; set; } = new();
    }
}

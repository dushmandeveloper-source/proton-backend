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

        // Payment-gated course videos for this registration's course — see
        // ICourseVideoData.ListForStudent (edu.CourseVideo_ListForStudent),
        // which already nulls out FileURL/ExternalURL server-side for any
        // row where PaymentStatus <> 'Paid', so a locked video's URL never
        // reaches this view model in the first place.
        public List<CourseVideo> Videos { get; set; } = new();

        // Account/passport verification gate (Student.IsContentRestricted).
        // The page itself is always reachable — a restricted student still
        // needs to see their balance and pay it — but Materials/Schedule/
        // Homework sections render disabled (no join links, no file
        // downloads) until an Admin verifies the account. Distinct from,
        // and stacked on top of, Videos' own payment-only gate above.
        public bool IsContentRestricted { get; set; }
    }
}

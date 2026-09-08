using Web_Backend.Areas.Admin.Models;

namespace Web_Backend.Areas.StudentPortal.Models
{
    // One day of the current week's schedule (Mon..Sun), with every class
    // segment applicable that day — see DashboardController.Index for how
    // this is built from ICourseScheduleData.GetSegmentsForStudent.
    public class StudentScheduleDay
    {
        public string DayLabel { get; set; } = "";
        public DateTime Date { get; set; }
        public List<StudentScheduleSegment> Segments { get; set; } = new();
    }

    // Backs Areas/Student/Views/Dashboard/Index.cshtml.
    public class StudentDashboardViewModel
    {
        public string StudentID { get; set; } = "";
        public string StudentName { get; set; } = "";
        public string PassportVerificationStatus { get; set; } = "Pending";
        public bool IsContentRestricted { get; set; }

        public List<StudentScheduleDay> WeekSchedule { get; set; } = new();

        public CourseRegistrationStudentSummary? Summary { get; set; }
        public List<CourseRegistration> Registrations { get; set; } = new();
    }
}

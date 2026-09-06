using Web_Backend.Areas.Admin.Models;

namespace Web_Backend.Areas.LecturerPortal.Models
{
    // One day of the current week's schedule (Mon..Sun) for the lecturer
    // dashboard's "This Week's Classes" widget — same shape as the Student
    // portal's StudentScheduleDay.
    public class LecturerScheduleDay
    {
        public string DayLabel { get; set; } = "";
        public DateTime Date { get; set; }
        public List<StudentScheduleSegment> Segments { get; set; } = new();
    }

    // Backs Areas/Lecturer/Views/Dashboard/Index.cshtml.
    public class LecturerDashboardViewModel
    {
        public string UserID { get; set; } = "";
        public string LecturerName { get; set; } = "";

        public List<LecturerScheduleDay> WeekSchedule { get; set; } = new();

        public int AssignedBatchCount { get; set; }
        public int PendingRescheduleCount { get; set; }
        public List<LectureMaterial> RecentMaterials { get; set; } = new();
    }
}

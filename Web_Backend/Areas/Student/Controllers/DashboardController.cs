using Microsoft.AspNetCore.Mvc;
using Web_Backend.Areas.Admin.Data;
using Web_Backend.Areas.StudentPortal;
using Web_Backend.Areas.StudentPortal.Models;
using Web_Backend.Classes;

namespace Web_Backend.Areas.StudentPortal.Controllers
{
    // The student self-service dashboard landing page — this week's classes,
    // enrolled courses, and pending payments, all at a glance. Reuses the
    // Admin area's data interfaces/models (IStudentData, ICourseScheduleData,
    // ICourseRegistrationData) since students and admins share the same
    // underlying mst.Student / mst.CourseRegistration tables.
    [Area("Student")]
    public class DashboardController : Controller
    {
        private readonly IStudentData studentRep;
        private readonly ICourseScheduleData scheduleRep;
        private readonly ICourseRegistrationData registrationRep;

        public DashboardController(IStudentData studentRep, ICourseScheduleData scheduleRep, ICourseRegistrationData registrationRep)
        {
            this.studentRep = studentRep;
            this.scheduleRep = scheduleRep;
            this.registrationRep = registrationRep;
        }

        [HttpGet]
        public async Task<IActionResult> Index()
        {
            Auth.CheckUser();
            var userId = Auth.GetUserId();
            var student = await studentRep.GetByUserID(userId);
            if (student == null)
                return RedirectToAction("Index", "Dashboard", new { area = "Admin" });

            var today = DateTime.Today;
            var diff = (7 + (today.DayOfWeek - DayOfWeek.Monday)) % 7;
            var weekStart = today.AddDays(-diff);
            var weekEnd = weekStart.AddDays(6);

            var schedule = await scheduleRep.GetSegmentsForStudent(student.StudentID, weekStart, weekEnd);
            var summary = await registrationRep.GetSummaryForStudent(student.StudentID);
            var registrations = await registrationRep.GetByStudent(student.StudentID);

            var weekSchedule = new List<StudentScheduleDay>();
            for (var i = 0; i < ScheduleExpansion.WeekDays.Length; i++)
            {
                var (day, code, label) = ScheduleExpansion.WeekDays[i];
                var date = weekStart.AddDays(i);
                var segmentsForDay = ScheduleExpansion.ForDay(schedule, date, code);

                weekSchedule.Add(new StudentScheduleDay
                {
                    DayLabel = label,
                    Date = date,
                    Segments = segmentsForDay
                });
            }

            var model = new StudentDashboardViewModel
            {
                StudentID = student.StudentID,
                StudentName = student.FullName,
                PassportVerificationStatus = student.PassportVerificationStatus,
                IsContentRestricted = student.IsContentRestricted,
                WeekSchedule = weekSchedule,
                Summary = summary,
                Registrations = registrations
            };

            ViewBag.CurrentUser = Auth.GetUser();
            return View(model);
        }
    }
}

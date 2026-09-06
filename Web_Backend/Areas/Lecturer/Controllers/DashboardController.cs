using Microsoft.AspNetCore.Mvc;
using Web_Backend.Areas.Admin.Data;
using Web_Backend.Areas.LecturerPortal.Models;
using Web_Backend.Areas.StudentPortal;
using Web_Backend.Classes;

namespace Web_Backend.Areas.LecturerPortal.Controllers
{
    // The lecturer self-service dashboard landing page — this week's
    // classes, assigned-batch count, pending-reschedule count, and recent
    // materials, at a glance. Reuses the Admin area's data interfaces
    // (ICourseScheduleData's instructor-scoped methods,
    // ICourseScheduleRescheduleData, ILectureMaterialData) and the Student
    // portal's ScheduleExpansion day-matching helper — none of that logic is
    // Student-specific, it just hasn't had a second caller until now.
    [Area("Lecturer")]
    public class DashboardController : Controller
    {
        private readonly ICourseScheduleData scheduleRep;
        private readonly ICourseScheduleRescheduleData rescheduleRep;
        private readonly ILectureMaterialData materialRep;

        public DashboardController(ICourseScheduleData scheduleRep, ICourseScheduleRescheduleData rescheduleRep, ILectureMaterialData materialRep)
        {
            this.scheduleRep = scheduleRep;
            this.rescheduleRep = rescheduleRep;
            this.materialRep = materialRep;
        }

        [HttpGet]
        public async Task<IActionResult> Index()
        {
            Auth.CheckUser();
            var userId = Auth.GetUserId();

            var today = DateTime.Today;
            var diff = (7 + (today.DayOfWeek - DayOfWeek.Monday)) % 7;
            var weekStart = today.AddDays(-diff);
            var weekEnd = weekStart.AddDays(6);

            var schedule = await scheduleRep.GetSegmentsForInstructor(userId, weekStart, weekEnd);
            var batches = await scheduleRep.GetListForInstructor(userId);
            var pending = await rescheduleRep.ListForLecturer(userId);
            var materials = await materialRep.ListForLecturer(userId);

            var weekSchedule = new List<LecturerScheduleDay>();
            for (var i = 0; i < ScheduleExpansion.WeekDays.Length; i++)
            {
                var (day, code, label) = ScheduleExpansion.WeekDays[i];
                var date = weekStart.AddDays(i);
                var segmentsForDay = ScheduleExpansion.ForDay(schedule, date, code);

                weekSchedule.Add(new LecturerScheduleDay
                {
                    DayLabel = label,
                    Date = date,
                    Segments = segmentsForDay
                });
            }

            var model = new LecturerDashboardViewModel
            {
                UserID = userId,
                LecturerName = Auth.GetUser()?.Name ?? "",
                WeekSchedule = weekSchedule,
                AssignedBatchCount = batches.Count,
                PendingRescheduleCount = pending.Count(r => r.Status == "Pending"),
                RecentMaterials = materials.Take(5).ToList()
            };

            ViewBag.CurrentUser = Auth.GetUser();
            return View(model);
        }
    }
}

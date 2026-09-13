using Microsoft.AspNetCore.Mvc;
using System.Linq;
using Web_Backend.Areas.Admin.Data;
using Web_Backend.Areas.Admin.Models;
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
        private readonly IExamScheduleData examScheduleRep;

        public DashboardController(ICourseScheduleData scheduleRep, ICourseScheduleRescheduleData rescheduleRep, ILectureMaterialData materialRep, IExamScheduleData examScheduleRep)
        {
            this.scheduleRep = scheduleRep;
            this.rescheduleRep = rescheduleRep;
            this.materialRep = materialRep;
            this.examScheduleRep = examScheduleRep;
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

            // Merge exam sittings into the same weekly view as course classes
            // -- same adapter mapping Lecturer's own ExamScheduleController
            // already uses (ExamScheduleInstructorSegment -> StudentScheduleSegment,
            // Kind = "Exam"), so the dashboard's "This Week" list shows both
            // instead of only course classes.
            var examSegments = await examScheduleRep.GetSegmentsForInstructor(userId, weekStart, weekEnd);
            var adaptedExamSegments = examSegments.Select(ToStudentScheduleSegment).ToList();
            var combinedSchedule = schedule.Concat(adaptedExamSegments).ToList();

            var weekSchedule = new List<LecturerScheduleDay>();
            for (var i = 0; i < ScheduleExpansion.WeekDays.Length; i++)
            {
                var (day, code, label) = ScheduleExpansion.WeekDays[i];
                var date = weekStart.AddDays(i);
                var segmentsForDay = ScheduleExpansion.ForDay(combinedSchedule, date, code)
                    .OrderBy(s => s.StartTime)
                    .ToList();

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

        // Adapter mapping: ExamScheduleInstructorSegment -> StudentScheduleSegment,
        // same shape/convention as Areas/Lecturer/Controllers/ExamScheduleController.cs's
        // own adapter and the Student dashboard's -- lets the combined weekly
        // list reuse LecturerScheduleDay/Segment and the shared view markup,
        // distinguished at render time by Kind == "Exam".
        private static StudentScheduleSegment ToStudentScheduleSegment(ExamScheduleInstructorSegment seg)
        {
            return new StudentScheduleSegment
            {
                SegmentID = seg.SegmentID,
                ScheduleID = seg.ScheduleID,
                CourseID = seg.ExamID,
                CourseTitle = seg.ExamTitle,
                ScheduleName = seg.ScheduleName,
                BatchName = seg.BatchName,
                Location = seg.Location,
                StartDate = seg.StartDate,
                EndDate = seg.EndDate,
                DaysOfWeek = seg.DaysOfWeek,
                StartTime = seg.StartTime ?? TimeSpan.Zero,
                EndTime = seg.EndTime ?? TimeSpan.Zero,
                InstructorNames = seg.InstructorNames,
                ExceptionDates = seg.ExceptionDates,
                MeetingLink = seg.MeetingLink,
                Kind = "Exam"
            };
        }
    }
}

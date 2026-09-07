using Microsoft.AspNetCore.Mvc;
using System.Text.Json;
using Web_Backend.Areas.Admin.Data;
using Web_Backend.Areas.Admin.Models;
using Web_Backend.Classes;

namespace Web_Backend.Areas.Admin.Controllers
{
    // Dated/timed sittings for an exam. Mirrors CourseScheduleController,
    // scoped to edu.Exam instead of edu.Course; no calendar-notes concept
    // (out of scope for this phase — see 0028_exam_schedule.sql's header).
    [Area("Admin")]
    public class ExamScheduleController : Controller
    {
        private readonly IExamScheduleData rep;
        private readonly IExamData examRep;
        private readonly IUserData userRep;
        private readonly IHolidayEventData holidayRep;
        private readonly ICourseScheduleData courseScheduleRep;

        public ExamScheduleController(IExamScheduleData rep, IExamData examRep, IUserData userRep, IHolidayEventData holidayRep, ICourseScheduleData courseScheduleRep)
        {
            this.rep = rep;
            this.examRep = examRep;
            this.userRep = userRep;
            this.holidayRep = holidayRep;
            this.courseScheduleRep = courseScheduleRep;
        }

        public async Task<IActionResult> Index(string KeyW = "", string ExamID = "", bool showInactive = false)
        {
            Auth.CheckPermission(PermissionCode.Exams, 'V');
            ViewBag.CurrentUser = Auth.GetUser();
            ViewBag.KeyW = KeyW;
            ViewBag.ExamID = ExamID;
            ViewBag.ShowInactive = showInactive;
            ViewBag.Exams = await examRep.GetList(new ExamSearchView { IsActive = "A" });
            ViewBag.Instructors = await userRep.GetInstructors();
            // Batches (edu.CourseSchedule rows) an exam sitting can optionally
            // be linked to — e.g. a CSCA exam tied to a specific course intake.
            ViewBag.Batches = await courseScheduleRep.GetList(new CourseScheduleSearchView { IsActive = "A" });

            // Calendar tab needs the full unfiltered-by-date set (it does its
            // own month navigation client-side), so KeyW/ExamID/showInactive
            // only affect the List tab's table — same list powers both.
            var list = await rep.GetList(new ExamScheduleSearchView
            {
                KeyW = KeyW,
                ExamID = ExamID,
                IsActive = showInactive ? "" : "A"
            });

            // Same "load everything once, navigate client-side" approach as
            // the schedule list above — a wide static window (today ± 2
            // years) comfortably covers anything the calendar's month/week/
            // day navigation could scroll to without needing a server round
            // trip per view change.
            var today = DateTime.Today;

            // Holidays/events are global (no ScheduleID) and shown as a
            // yellow marker on the same calendar — loaded over the same
            // date window as CourseScheduleController.
            var holidays = await holidayRep.GetByDateRange(today.AddYears(-2), today.AddYears(2));
            ViewBag.Holidays = holidays;

            return View(list);
        }

        public async Task<IActionResult> Details(string id)
        {
            Auth.CheckPermission(PermissionCode.Exams, 'V');
            var schedule = await rep.Get(id);
            if (schedule == null) return NotFound();

            return View(schedule);
        }

        [HttpPost, ValidateAntiForgeryToken]
        public async Task<IActionResult> Save(ExamSchedule form, string SegmentJSON = "[]", string InstructorUserIDsJSON = "[]")
        {
            var isNew = string.IsNullOrEmpty(form.ScheduleID);
            Auth.CheckPermission(PermissionCode.Exams, isNew ? 'A' : 'E');

            if (string.IsNullOrWhiteSpace(form.ExamID))
            {
                TempData["ErrorMessage"] = "Exam is required.";
                return RedirectToAction("Index");
            }

            try
            {
                form.Segments = JsonSerializer.Deserialize<List<ExamScheduleSegment>>(SegmentJSON, new JsonSerializerOptions { PropertyNameCaseInsensitive = true }) ?? new List<ExamScheduleSegment>();
                if (form.Segments.Count == 0)
                {
                    TempData["ErrorMessage"] = "At least one period (date range, days, time) is required.";
                    return RedirectToAction("Index");
                }
                form.Instructors = await ResolveInstructors(InstructorUserIDsJSON);
                form.IsActive = isNew ? "A" : form.IsActive;
                await rep.AddEdit(form);
                TempData["SuccessMessage"] = isNew ? "Schedule created." : "Schedule saved.";
            }
            catch (Exception ex)
            {
                TempData["ErrorMessage"] = "Could not save: " + ex.Message;
            }
            return RedirectToAction("Index");
        }

        // Quick single-period meeting-link edit from the calendar's day
        // popup — narrower than the full Save form.
        [HttpPost, ValidateAntiForgeryToken]
        public async Task<IActionResult> SetSegmentMeetingLink(string segmentId, string meetingLink)
        {
            Auth.CheckPermission(PermissionCode.Exams, 'E');
            try
            {
                await rep.SetSegmentMeetingLink(segmentId, meetingLink ?? "");
                return Json(new { success = true, meetingLink });
            }
            catch (Exception ex)
            {
                return Json(new { success = false, error = ex.Message });
            }
        }

        [HttpPost, ValidateAntiForgeryToken]
        public async Task<IActionResult> Delete(string id)
        {
            Auth.CheckPermission(PermissionCode.Exams, 'D');
            try
            {
                await rep.Delete(id);
                TempData["SuccessMessage"] = "Schedule deleted.";
            }
            catch (Exception ex)
            {
                TempData["ErrorMessage"] = "Could not delete: " + ex.Message;
            }
            return RedirectToAction("Index");
        }

        [HttpPost, ValidateAntiForgeryToken]
        public async Task<IActionResult> Activate(string id)
        {
            Auth.CheckPermission(PermissionCode.Exams, 'E');
            try
            {
                var schedule = await rep.Get(id);
                if (schedule == null)
                {
                    TempData["ErrorMessage"] = "Schedule not found.";
                    return RedirectToAction("Index");
                }
                schedule.IsActive = "A";
                await rep.AddEdit(schedule);
                TempData["SuccessMessage"] = "Schedule activated.";
            }
            catch (Exception ex)
            {
                TempData["ErrorMessage"] = "Could not activate: " + ex.Message;
            }
            return RedirectToAction("Index", new { showInactive = true });
        }

        // The instructor picker posts back bare UserID strings (the widget
        // already has FullName client-side for rendering pills, so there's
        // no need to round-trip it); look FullName up here so
        // ExamSchedule.Instructors is fully populated for InstructorsLabel
        // etc. even before the next page load re-fetches from the DB. Copied
        // verbatim from CourseScheduleController — it's course-agnostic.
        private async Task<List<ScheduleInstructor>> ResolveInstructors(string instructorUserIDsJSON)
        {
            var ids = JsonSerializer.Deserialize<List<string>>(instructorUserIDsJSON, new JsonSerializerOptions { PropertyNameCaseInsensitive = true }) ?? new List<string>();
            if (ids.Count == 0) return new List<ScheduleInstructor>();

            var instructors = await userRep.GetInstructors();
            return ids
                .Select(id => instructors.FirstOrDefault(u => u.UserID == id))
                .Where(u => u != null)
                .Select(u => new ScheduleInstructor { UserID = u!.UserID, FullName = u.FullName })
                .ToList();
        }
    }
}

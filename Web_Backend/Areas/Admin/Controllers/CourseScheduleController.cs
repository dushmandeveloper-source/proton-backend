using Microsoft.AspNetCore.Mvc;
using System.Text.Json;
using Web_Backend.Areas.Admin.Data;
using Web_Backend.Areas.Admin.Models;
using Web_Backend.Classes;

namespace Web_Backend.Areas.Admin.Controllers
{
    // Dated/timed batches (course intakes, or CSCA exam sessions) for a
    // course. Kept as its own module rather than a Course tab because
    // schedules are commonly filtered/browsed across all courses at once
    // (e.g. "what's coming up in the next 30 days").
    [Area("Admin")]
    public class CourseScheduleController : Controller
    {
        private readonly ICourseScheduleData rep;
        private readonly ICourseData courseRep;
        private readonly IUserData userRep;
        private readonly ICourseScheduleNoteData noteRep;
        private readonly IHolidayEventData holidayRep;

        public CourseScheduleController(ICourseScheduleData rep, ICourseData courseRep, IUserData userRep, ICourseScheduleNoteData noteRep, IHolidayEventData holidayRep)
        {
            this.rep = rep;
            this.courseRep = courseRep;
            this.userRep = userRep;
            this.noteRep = noteRep;
            this.holidayRep = holidayRep;
        }

        public async Task<IActionResult> Index(string KeyW = "", string CourseID = "", bool showInactive = false)
        {
            Auth.CheckPermission(PermissionCode.CourseSchedules, 'V');
            ViewBag.CurrentUser = Auth.GetUser();
            ViewBag.KeyW = KeyW;
            ViewBag.CourseID = CourseID;
            ViewBag.ShowInactive = showInactive;
            ViewBag.Courses = await courseRep.GetList(new CourseSearchView { IsActive = "A" });
            ViewBag.Instructors = await userRep.GetInstructors();

            // Calendar tab needs the full unfiltered-by-date set (it does its
            // own month navigation client-side), so KeyW/CourseID/showInactive
            // only affect the List tab's table — same list powers both.
            var list = await rep.GetList(new CourseScheduleSearchView
            {
                KeyW = KeyW,
                CourseID = CourseID,
                IsActive = showInactive ? "" : "A"
            });

            // Same "load everything once, navigate client-side" approach as
            // the schedule list above — a wide static window (today ± 2
            // years) comfortably covers anything the calendar's month/week/
            // day navigation could scroll to without needing a server round
            // trip per view change.
            var today = DateTime.Today;
            var notes = await noteRep.GetByDateRange(today.AddYears(-2), today.AddYears(2));
            ViewBag.CalendarNotes = notes;

            // Holidays/events are global (no ScheduleID) and shown as a
            // yellow marker on the same calendar — loaded over the same
            // date window as notes above.
            var holidays = await holidayRep.GetByDateRange(today.AddYears(-2), today.AddYears(2));
            ViewBag.Holidays = holidays;

            // Only worth the per-schedule round trip when the delete button
            // is actually rendered — same pattern as CourseController.Index.
            var deleteImpacts = new Dictionary<string, CourseScheduleDeleteImpact>();
            var deletePaymentImpacts = new Dictionary<string, List<CoursePaymentImpact>>();
            if (Auth.HasPermission(PermissionCode.CourseSchedules, 'D'))
            {
                foreach (var schedule in list)
                {
                    var impact = await rep.GetDeleteImpact(schedule.ScheduleID);
                    if (impact == null) continue;
                    deleteImpacts[schedule.ScheduleID] = impact;
                    if (impact.RegistrationCount > 0)
                        deletePaymentImpacts[schedule.ScheduleID] = await rep.GetDeletePaymentImpact(schedule.ScheduleID);
                }
            }
            ViewBag.DeleteImpacts = deleteImpacts;
            ViewBag.DeletePaymentImpacts = deletePaymentImpacts;

            return View(list);
        }

        public async Task<IActionResult> Details(string id)
        {
            Auth.CheckPermission(PermissionCode.CourseSchedules, 'V');
            var schedule = await rep.Get(id);
            if (schedule == null) return NotFound();

            var today = DateTime.Today;
            ViewBag.Notes = await noteRep.GetByDateRange(today.AddYears(-10), today.AddYears(10), id);
            return View(schedule);
        }

        [HttpPost, ValidateAntiForgeryToken]
        public async Task<IActionResult> Save(CourseSchedule form, string SegmentJSON = "[]", string InstructorUserIDsJSON = "[]")
        {
            var isNew = string.IsNullOrEmpty(form.ScheduleID);
            Auth.CheckPermission(PermissionCode.CourseSchedules, isNew ? 'A' : 'E');

            if (string.IsNullOrWhiteSpace(form.CourseID))
            {
                TempData["ErrorMessage"] = "Course is required.";
                return RedirectToAction("Index");
            }

            try
            {
                form.Segments = JsonSerializer.Deserialize<List<CourseScheduleSegment>>(SegmentJSON, new JsonSerializerOptions { PropertyNameCaseInsensitive = true }) ?? new List<CourseScheduleSegment>();
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
        // popup — narrower than the full Save form, so it doesn't require
        // re-submitting every field of the batch just to fix a link.
        [HttpPost, ValidateAntiForgeryToken]
        public async Task<IActionResult> SetSegmentMeetingLink(string segmentId, string meetingLink)
        {
            Auth.CheckPermission(PermissionCode.CourseSchedules, 'E');
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
        public async Task<IActionResult> Deactivate(string id)
        {
            Auth.CheckPermission(PermissionCode.CourseSchedules, 'D');
            try
            {
                await rep.Deactivate(id);
                TempData["SuccessMessage"] = "Schedule deactivated.";
            }
            catch (Exception ex)
            {
                TempData["ErrorMessage"] = "Could not deactivate: " + ex.Message;
            }
            return RedirectToAction("Index");
        }

        [HttpPost, ValidateAntiForgeryToken]
        public async Task<IActionResult> DeletePermanently(string id)
        {
            Auth.CheckPermission(PermissionCode.CourseSchedules, 'D');
            try
            {
                await rep.DeletePermanently(id);
                TempData["SuccessMessage"] = "Schedule permanently deleted.";
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
            Auth.CheckPermission(PermissionCode.CourseSchedules, 'E');
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

        [HttpPost, ValidateAntiForgeryToken]
        public async Task<IActionResult> SaveNote(CourseScheduleNote form)
        {
            var isNew = string.IsNullOrEmpty(form.NoteID);
            Auth.CheckPermission(PermissionCode.CourseSchedules, isNew ? 'A' : 'E');

            if (string.IsNullOrWhiteSpace(form.NoteText))
            {
                TempData["ErrorMessage"] = "Note text is required.";
                return RedirectToAction("Index");
            }

            try
            {
                form.IsActive = "A";
                await noteRep.AddEdit(form);
                TempData["SuccessMessage"] = isNew ? "Note added." : "Note saved.";
            }
            catch (Exception ex)
            {
                TempData["ErrorMessage"] = "Could not save note: " + ex.Message;
            }
            return RedirectToAction("Index");
        }

        [HttpPost, ValidateAntiForgeryToken]
        public async Task<IActionResult> DeleteNote(string id)
        {
            Auth.CheckPermission(PermissionCode.CourseSchedules, 'D');
            try
            {
                await noteRep.Delete(id);
                TempData["SuccessMessage"] = "Note deleted.";
            }
            catch (Exception ex)
            {
                TempData["ErrorMessage"] = "Could not delete note: " + ex.Message;
            }
            return RedirectToAction("Index");
        }

        // The instructor picker posts back bare UserID strings (the widget
        // already has FullName client-side for rendering pills, so there's
        // no need to round-trip it); look FullName up here so
        // CourseSchedule.Instructors is fully populated for InstructorsLabel
        // etc. even before the next page load re-fetches from the DB.
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

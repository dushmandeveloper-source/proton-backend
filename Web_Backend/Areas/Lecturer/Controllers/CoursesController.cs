using Microsoft.AspNetCore.Mvc;
using System.Text.Json;
using Web_Backend.Areas.Admin.Data;
using Web_Backend.Classes;

namespace Web_Backend.Areas.LecturerPortal.Controllers
{
    // "My Batches" — list + detail per assigned schedule. The detail page
    // shows segment/schedule info and an enrolled-student COUNT ONLY
    // (edu.CourseSchedule_ListForInstructor's EnrolledCount column) — never
    // the full roster or any student PII, per the Lecturer Portal plan's
    // explicit privacy constraint.
    [Area("Lecturer")]
    public class CoursesController : Controller
    {
        private readonly ICourseScheduleData scheduleRep;
        private readonly ILectureMaterialData materialRep;

        public CoursesController(ICourseScheduleData scheduleRep, ILectureMaterialData materialRep)
        {
            this.scheduleRep = scheduleRep;
            this.materialRep = materialRep;
        }

        [HttpGet]
        public async Task<IActionResult> Index()
        {
            Auth.CheckUser();
            var userId = Auth.GetUserId();

            var batches = await scheduleRep.GetListForInstructor(userId);

            ViewBag.CurrentUser = Auth.GetUser();
            return View(batches);
        }

        [HttpGet]
        public async Task<IActionResult> Details(string scheduleId)
        {
            Auth.CheckUser();
            var userId = Auth.GetUserId();

            var batches = await scheduleRep.GetListForInstructor(userId);
            var batch = batches.FirstOrDefault(b => b.ScheduleID == scheduleId);
            if (batch == null)
            {
                TempData["ErrorMessage"] = "Batch not found, or you are not assigned to it.";
                return RedirectToAction("Index");
            }

            var materials = await materialRep.ListForSchedule(scheduleId);
            var roster = await scheduleRep.GetStudentRosterForInstructor(scheduleId, userId);

            ViewBag.CurrentUser = Auth.GetUser();
            ViewBag.Materials = materials;
            ViewBag.Roster = roster;
            return View(batch);
        }

        // Lets the lecturer paste a Zoom/VooV/Teams link once and apply it
        // to a single period or several selected periods of one of their own
        // batches. Ownership (scheduleId belongs to this lecturer) is
        // re-checked in edu.CourseScheduleSegment_UpdateMeetingLinks itself.
        [HttpPost, ValidateAntiForgeryToken]
        public async Task<IActionResult> SetMeetingLink(string scheduleId, string SegmentIDsJSON, string MeetingLink)
        {
            Auth.CheckUser();
            var userId = Auth.GetUserId();

            var segmentIds = JsonSerializer.Deserialize<List<string>>(SegmentIDsJSON ?? "[]",
                new JsonSerializerOptions { PropertyNameCaseInsensitive = true }) ?? new List<string>();

            if (segmentIds.Count == 0)
            {
                TempData["ErrorMessage"] = "Select at least one class date.";
                return RedirectToAction("Details", new { scheduleId });
            }

            try
            {
                await scheduleRep.UpdateSegmentMeetingLinks(scheduleId, userId, segmentIds, MeetingLink ?? "");
                TempData["SuccessMessage"] = "Meeting link saved.";
            }
            catch (Exception ex)
            {
                TempData["ErrorMessage"] = "Could not save meeting link: " + ex.Message;
            }
            return RedirectToAction("Details", new { scheduleId });
        }

        // AJAX counterpart of SetMeetingLink for a single class date — used
        // by the Schedule calendar's day popup and the Dashboard "This
        // Week's Classes" widget, where a full-page redirect back to the
        // batch Details view would lose the caller's current context
        // (selected month, current week). Ownership is still enforced via
        // edu.CourseScheduleSegment_UpdateMeetingLinks.
        [HttpPost, ValidateAntiForgeryToken]
        public async Task<IActionResult> SetSegmentMeetingLink(string scheduleId, string segmentId, string meetingLink)
        {
            Auth.CheckUser();
            var userId = Auth.GetUserId();

            if (string.IsNullOrEmpty(scheduleId) || string.IsNullOrEmpty(segmentId))
                return Json(new { success = false, error = "Missing schedule or segment." });

            try
            {
                await scheduleRep.UpdateSegmentMeetingLinks(scheduleId, userId, new List<string> { segmentId }, meetingLink ?? "");
                return Json(new { success = true, meetingLink });
            }
            catch (Exception ex)
            {
                return Json(new { success = false, error = ex.Message });
            }
        }
    }
}

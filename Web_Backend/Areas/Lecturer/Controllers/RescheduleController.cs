using Microsoft.AspNetCore.Mvc;
using Web_Backend.Areas.Admin.Data;
using Web_Backend.Areas.Admin.Models;
using Web_Backend.Areas.LecturerPortal.Models;
using Web_Backend.Classes;

namespace Web_Backend.Areas.LecturerPortal.Controllers
{
    // A lecturer's own reschedule requests, by status, plus the Create
    // GET/POST flow. Every action is ownership-checked to the lecturer's own
    // assigned schedules — edu.CourseScheduleReschedule_Create re-validates
    // this at the SQL layer too (defense in depth), and its THROW messages
    // are surfaced here as friendly TempData errors rather than a raw 500.
    [Area("Lecturer")]
    public class RescheduleController : Controller
    {
        private readonly ICourseScheduleRescheduleData rescheduleRep;
        private readonly ICourseScheduleData scheduleRep;

        public RescheduleController(ICourseScheduleRescheduleData rescheduleRep, ICourseScheduleData scheduleRep)
        {
            this.rescheduleRep = rescheduleRep;
            this.scheduleRep = scheduleRep;
        }

        [HttpGet]
        public async Task<IActionResult> Index()
        {
            Auth.CheckUser();
            var userId = Auth.GetUserId();

            var requests = await rescheduleRep.ListForLecturer(userId);

            ViewBag.CurrentUser = Auth.GetUser();
            return View(requests);
        }

        [HttpGet]
        public async Task<IActionResult> Create(string scheduleId, string segmentId)
        {
            Auth.CheckUser();
            var userId = Auth.GetUserId();

            var batches = await scheduleRep.GetListForInstructor(userId);
            var batch = batches.FirstOrDefault(b => b.ScheduleID == scheduleId);
            if (batch == null)
            {
                TempData["ErrorMessage"] = "Batch not found, or you are not assigned to it.";
                return RedirectToAction("Index", "Courses");
            }

            var segment = batch.Segments.FirstOrDefault(s => s.SegmentID == segmentId);

            ViewBag.CurrentUser = Auth.GetUser();
            ViewBag.Batches = batches;
            return View(new RescheduleRequestFormModel
            {
                ScheduleID = scheduleId,
                SegmentID = segmentId,
                ScheduleName = batch.ScheduleName,
                CourseTitle = batch.CourseTitle
            });
        }

        [HttpPost, ValidateAntiForgeryToken]
        public async Task<IActionResult> Create(RescheduleRequestFormModel form)
        {
            Auth.CheckUser();
            var userId = Auth.GetUserId();
            ViewBag.CurrentUser = Auth.GetUser();

            if (!ModelState.IsValid || form.OriginalDate == null || form.ProposedNewDate == null)
            {
                TempData["ErrorMessage"] = "Please fill in the required fields.";
                ViewBag.Batches = await scheduleRep.GetListForInstructor(userId);
                return View(form);
            }

            try
            {
                await rescheduleRep.Create(new CourseScheduleReschedule
                {
                    ScheduleID = form.ScheduleID,
                    SegmentID = form.SegmentID,
                    OriginalDate = form.OriginalDate.Value,
                    ProposedNewDate = form.ProposedNewDate.Value,
                    Remark = form.Remark,
                    RequestedByUserID = userId
                });

                TempData["SuccessMessage"] = "Reschedule request submitted — pending admin approval.";
                return RedirectToAction("Index");
            }
            catch (Exception ex)
            {
                // Surfaces edu.CourseScheduleReschedule_Create's THROW
                // messages (not-assigned / duplicate-pending / bad segment)
                // as a friendly inline error rather than a raw 500.
                TempData["ErrorMessage"] = ex.Message;
                ViewBag.Batches = await scheduleRep.GetListForInstructor(userId);
                return View(form);
            }
        }
    }
}

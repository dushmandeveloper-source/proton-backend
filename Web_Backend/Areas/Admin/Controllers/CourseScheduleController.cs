using Microsoft.AspNetCore.Mvc;
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

        public CourseScheduleController(ICourseScheduleData rep, ICourseData courseRep)
        {
            this.rep = rep;
            this.courseRep = courseRep;
        }

        public async Task<IActionResult> Index(string KeyW = "", string CourseID = "", bool showInactive = false)
        {
            Auth.CheckPermission(PermissionCode.CourseSchedules, 'V');
            ViewBag.CurrentUser = Auth.GetUser();
            ViewBag.KeyW = KeyW;
            ViewBag.CourseID = CourseID;
            ViewBag.ShowInactive = showInactive;
            ViewBag.Courses = await courseRep.GetList(new CourseSearchView { IsActive = "A" });

            // Calendar tab needs the full unfiltered-by-date set (it does its
            // own month navigation client-side), so KeyW/CourseID/showInactive
            // only affect the List tab's table — same list powers both.
            var list = await rep.GetList(new CourseScheduleSearchView
            {
                KeyW = KeyW,
                CourseID = CourseID,
                IsActive = showInactive ? "" : "A"
            });
            return View(list);
        }

        [HttpPost, ValidateAntiForgeryToken]
        public async Task<IActionResult> Save(CourseSchedule form)
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

        [HttpPost, ValidateAntiForgeryToken]
        public async Task<IActionResult> Delete(string id)
        {
            Auth.CheckPermission(PermissionCode.CourseSchedules, 'D');
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
    }
}

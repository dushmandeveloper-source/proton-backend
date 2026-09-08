using Microsoft.AspNetCore.Mvc;
using Web_Backend.Areas.Admin.Data;
using Web_Backend.Areas.Admin.Models;
using Web_Backend.Classes;

namespace Web_Backend.Areas.Admin.Controllers
{
    // Global holiday/event dates. Separate module from CourseSchedule
    // because these are not linked to any specific batch (no ScheduleID) —
    // they apply uniformly to every course schedule and are surfaced as a
    // yellow marker on the CourseSchedule calendar (see
    // CourseScheduleController.Index / CourseSchedule/Index.cshtml).
    [Area("Admin")]
    public class HolidayEventController : Controller
    {
        private readonly IHolidayEventData rep;

        public HolidayEventController(IHolidayEventData rep)
        {
            this.rep = rep;
        }

        public async Task<IActionResult> Index(bool showInactive = false)
        {
            Auth.CheckPermission(PermissionCode.HolidayCalendar, 'V');
            ViewBag.CurrentUser = Auth.GetUser();
            ViewBag.ShowInactive = showInactive;

            // Same "load a wide static window, no server-side filtering"
            // approach as CourseScheduleNote — this list is short enough
            // (a handful of holidays/events per year) that client-side
            // display needs no paging.
            var today = DateTime.Today;
            var list = await rep.GetByDateRange(today.AddYears(-2), today.AddYears(2), showInactive);
            return View(list.OrderBy(h => h.HolidayDate).ToList());
        }

        [HttpPost, ValidateAntiForgeryToken]
        public async Task<IActionResult> Save(HolidayEvent form)
        {
            var isNew = string.IsNullOrEmpty(form.HolidayID);
            Auth.CheckPermission(PermissionCode.HolidayCalendar, isNew ? 'A' : 'E');

            if (string.IsNullOrWhiteSpace(form.Title))
            {
                TempData["ErrorMessage"] = "Title is required.";
                return RedirectToAction("Index");
            }

            try
            {
                form.IsActive = "A";
                await rep.AddEdit(form);
                TempData["SuccessMessage"] = isNew ? "Holiday/event added." : "Holiday/event saved.";
            }
            catch (Exception ex)
            {
                TempData["ErrorMessage"] = "Could not save: " + ex.Message;
            }
            return RedirectToAction("Index");
        }

        [HttpPost, ValidateAntiForgeryToken]
        public async Task<IActionResult> Deactivate(string id)
        {
            Auth.CheckPermission(PermissionCode.HolidayCalendar, 'D');
            try
            {
                await rep.Deactivate(id);
                TempData["SuccessMessage"] = "Holiday/event deactivated.";
            }
            catch (Exception ex)
            {
                TempData["ErrorMessage"] = "Could not deactivate: " + ex.Message;
            }
            return RedirectToAction("Index");
        }

        [HttpPost, ValidateAntiForgeryToken]
        public async Task<IActionResult> Activate(string id)
        {
            Auth.CheckPermission(PermissionCode.HolidayCalendar, 'E');
            try
            {
                var holiday = await rep.Get(id);
                if (holiday == null)
                {
                    TempData["ErrorMessage"] = "Holiday/event not found.";
                    return RedirectToAction("Index");
                }
                holiday.IsActive = "A";
                await rep.AddEdit(holiday);
                TempData["SuccessMessage"] = "Holiday/event activated.";
            }
            catch (Exception ex)
            {
                TempData["ErrorMessage"] = "Could not activate: " + ex.Message;
            }
            return RedirectToAction("Index", new { showInactive = true });
        }

        [HttpPost, ValidateAntiForgeryToken]
        public async Task<IActionResult> DeletePermanently(string id)
        {
            Auth.CheckPermission(PermissionCode.HolidayCalendar, 'D');
            try
            {
                await rep.DeletePermanently(id);
                TempData["SuccessMessage"] = "Holiday/event permanently deleted.";
            }
            catch (Exception ex)
            {
                TempData["ErrorMessage"] = ex.Message;
            }
            return RedirectToAction("Index");
        }
    }
}

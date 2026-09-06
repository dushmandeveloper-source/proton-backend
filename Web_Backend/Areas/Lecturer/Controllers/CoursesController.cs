using Microsoft.AspNetCore.Mvc;
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
    }
}

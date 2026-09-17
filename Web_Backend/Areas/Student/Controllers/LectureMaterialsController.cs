using Microsoft.AspNetCore.Mvc;
using Web_Backend.Areas.Admin.Data;
using Web_Backend.Classes;

namespace Web_Backend.Areas.StudentPortal.Controllers
{
    // Cross-course "Lecture Materials" list — every LectureMaterial the
    // student can see tagged Category == "LectureNote". Sibling of
    // HomeworkController/CourseMaterialController: same underlying
    // ListForStudent query, filtered by Category instead of left
    // unfiltered.
    [Area("Student")]
    public class LectureMaterialsController : Controller
    {
        private readonly IStudentData studentRep;
        private readonly ILectureMaterialData materialRep;

        public LectureMaterialsController(IStudentData studentRep, ILectureMaterialData materialRep)
        {
            this.studentRep = studentRep;
            this.materialRep = materialRep;
        }

        [HttpGet]
        public async Task<IActionResult> Index()
        {
            Auth.CheckUser();
            var student = await studentRep.GetByUserID(Auth.GetUserId());
            if (student == null)
                return RedirectToAction("Index", "Dashboard", new { area = "Admin" });

            ViewBag.CurrentUser = Auth.GetUser();

            if (student.IsContentRestricted)
            {
                TempData["ErrorMessage"] = "Your account is still being verified. Course materials unlock once an administrator verifies your account.";
                ViewBag.Restricted = true;
                return View(new List<Admin.Models.LectureMaterial>());
            }

            var all = await materialRep.ListForStudent(student.StudentID);
            var notes = all.Where(m => m.Category != "Homework").OrderByDescending(m => m.MaterialDate).ToList();
            return View(notes);
        }
    }
}

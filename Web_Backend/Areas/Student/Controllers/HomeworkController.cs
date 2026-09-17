using Microsoft.AspNetCore.Mvc;
using Web_Backend.Areas.Admin.Data;
using Web_Backend.Classes;

namespace Web_Backend.Areas.StudentPortal.Controllers
{
    // Cross-course "Homework" list — every LectureMaterial the student can
    // see (across all their enrolled courses/batches) tagged Category ==
    // "Homework". Downloads only: there is no submission/turn-in workflow
    // anywhere in this codebase, this is a file the lecturer posted, same
    // as the combined "Homework / Lecture Materials" section already shown
    // on Courses/Details.cshtml — just surfaced as its own top-level page
    // instead of only reachable per-course.
    [Area("Student")]
    public class HomeworkController : Controller
    {
        private readonly IStudentData studentRep;
        private readonly ILectureMaterialData materialRep;

        public HomeworkController(IStudentData studentRep, ILectureMaterialData materialRep)
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

            // ListForStudent already joins mst.CourseRegistration for
            // ownership — only materials for courses this student is
            // actually enrolled in are ever returned.
            var all = await materialRep.ListForStudent(student.StudentID);
            var homework = all.Where(m => m.Category == "Homework").OrderByDescending(m => m.MaterialDate).ToList();
            return View(homework);
        }
    }
}

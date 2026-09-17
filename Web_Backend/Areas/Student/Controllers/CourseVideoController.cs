using Microsoft.AspNetCore.Mvc;
using Web_Backend.Areas.Admin.Data;
using Web_Backend.Classes;

namespace Web_Backend.Areas.StudentPortal.Controllers
{
    // Cross-course "Course Video" list — every CourseVideo the student can
    // see across all their enrolled courses, unlocked/locked exactly as
    // ICourseVideoData.ListForStudent already resolves (payment-gated per
    // course, same rule as the per-course Details.cshtml section — that
    // gate is untouched here, only surfaced as its own top-level page).
    [Area("Student")]
    public class CourseVideoController : Controller
    {
        private readonly IStudentData studentRep;
        private readonly ICourseVideoData videoRep;

        public CourseVideoController(IStudentData studentRep, ICourseVideoData videoRep)
        {
            this.studentRep = studentRep;
            this.videoRep = videoRep;
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
                TempData["ErrorMessage"] = "Your account is still being verified. Course videos unlock once an administrator verifies your account.";
                ViewBag.Restricted = true;
                return View(new List<Admin.Models.CourseVideo>());
            }

            var videos = await videoRep.ListForStudent(student.StudentID);
            return View(videos.OrderByDescending(v => v.CreatedDate).ToList());
        }
    }
}

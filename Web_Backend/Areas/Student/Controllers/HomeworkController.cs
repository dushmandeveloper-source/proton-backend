using Microsoft.AspNetCore.Mvc;
using Web_Backend.Areas.Admin.Data;
using Web_Backend.Areas.Admin.Models;
using Web_Backend.Classes;

namespace Web_Backend.Areas.StudentPortal.Controllers
{
    // Cross-course "Homework" list — every LectureMaterial the student can
    // see (across all their enrolled courses/batches) tagged Category ==
    // "Homework", same as the combined "Homework / Lecture Materials"
    // section already shown on Courses/Details.cshtml — just surfaced as
    // its own top-level page instead of only reachable per-course. Also
    // handles the student's own answer-file submission (edu.HomeworkSubmission,
    // migration 0072) — one file per homework item, resubmission allowed.
    [Area("Student")]
    public class HomeworkController : Controller
    {
        private const string SubmissionFolder = "HomeworkSubmissions";
        private static readonly string[] AllowedExtensions =
        {
            ".pdf", ".doc", ".docx", ".ppt", ".pptx", ".xls", ".xlsx",
            ".jpg", ".jpeg", ".png", ".gif", ".svg", ".webp", ".mp4", ".mov", ".webm"
        };
        private const long MaxBytes = 100 * 1024 * 1024;

        private readonly IStudentData studentRep;
        private readonly ILectureMaterialData materialRep;
        private readonly IHomeworkSubmissionData submissionRep;
        private readonly IImageUploader uploader;

        public HomeworkController(IStudentData studentRep, ILectureMaterialData materialRep, IHomeworkSubmissionData submissionRep, IImageUploader uploader)
        {
            this.studentRep = studentRep;
            this.materialRep = materialRep;
            this.submissionRep = submissionRep;
            this.uploader = uploader;
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
                return View(new List<LectureMaterial>());
            }

            // ListForStudent already joins mst.CourseRegistration for
            // ownership — only materials for courses this student is
            // actually enrolled in are ever returned.
            var all = await materialRep.ListForStudent(student.StudentID);
            var homework = all.Where(m => m.Category == "Homework").OrderByDescending(m => m.MaterialDate).ToList();

            var submissions = await submissionRep.ListForStudent(student.StudentID);
            ViewBag.Submissions = submissions.ToDictionary(s => s.MaterialID);

            return View(homework);
        }

        [HttpPost, ValidateAntiForgeryToken]
        [RequestFormLimits(MultipartBodyLengthLimit = 110_000_000)]
        [RequestSizeLimit(110_000_000)]
        public async Task<IActionResult> Submit(string materialId, IFormFile? file)
        {
            Auth.CheckUser();
            var student = await studentRep.GetByUserID(Auth.GetUserId());
            if (student == null)
                return RedirectToAction("Index", "Dashboard", new { area = "Admin" });

            if (string.IsNullOrWhiteSpace(materialId) || file == null)
            {
                TempData["ErrorMessage"] = "Please choose a file to submit.";
                return RedirectToAction("Index");
            }

            try
            {
                var fileUrl = await uploader.SaveMediaAsync(file, SubmissionFolder, AllowedExtensions, MaxBytes);
                if (fileUrl == null)
                {
                    TempData["ErrorMessage"] = "Please choose a file to submit.";
                    return RedirectToAction("Index");
                }

                await submissionRep.Upsert(materialId, student.StudentID, fileUrl);
                TempData["SuccessMessage"] = "Homework submitted.";
            }
            catch (InvalidOperationException ex)
            {
                TempData["ErrorMessage"] = ex.Message;
            }
            catch (Exception ex)
            {
                TempData["ErrorMessage"] = "Could not submit: " + ex.Message;
            }

            return RedirectToAction("Index");
        }
    }
}

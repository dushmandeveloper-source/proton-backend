using Microsoft.AspNetCore.Http.Features;
using Microsoft.AspNetCore.Mvc;
using Web_Backend.Areas.Admin.Data;
using Web_Backend.Areas.Admin.Models;
using Web_Backend.Areas.LecturerPortal.Models;
using Web_Backend.Classes;

namespace Web_Backend.Areas.LecturerPortal.Controllers
{
    // Lecture notes/materials upload — own uploads and batch notes, scoped
    // to the lecturer's own assigned schedules (ownership-checked the same
    // way RescheduleController checks batch assignment). Delete removes only
    // the lecturer's own uploads, never an admin's.
    [Area("Lecturer")]
    public class NotesController : Controller
    {
        private const string UploadFolder = "LectureNotes";

        // Section F: .pdf .doc .docx .ppt .pptx .xls .xlsx .jpg .jpeg .png
        // .gif .svg .webp .mp4 .mov .webm, 100 MB cap.
        private static readonly string[] AllowedExtensions =
        {
            ".pdf", ".doc", ".docx", ".ppt", ".pptx", ".xls", ".xlsx",
            ".jpg", ".jpeg", ".png", ".gif", ".svg", ".webp", ".mp4", ".mov", ".webm"
        };
        private const long MaxBytes = 100 * 1024 * 1024;

        private readonly ICourseScheduleData scheduleRep;
        private readonly ILectureMaterialData materialRep;
        private readonly IHomeworkSubmissionData submissionRep;
        private readonly IImageUploader uploader;

        public NotesController(ICourseScheduleData scheduleRep, ILectureMaterialData materialRep, IHomeworkSubmissionData submissionRep, IImageUploader uploader)
        {
            this.scheduleRep = scheduleRep;
            this.materialRep = materialRep;
            this.submissionRep = submissionRep;
            this.uploader = uploader;
        }

        [HttpGet]
        public async Task<IActionResult> Index()
        {
            Auth.CheckUser();
            var userId = Auth.GetUserId();

            var materials = await materialRep.ListForLecturer(userId);

            ViewBag.CurrentUser = Auth.GetUser();
            return View(materials);
        }

        [HttpGet]
        public async Task<IActionResult> Upload(string? scheduleId)
        {
            Auth.CheckUser();
            var userId = Auth.GetUserId();

            var batches = await scheduleRep.GetListForInstructor(userId);
            if (batches.Count == 0)
            {
                TempData["ErrorMessage"] = "You are not assigned to any batches yet.";
                return RedirectToAction("Index");
            }

            // No batch pre-selected (e.g. "Upload New" from the Notes list) —
            // default to the lecturer's first batch; the form itself has a
            // batch picker so they can switch without leaving the page.
            var batch = batches.FirstOrDefault(b => b.ScheduleID == scheduleId) ?? batches[0];

            ViewBag.CurrentUser = Auth.GetUser();
            ViewBag.Batches = batches;
            return View(new LectureMaterialFormModel
            {
                ScheduleID = batch.ScheduleID,
                ScheduleName = batch.ScheduleName,
                CourseTitle = batch.CourseTitle
            });
        }

        [HttpPost, ValidateAntiForgeryToken]
        [RequestFormLimits(MultipartBodyLengthLimit = 110_000_000)]
        [RequestSizeLimit(110_000_000)]
        public async Task<IActionResult> Upload(LectureMaterialFormModel form, IFormFile? file)
        {
            Auth.CheckUser();
            var userId = Auth.GetUserId();
            ViewBag.CurrentUser = Auth.GetUser();

            var batches = await scheduleRep.GetListForInstructor(userId);
            var batch = batches.FirstOrDefault(b => b.ScheduleID == form.ScheduleID);
            if (batch == null)
            {
                TempData["ErrorMessage"] = "Batch not found, or you are not assigned to it.";
                return RedirectToAction("Index", "Courses");
            }

            if (!ModelState.IsValid || form.MaterialDate == null || file == null)
            {
                TempData["ErrorMessage"] = file == null ? "Please choose a file to upload." : "Please fill in the required fields.";
                ViewBag.Batches = batches;
                return View(form);
            }

            try
            {
                var fileUrl = await uploader.SaveMediaAsync(file, UploadFolder, AllowedExtensions, MaxBytes);
                if (fileUrl == null)
                {
                    TempData["ErrorMessage"] = "Please choose a file to upload.";
                    ViewBag.Batches = batches;
                    return View(form);
                }

                var ext = Path.GetExtension(file.FileName).ToLowerInvariant();
                var fileType = ext switch
                {
                    ".jpg" or ".jpeg" or ".png" or ".webp" => "Image",
                    ".mp4" or ".mov" or ".webm" => "Video",
                    _ => "Document"
                };

                await materialRep.AddEdit(new LectureMaterial
                {
                    ScheduleID = form.ScheduleID,
                    SegmentID = string.IsNullOrWhiteSpace(form.SegmentID) ? null : form.SegmentID,
                    MaterialDate = form.MaterialDate.Value,
                    Title = form.Title,
                    Description = form.Description,
                    FileType = fileType,
                    FileURL = fileUrl,
                    Category = form.Category == "Homework" ? "Homework" : "LectureNote",
                    AllowDownload = form.AllowDownload,
                    UploadedByUserID = userId,
                    UploadedByRole = "Lecturer"
                });

                TempData["SuccessMessage"] = "Lecture material uploaded.";
                return RedirectToAction("Index");
            }
            catch (InvalidOperationException ex)
            {
                // SaveMediaAsync's own validation errors (bad extension / too large).
                TempData["ErrorMessage"] = ex.Message;
                ViewBag.Batches = batches;
                return View(form);
            }
            catch (Exception ex)
            {
                TempData["ErrorMessage"] = "Could not upload: " + ex.Message;
                ViewBag.Batches = batches;
                return View(form);
            }
        }

        [HttpGet]
        public async Task<IActionResult> Submissions(string materialId)
        {
            Auth.CheckUser();
            var userId = Auth.GetUserId();

            // Ownership check: the lecturer can only view submissions for a
            // homework item on a batch they're actually assigned to — same
            // scoping ListForLecturer already applies for the Index list.
            var assigned = await materialRep.ListForLecturer(userId);
            var material = assigned.FirstOrDefault(m => m.MaterialID == materialId && m.Category == "Homework");
            if (material == null)
            {
                TempData["ErrorMessage"] = "Homework item not found, or you are not assigned to its batch.";
                return RedirectToAction("Index");
            }

            var submissions = await submissionRep.ListForMaterial(materialId);
            ViewBag.Material = material;
            ViewBag.CurrentUser = Auth.GetUser();
            return View(submissions);
        }

        [HttpPost, ValidateAntiForgeryToken]
        public async Task<IActionResult> Grade(string submissionId, string materialId, decimal? marksAwarded, string? feedback)
        {
            Auth.CheckUser();
            var userId = Auth.GetUserId();

            var assigned = await materialRep.ListForLecturer(userId);
            var material = assigned.FirstOrDefault(m => m.MaterialID == materialId && m.Category == "Homework");
            if (material == null)
            {
                TempData["ErrorMessage"] = "Homework item not found, or you are not assigned to its batch.";
                return RedirectToAction("Index");
            }

            try
            {
                await submissionRep.Grade(submissionId, marksAwarded, feedback, userId);
                TempData["SuccessMessage"] = "Submission graded.";
            }
            catch (Exception ex)
            {
                TempData["ErrorMessage"] = "Could not save grade: " + ex.Message;
            }

            return RedirectToAction("Submissions", new { materialId });
        }

        [HttpPost, ValidateAntiForgeryToken]
        public async Task<IActionResult> RequestResubmission(string submissionId, string materialId, string? remark)
        {
            Auth.CheckUser();
            var userId = Auth.GetUserId();

            var assigned = await materialRep.ListForLecturer(userId);
            var material = assigned.FirstOrDefault(m => m.MaterialID == materialId && m.Category == "Homework");
            if (material == null)
            {
                TempData["ErrorMessage"] = "Homework item not found, or you are not assigned to its batch.";
                return RedirectToAction("Index");
            }

            try
            {
                await submissionRep.RequestResubmission(submissionId, remark);
                TempData["SuccessMessage"] = "Resubmission requested.";
            }
            catch (Exception ex)
            {
                TempData["ErrorMessage"] = "Could not request resubmission: " + ex.Message;
            }

            return RedirectToAction("Submissions", new { materialId });
        }

        [HttpPost, ValidateAntiForgeryToken]
        public async Task<IActionResult> Delete(string id)
        {
            Auth.CheckUser();
            var userId = Auth.GetUserId();

            // Ownership check: only ever delete the lecturer's own uploads,
            // never an admin's, even for a batch the lecturer is assigned to.
            var own = await materialRep.ListForLecturer(userId);
            var material = own.FirstOrDefault(m => m.MaterialID == id && m.UploadedByUserID == userId);
            if (material == null)
            {
                TempData["ErrorMessage"] = "Material not found, or it isn't yours to delete.";
                return RedirectToAction("Index");
            }

            try
            {
                await materialRep.Delete(id);
                TempData["SuccessMessage"] = "Lecture material deleted.";
            }
            catch (Exception ex)
            {
                TempData["ErrorMessage"] = "Could not delete: " + ex.Message;
            }

            return RedirectToAction("Index");
        }
    }
}

using Microsoft.AspNetCore.Mvc;
using Web_Backend.Areas.Admin.Data;
using Web_Backend.Areas.Admin.Models;
using Web_Backend.Classes;

namespace Web_Backend.Areas.Admin.Controllers
{
    // Admin browse of every lecture material across every batch
    // (edu.LectureMaterial_ListAll — unscoped, gated by PermissionCode
    // .LectureNotes only, no SQL-level restriction). Admins can also upload
    // here directly (UploadedByRole = "Admin"), same file-type/size limits
    // as the Lecturer portal's NotesController.
    [Area("Admin")]
    public class LectureNoteController : Controller
    {
        private const string UploadFolder = "LectureNotes";
        private static readonly string[] AllowedExtensions =
        {
            ".pdf", ".doc", ".docx", ".ppt", ".pptx", ".xls", ".xlsx",
            ".jpg", ".jpeg", ".png", ".webp", ".mp4", ".mov", ".webm"
        };
        private const long MaxBytes = 100 * 1024 * 1024;

        private readonly ILectureMaterialData materialRep;
        private readonly ICourseScheduleData scheduleRep;
        private readonly IImageUploader uploader;

        public LectureNoteController(ILectureMaterialData materialRep, ICourseScheduleData scheduleRep, IImageUploader uploader)
        {
            this.materialRep = materialRep;
            this.scheduleRep = scheduleRep;
            this.uploader = uploader;
        }

        public async Task<IActionResult> Index()
        {
            Auth.CheckPermission(PermissionCode.LectureNotes, 'V');
            ViewBag.CurrentUser = Auth.GetUser();

            var list = await materialRep.ListAll();
            ViewBag.Batches = await scheduleRep.GetList(new CourseScheduleSearchView { IsActive = "A" });
            return View(list);
        }

        [HttpPost, ValidateAntiForgeryToken]
        [RequestFormLimits(MultipartBodyLengthLimit = 110_000_000)]
        [RequestSizeLimit(110_000_000)]
        public async Task<IActionResult> Upload(string scheduleId, string segmentId, DateTime materialDate, string title, string description, IFormFile? file)
        {
            Auth.CheckPermission(PermissionCode.LectureNotes, 'A');

            if (string.IsNullOrWhiteSpace(scheduleId) || string.IsNullOrWhiteSpace(title) || file == null)
            {
                TempData["ErrorMessage"] = "Batch, title, and file are required.";
                return RedirectToAction("Index");
            }

            try
            {
                var fileUrl = await uploader.SaveMediaAsync(file, UploadFolder, AllowedExtensions, MaxBytes);
                if (fileUrl == null)
                {
                    TempData["ErrorMessage"] = "Please choose a file to upload.";
                    return RedirectToAction("Index");
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
                    ScheduleID = scheduleId,
                    SegmentID = string.IsNullOrWhiteSpace(segmentId) ? null : segmentId,
                    MaterialDate = materialDate,
                    Title = title,
                    Description = description,
                    FileType = fileType,
                    FileURL = fileUrl,
                    UploadedByUserID = Auth.GetUserId(),
                    UploadedByRole = "Admin"
                });

                TempData["SuccessMessage"] = "Lecture material uploaded.";
            }
            catch (InvalidOperationException ex)
            {
                TempData["ErrorMessage"] = ex.Message;
            }
            catch (Exception ex)
            {
                TempData["ErrorMessage"] = "Could not upload: " + ex.Message;
            }

            return RedirectToAction("Index");
        }

        [HttpPost, ValidateAntiForgeryToken]
        public async Task<IActionResult> Delete(string id)
        {
            Auth.CheckPermission(PermissionCode.LectureNotes, 'D');
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

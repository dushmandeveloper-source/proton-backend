using Microsoft.AspNetCore.Http.Features;
using Microsoft.AspNetCore.Mvc;
using Web_Backend.Areas.Admin.Data;
using Web_Backend.Areas.Admin.Models;

namespace Web_Backend.Classes
{
    // Shared Classroom logic for the Admin and Lecturer portals: one screen
    // per batch, listing its modules (edu.BatchModule) and, for the selected
    // module, every lecture note / homework / assignment / video in it.
    // Subclasses decide who may see/edit which batches; everything else --
    // uploads, links, module CRUD -- is identical, so it lives here once.
    // Each area has thin Classroom/Index + Batch views that render the shared
    // partials in /Views/Shared/Classroom/.
    public abstract class ClassroomStaffController : Controller
    {
        private const string UploadFolder = "LectureNotes";
        private static readonly string[] AllowedExtensions =
        {
            ".pdf", ".doc", ".docx", ".ppt", ".pptx", ".xls", ".xlsx",
            ".jpg", ".jpeg", ".png", ".gif", ".svg", ".webp", ".mp4", ".mov", ".webm"
        };
        private const long MaxBytes = 100 * 1024 * 1024;
        private static readonly string[] Categories = { "LectureNote", "Homework", "Assignment", "Video" };

        protected readonly ICourseScheduleData scheduleRep;
        protected readonly IBatchModuleData moduleRep;
        protected readonly ILectureMaterialData materialRep;
        private readonly IImageUploader uploader;

        protected ClassroomStaffController(ICourseScheduleData scheduleRep, IBatchModuleData moduleRep, ILectureMaterialData materialRep, IImageUploader uploader)
        {
            this.scheduleRep = scheduleRep;
            this.moduleRep = moduleRep;
            this.materialRep = materialRep;
            this.uploader = uploader;
        }

        // 'Admin' | 'Lecturer' -- stored as UploadedByRole.
        protected abstract string Role { get; }

        // Controller that hosts the existing Submissions/Grade screens.
        protected abstract string SubmissionsController { get; }

        protected abstract void CheckView();
        protected abstract void CheckEdit();
        protected abstract bool CanEdit();

        // Batches the current user may open.
        protected abstract Task<List<CourseSchedule>> GetBatches();

        // Whether the current user may delete this item (lecturers: own only).
        protected abstract bool CanDeleteItem(LectureMaterial item);

        private async Task<CourseSchedule?> FindBatch(string? scheduleId)
        {
            if (string.IsNullOrWhiteSpace(scheduleId)) return null;
            var batches = await GetBatches();
            return batches.FirstOrDefault(b => b.ScheduleID == scheduleId);
        }

        [HttpGet]
        public async Task<IActionResult> Index()
        {
            CheckView();
            ViewBag.CurrentUser = Auth.GetUser();
            var batches = await GetBatches();
            return View("Index", batches);
        }

        [HttpGet]
        public async Task<IActionResult> Batch(string id, string? module)
        {
            CheckView();
            var batch = await FindBatch(id);
            if (batch == null)
            {
                TempData["ErrorMessage"] = "Batch not found, or you don't have access to it.";
                return RedirectToAction("Index");
            }

            var modules = await moduleRep.List(id);
            var all = await materialRep.ListForSchedule(id);

            // Default to the first module; fall back to General.
            var selected = string.IsNullOrEmpty(module)
                ? modules.FirstOrDefault()?.ModuleID
                : module == "general" ? null : modules.FirstOrDefault(m => m.ModuleID == module)?.ModuleID;

            var vm = new ClassroomViewModel
            {
                Batch = batch,
                Modules = modules,
                SelectedModuleID = selected,
                GeneralCount = all.Count(m => string.IsNullOrEmpty(m.ModuleID)),
                Items = all.Where(m => (m.ModuleID ?? "") == (selected ?? "")).OrderBy(m => m.MaterialDate).ThenBy(m => m.CreatedDate).ToList(),
                CanEdit = CanEdit(),
                CurrentUserID = Auth.GetUserId()
            };

            ViewBag.CurrentUser = Auth.GetUser();
            ViewBag.SubmissionsController = SubmissionsController;
            ViewBag.CanDeleteItem = (Func<LectureMaterial, bool>)CanDeleteItem;
            return View("Batch", vm);
        }

        [HttpPost, ValidateAntiForgeryToken]
        public async Task<IActionResult> SaveModule(string scheduleId, string? moduleId, string moduleName, string? icon, DateTime? moduleDate, string? description)
        {
            CheckEdit();
            if (await FindBatch(scheduleId) == null)
            {
                TempData["ErrorMessage"] = "Batch not found, or you don't have access to it.";
                return RedirectToAction("Index");
            }

            try
            {
                var id = await moduleRep.AddEdit(new BatchModule
                {
                    ModuleID = moduleId ?? "",
                    ScheduleID = scheduleId,
                    ModuleName = (moduleName ?? "").Trim(),
                    Icon = BatchModule.IconChoices.Contains(icon) ? icon! : "book-open",
                    ModuleDate = moduleDate,
                    Description = description,
                    CreatedByUserID = Auth.GetUserId()
                });
                TempData["SuccessMessage"] = string.IsNullOrEmpty(moduleId) ? "Module added." : "Module updated.";
                return RedirectToAction("Batch", new { id = scheduleId, module = id });
            }
            catch (Exception ex)
            {
                TempData["ErrorMessage"] = "Could not save module: " + ex.Message;
                return RedirectToAction("Batch", new { id = scheduleId, module = moduleId });
            }
        }

        [HttpPost, ValidateAntiForgeryToken]
        public async Task<IActionResult> DeleteModule(string scheduleId, string moduleId)
        {
            CheckEdit();
            if (await FindBatch(scheduleId) == null)
            {
                TempData["ErrorMessage"] = "Batch not found, or you don't have access to it.";
                return RedirectToAction("Index");
            }

            var modules = await moduleRep.List(scheduleId);
            if (!modules.Any(m => m.ModuleID == moduleId))
            {
                TempData["ErrorMessage"] = "Module not found in this batch.";
                return RedirectToAction("Batch", new { id = scheduleId });
            }

            try
            {
                await moduleRep.Delete(moduleId);
                TempData["SuccessMessage"] = "Module removed. Its items were moved to General.";
            }
            catch (Exception ex)
            {
                TempData["ErrorMessage"] = "Could not remove module: " + ex.Message;
            }
            return RedirectToAction("Batch", new { id = scheduleId });
        }

        [HttpPost, ValidateAntiForgeryToken]
        [RequestFormLimits(MultipartBodyLengthLimit = 110_000_000)]
        [RequestSizeLimit(110_000_000)]
        public async Task<IActionResult> AddItem(string scheduleId, string? moduleId, string category, string title, string? description,
            DateTime? materialDate, DateTime? dueDate, decimal? maxMarks, bool allowDownload, string? sourceType, string? linkUrl, IFormFile? file)
        {
            CheckEdit();
            var back = RedirectToAction("Batch", new { id = scheduleId, module = string.IsNullOrEmpty(moduleId) ? "general" : moduleId });

            if (await FindBatch(scheduleId) == null)
            {
                TempData["ErrorMessage"] = "Batch not found, or you don't have access to it.";
                return RedirectToAction("Index");
            }
            if (string.IsNullOrWhiteSpace(title))
            {
                TempData["ErrorMessage"] = "Title is required.";
                return back;
            }
            if (!Categories.Contains(category)) category = "LectureNote";

            try
            {
                string fileUrl;
                string fileType;
                if (sourceType == "Link")
                {
                    if (!Uri.TryCreate((linkUrl ?? "").Trim(), UriKind.Absolute, out var uri) || (uri.Scheme != Uri.UriSchemeHttp && uri.Scheme != Uri.UriSchemeHttps))
                    {
                        TempData["ErrorMessage"] = "Please enter a valid http(s) link.";
                        return back;
                    }
                    fileUrl = uri.ToString();
                    fileType = "Link";
                }
                else
                {
                    var saved = await uploader.SaveMediaAsync(file, UploadFolder, AllowedExtensions, MaxBytes);
                    if (saved == null)
                    {
                        TempData["ErrorMessage"] = "Please choose a file to upload, or switch to a link.";
                        return back;
                    }
                    fileUrl = saved;
                    fileType = Path.GetExtension(file!.FileName).ToLowerInvariant() switch
                    {
                        ".jpg" or ".jpeg" or ".png" or ".webp" or ".gif" or ".svg" => "Image",
                        ".mp4" or ".mov" or ".webm" => "Video",
                        _ => "Document"
                    };
                }

                await materialRep.AddEdit(new LectureMaterial
                {
                    ScheduleID = scheduleId,
                    ModuleID = string.IsNullOrEmpty(moduleId) ? null : moduleId,
                    MaterialDate = materialDate ?? SriLankaTime.Now.Date,
                    Title = title.Trim(),
                    Description = description,
                    FileType = fileType,
                    FileURL = fileUrl,
                    Category = category,
                    AllowDownload = allowDownload,
                    DueDate = dueDate,
                    MaxMarks = maxMarks,
                    UploadedByUserID = Auth.GetUserId(),
                    UploadedByRole = Role
                });
                TempData["SuccessMessage"] = "Added.";
            }
            catch (InvalidOperationException ex)
            {
                TempData["ErrorMessage"] = ex.Message;
            }
            catch (Exception ex)
            {
                TempData["ErrorMessage"] = "Could not add: " + ex.Message;
            }
            return back;
        }

        [HttpPost, ValidateAntiForgeryToken]
        public async Task<IActionResult> DeleteItem(string scheduleId, string id, string? moduleId)
        {
            CheckEdit();
            var back = RedirectToAction("Batch", new { id = scheduleId, module = string.IsNullOrEmpty(moduleId) ? "general" : moduleId });

            if (await FindBatch(scheduleId) == null)
            {
                TempData["ErrorMessage"] = "Batch not found, or you don't have access to it.";
                return RedirectToAction("Index");
            }

            var item = (await materialRep.ListForSchedule(scheduleId)).FirstOrDefault(m => m.MaterialID == id);
            if (item == null || !CanDeleteItem(item))
            {
                TempData["ErrorMessage"] = "Item not found, or it isn't yours to delete.";
                return back;
            }

            try
            {
                await materialRep.Delete(id);
                TempData["SuccessMessage"] = "Deleted.";
            }
            catch (Exception ex)
            {
                TempData["ErrorMessage"] = "Could not delete: " + ex.Message;
            }
            return back;
        }
    }
}

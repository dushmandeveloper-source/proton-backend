using Microsoft.AspNetCore.Mvc;
using Web_Backend.Areas.Admin.Data;
using Web_Backend.Classes;

namespace Web_Backend.Areas.StudentPortal.Controllers
{
    // Student-facing view of documents an admin has requested from them
    // (edu... actually mst.DocumentRequest/DocumentRequestItem, Database/
    // migrations/0075) -- upload a file against each requested item,
    // locked once approved/rejected unless the admin explicitly reopens it
    // for resubmission (mirrors HomeworkController's submission pattern).
    [Area("Student")]
    public class DocumentRequestController : Controller
    {
        private readonly IStudentData studentRep;
        private readonly IDocumentRequestData requestRep;
        private readonly IDocumentStorage storage;

        public DocumentRequestController(IStudentData studentRep, IDocumentRequestData requestRep, IDocumentStorage storage)
        {
            this.studentRep = studentRep;
            this.requestRep = requestRep;
            this.storage = storage;
        }

        [HttpGet]
        public async Task<IActionResult> Index()
        {
            Auth.CheckUser();
            var student = await studentRep.GetByUserID(Auth.GetUserId());
            if (student == null)
                return RedirectToAction("Index", "Dashboard", new { area = "Admin" });

            ViewBag.CurrentUser = Auth.GetUser();

            var items = await requestRep.ListForStudent(student.StudentID);
            return View(items);
        }

        [HttpPost, ValidateAntiForgeryToken]
        [RequestFormLimits(MultipartBodyLengthLimit = 12_000_000)]
        [RequestSizeLimit(12_000_000)]
        public async Task<IActionResult> Submit(string itemId, IFormFile? file)
        {
            Auth.CheckUser();
            var student = await studentRep.GetByUserID(Auth.GetUserId());
            if (student == null)
                return RedirectToAction("Index", "Dashboard", new { area = "Admin" });

            if (string.IsNullOrWhiteSpace(itemId) || file == null)
            {
                TempData["ErrorMessage"] = "Please choose a file to submit.";
                return RedirectToAction("Index");
            }

            var item = await requestRep.GetItem(itemId);
            if (item == null || item.StudentID != student.StudentID)
            {
                TempData["ErrorMessage"] = "Document request not found.";
                return RedirectToAction("Index");
            }

            try
            {
                var storedFileName = await storage.SaveAsync(file);
                if (storedFileName == null)
                {
                    TempData["ErrorMessage"] = "Please choose a file to submit.";
                    return RedirectToAction("Index");
                }

                await requestRep.Submit(itemId, storedFileName, file.FileName, file.ContentType, Auth.GetUserId(), "Student");
                TempData["SuccessMessage"] = "Document submitted.";
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

        // Own-submission preview/download -- ownership-checked against the
        // signed-in student, same as Submit above.
        [HttpGet]
        public async Task<IActionResult> Download(string itemId)
        {
            Auth.CheckUser();
            var student = await studentRep.GetByUserID(Auth.GetUserId());
            if (student == null) return NotFound();

            var item = await requestRep.GetItem(itemId);
            if (item == null || item.StudentID != student.StudentID || string.IsNullOrEmpty(item.StoredFileName)) return NotFound();

            var stream = await storage.OpenReadAsync(item.StoredFileName);
            if (stream == null) return NotFound();

            return File(stream, string.IsNullOrEmpty(item.ContentType) ? "application/octet-stream" : item.ContentType, item.OriginalFileName ?? "document");
        }

        // Backs the Preview modal's <img>/<iframe> src -- inline
        // disposition, not attachment (see Admin's DocumentRequestController
        // .Preview for why this needs its own action).
        [HttpGet]
        public async Task<IActionResult> Preview(string itemId)
        {
            Auth.CheckUser();
            var student = await studentRep.GetByUserID(Auth.GetUserId());
            if (student == null) return NotFound();

            var item = await requestRep.GetItem(itemId);
            if (item == null || item.StudentID != student.StudentID || string.IsNullOrEmpty(item.StoredFileName)) return NotFound();

            var stream = await storage.OpenReadAsync(item.StoredFileName);
            if (stream == null) return NotFound();

            Response.Headers["Content-Disposition"] = $"inline; filename=\"{item.OriginalFileName}\"";
            return File(stream, string.IsNullOrEmpty(item.ContentType) ? "application/octet-stream" : item.ContentType);
        }
    }
}

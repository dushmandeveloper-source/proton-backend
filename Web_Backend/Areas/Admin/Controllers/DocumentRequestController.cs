using Microsoft.AspNetCore.Mvc;
using Web_Backend.Areas.Admin.Data;
using Web_Backend.Areas.Admin.Models;
using Web_Backend.Classes;

namespace Web_Backend.Areas.Admin.Controllers
{
    // Admin-initiated document requests -- ask one or more students for one
    // or more specific document types, review what they submit (approve/
    // reject with a remark), and reopen an already-decided item for
    // resubmission. See Database/migrations/0075_document_requests.sql for
    // the schema and Classes/DocumentStorage.cs for the private,
    // non-wwwroot file storage (same as the Agent Document Library, 0063 --
    // these are often sensitive personal documents).
    [Area("Admin")]
    public class DocumentRequestController : Controller
    {
        private readonly IDocumentRequestData requestRep;
        private readonly IDocumentTypeData typeRep;
        private readonly IStudentData studentRep;
        private readonly IDocumentStorage storage;

        public DocumentRequestController(IDocumentRequestData requestRep, IDocumentTypeData typeRep, IStudentData studentRep, IDocumentStorage storage)
        {
            this.requestRep = requestRep;
            this.typeRep = typeRep;
            this.studentRep = studentRep;
            this.storage = storage;
        }

        // Lets an admin upload a document directly against a request item --
        // e.g. the admin already has the file in hand (a scanned copy, an
        // emailed attachment) and doesn't need to wait on the student/agent
        // to self-serve. Subject to the same lock as Student/Agent Submit:
        // refused once already Submitted/Approved/Rejected unless a
        // resubmission was requested (mst.DocumentRequestItem_Submit
        // enforces this server-side regardless of caller).
        [HttpPost, ValidateAntiForgeryToken]
        [RequestFormLimits(MultipartBodyLengthLimit = 12_000_000)]
        [RequestSizeLimit(12_000_000)]
        public async Task<IActionResult> Submit(string itemId, string requestId, IFormFile? file)
        {
            Auth.CheckPermission(PermissionCode.DocumentRequests, 'A');

            if (string.IsNullOrWhiteSpace(itemId) || file == null)
            {
                TempData["ErrorMessage"] = "Please choose a file to submit.";
                return RedirectToAction("Details", new { requestId });
            }

            try
            {
                var storedFileName = await storage.SaveAsync(file);
                if (storedFileName == null)
                {
                    TempData["ErrorMessage"] = "Please choose a file to submit.";
                    return RedirectToAction("Details", new { requestId });
                }

                await requestRep.Submit(itemId, storedFileName, file.FileName, file.ContentType, Auth.GetUserId(), "Admin");
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

            return RedirectToAction("Details", new { requestId });
        }

        public async Task<IActionResult> Index()
        {
            Auth.CheckPermission(PermissionCode.DocumentRequests, 'V');
            ViewBag.CurrentUser = Auth.GetUser();

            var list = await requestRep.ListForAdmin();
            return View(list);
        }

        [HttpGet]
        public async Task<IActionResult> New()
        {
            Auth.CheckPermission(PermissionCode.DocumentRequests, 'A');
            ViewBag.CurrentUser = Auth.GetUser();

            ViewBag.Students = await studentRep.GetList(new StudentSearchView { IsActive = "A" });
            ViewBag.Types = await typeRep.List();
            return View();
        }

        [HttpPost, ValidateAntiForgeryToken]
        public async Task<IActionResult> Create(string title, string? instructions, List<string>? studentIds, Dictionary<string, List<string>>? typesByStudent)
        {
            Auth.CheckPermission(PermissionCode.DocumentRequests, 'A');

            if (string.IsNullOrWhiteSpace(title) || studentIds == null || studentIds.Count == 0)
            {
                TempData["ErrorMessage"] = "Title and at least one student are required.";
                return RedirectToAction("New");
            }

            var items = new List<DocumentRequestItemInput>();
            foreach (var studentId in studentIds)
            {
                if (typesByStudent == null || !typesByStudent.TryGetValue(studentId, out var typeIds) || typeIds.Count == 0)
                    continue;
                items.Add(new DocumentRequestItemInput { StudentID = studentId, TypeIDs = typeIds });
            }

            if (items.Count == 0)
            {
                TempData["ErrorMessage"] = "Select at least one document type for at least one student.";
                return RedirectToAction("New");
            }

            try
            {
                await requestRep.Create(title, instructions, Auth.GetUserId(), items);
                TempData["SuccessMessage"] = "Document request sent.";
            }
            catch (Exception ex)
            {
                TempData["ErrorMessage"] = "Could not create request: " + ex.Message;
            }

            return RedirectToAction("Index");
        }

        [HttpGet]
        public async Task<IActionResult> Details(string requestId)
        {
            Auth.CheckPermission(PermissionCode.DocumentRequests, 'V');
            ViewBag.CurrentUser = Auth.GetUser();

            var items = await requestRep.ListForRequest(requestId);
            ViewBag.RequestID = requestId;
            return View(items);
        }

        // Only Admin ever downloads the underlying file -- Student/Agent
        // portals preview inline only, same split as the Agent Document
        // Library's Admin-only Download action.
        [HttpGet]
        public async Task<IActionResult> Download(string itemId)
        {
            Auth.CheckPermission(PermissionCode.DocumentRequests, 'V');

            var item = await requestRep.GetItem(itemId);
            if (item == null || string.IsNullOrEmpty(item.StoredFileName)) return NotFound();

            var stream = await storage.OpenReadAsync(item.StoredFileName);
            if (stream == null) return NotFound();

            return File(stream, string.IsNullOrEmpty(item.ContentType) ? "application/octet-stream" : item.ContentType, item.OriginalFileName ?? "document");
        }

        // Backs the Preview modal's <img>/<iframe> src -- Content-Disposition
        // is explicitly "inline" (never "attachment"), which is what stops
        // the browser treating the response as a download the way Download
        // above deliberately does. Same split as the Agent Document
        // Library's Preview/ViewFile actions.
        [HttpGet]
        public async Task<IActionResult> Preview(string itemId)
        {
            Auth.CheckPermission(PermissionCode.DocumentRequests, 'V');

            var item = await requestRep.GetItem(itemId);
            if (item == null || string.IsNullOrEmpty(item.StoredFileName)) return NotFound();

            var stream = await storage.OpenReadAsync(item.StoredFileName);
            if (stream == null) return NotFound();

            Response.Headers["Content-Disposition"] = $"inline; filename=\"{item.OriginalFileName}\"";
            return File(stream, string.IsNullOrEmpty(item.ContentType) ? "application/octet-stream" : item.ContentType);
        }

        [HttpPost, ValidateAntiForgeryToken]
        public async Task<IActionResult> Review(string itemId, string requestId, bool approve, string? remark)
        {
            Auth.CheckPermission(PermissionCode.DocumentRequests, 'E');

            try
            {
                await requestRep.Review(itemId, approve, remark, Auth.GetUserId());
                TempData["SuccessMessage"] = approve ? "Document approved." : "Document rejected.";
            }
            catch (Exception ex)
            {
                TempData["ErrorMessage"] = "Could not save review: " + ex.Message;
            }

            return RedirectToAction("Details", new { requestId });
        }

        [HttpPost, ValidateAntiForgeryToken]
        public async Task<IActionResult> RequestResubmission(string itemId, string requestId, string? remark)
        {
            Auth.CheckPermission(PermissionCode.DocumentRequests, 'E');

            try
            {
                await requestRep.RequestResubmission(itemId, remark);
                TempData["SuccessMessage"] = "Resubmission requested.";
            }
            catch (Exception ex)
            {
                TempData["ErrorMessage"] = "Could not request resubmission: " + ex.Message;
            }

            return RedirectToAction("Details", new { requestId });
        }

        // ---------- Document Type management (inline tab, same UX as
        // Course's Category tab -- Areas/Admin/Controllers/CourseController.cs) ----------

        [HttpPost, ValidateAntiForgeryToken]
        public async Task<IActionResult> SaveType(string typeId, string typeName, string? description, int sortOrder)
        {
            Auth.CheckPermission(PermissionCode.DocumentRequests, 'A');

            try
            {
                await typeRep.AddEdit(new DocumentType { TypeID = typeId, TypeName = typeName, Description = description, SortOrder = sortOrder });
                TempData["SuccessMessage"] = "Document type saved.";
            }
            catch (Exception ex)
            {
                TempData["ErrorMessage"] = "Could not save document type: " + ex.Message;
            }

            return RedirectToAction("Types");
        }

        [HttpGet]
        public async Task<IActionResult> Types()
        {
            Auth.CheckPermission(PermissionCode.DocumentRequests, 'V');
            ViewBag.CurrentUser = Auth.GetUser();

            var types = await typeRep.List();
            return View(types);
        }

        [HttpPost, ValidateAntiForgeryToken]
        public async Task<IActionResult> DeleteType(string id)
        {
            Auth.CheckPermission(PermissionCode.DocumentRequests, 'D');

            try
            {
                await typeRep.Delete(id);
                TempData["SuccessMessage"] = "Document type deleted.";
            }
            catch (Exception ex)
            {
                TempData["ErrorMessage"] = "Could not delete: " + ex.Message;
            }

            return RedirectToAction("Types");
        }
    }
}

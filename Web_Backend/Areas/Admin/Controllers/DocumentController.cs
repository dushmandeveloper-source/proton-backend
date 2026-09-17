using Microsoft.AspNetCore.Mvc;
using Web_Backend.Areas.Admin.Data;
using Web_Backend.Areas.Admin.Models;
using Web_Backend.Classes;

namespace Web_Backend.Areas.Admin.Controllers
{
    // Admin-managed Documents library — Agents see these read-only, in the
    // Agent portal (Areas/Agent/Controllers/DocumentsController.cs), either
    // because a document is marked visible to "All Agents" or because they
    // were individually picked under "Specific Agents". See
    // Database/migrations/0063_agent_document_library.sql for the schema
    // and Classes/DocumentStorage.cs for why files are stored outside
    // wwwroot (visibility can't be enforced on a plain static-file URL).
    [Area("Admin")]
    public class DocumentController : Controller
    {
        private readonly IDocumentData rep;
        private readonly IAgentData agentRep;
        private readonly IDocumentStorage storage;

        public DocumentController(IDocumentData rep, IAgentData agentRep, IDocumentStorage storage)
        {
            this.rep = rep;
            this.agentRep = agentRep;
            this.storage = storage;
        }

        public async Task<IActionResult> Index()
        {
            Auth.CheckPermission(PermissionCode.Documents, 'V');
            ViewBag.CurrentUser = Auth.GetUser();

            var list = await rep.GetList(new DocumentSearchView { IsActive = "A" });
            return View(list);
        }

        [HttpGet]
        public async Task<IActionResult> Add()
        {
            Auth.CheckPermission(PermissionCode.Documents, 'A');
            ViewBag.CurrentUser = Auth.GetUser();
            await PopulateAgentList();
            return View("Edit", new DocumentFormViewModel { IsActive = "A" });
        }

        [HttpGet]
        public async Task<IActionResult> Edit(string id)
        {
            Auth.CheckPermission(PermissionCode.Documents, 'V');
            ViewBag.CurrentUser = Auth.GetUser();

            var doc = await rep.Get(id);
            if (doc == null)
            {
                TempData["ErrorMessage"] = "Document not found.";
                return RedirectToAction("Index");
            }

            await PopulateAgentList();
            return View(ToForm(doc));
        }

        [HttpGet]
        public async Task<IActionResult> Details(string id)
        {
            Auth.CheckPermission(PermissionCode.Documents, 'V');
            ViewBag.CurrentUser = Auth.GetUser();

            var doc = await rep.Get(id);
            if (doc == null)
            {
                TempData["ErrorMessage"] = "Document not found.";
                return RedirectToAction("Index");
            }
            return View(doc);
        }

        // Only Admin ever downloads the underlying file — the Agent portal
        // is view-only (Areas/Agent/Controllers/DocumentsController.cs's
        // Preview action) and never links here.
        [HttpGet]
        public async Task<IActionResult> Download(string id)
        {
            Auth.CheckPermission(PermissionCode.Documents, 'V');

            var doc = await rep.Get(id);
            if (doc == null) return NotFound();

            var stream = await storage.OpenReadAsync(doc.StoredFileName);
            if (stream == null) return NotFound();

            return File(stream, string.IsNullOrEmpty(doc.ContentType) ? "application/octet-stream" : doc.ContentType, doc.OriginalFileName);
        }

        [HttpPost, ValidateAntiForgeryToken]
        public async Task<IActionResult> Save(DocumentFormViewModel form, IFormFile? file)
        {
            ViewBag.CurrentUser = Auth.GetUser();

            var isNew = string.IsNullOrEmpty(form.DocumentID);
            Auth.CheckPermission(PermissionCode.Documents, isNew ? 'A' : 'E');

            if (string.IsNullOrWhiteSpace(form.Title))
                ModelState.AddModelError(nameof(form.Title), "Title is required.");
            if (isNew && (file == null || file.Length == 0))
                ModelState.AddModelError(nameof(file), "A file is required.");
            if (form.VisibilityScope == "Specific" && form.AgentUserIDs.Count == 0)
                ModelState.AddModelError(nameof(form.AgentUserIDs), "Pick at least one agent, or choose \"All Agents\".");

            if (!ModelState.IsValid)
            {
                await PopulateAgentList();
                return View("Edit", form);
            }

            try
            {
                var existing = isNew ? null : await rep.Get(form.DocumentID);

                var storedFileName = "";
                var originalFileName = "";
                var contentType = "";
                long fileSizeBytes = 0;

                if (file != null && file.Length > 0)
                {
                    storedFileName = await storage.SaveAsync(file) ?? "";
                    originalFileName = file.FileName;
                    contentType = file.ContentType;
                    fileSizeBytes = file.Length;

                    // Replacing an existing file — remove the old one only
                    // after the new one has saved successfully.
                    if (existing != null && !string.IsNullOrEmpty(existing.StoredFileName))
                        storage.Delete(existing.StoredFileName);
                }

                var doc = new Document
                {
                    DocumentID = form.DocumentID,
                    Title = form.Title,
                    Description = form.Description,
                    StoredFileName = storedFileName,
                    OriginalFileName = originalFileName,
                    ContentType = contentType,
                    FileSizeBytes = fileSizeBytes,
                    VisibilityScope = form.VisibilityScope,
                    IsActive = form.IsActive
                };

                var agentUserIds = form.VisibilityScope == "Specific" ? form.AgentUserIDs : new List<string>();
                var id = await rep.AddEdit(doc, agentUserIds, Auth.GetUserId());

                TempData["SuccessMessage"] = isNew ? $"'{form.Title}' added." : $"'{form.Title}' saved.";
                return RedirectToAction("Details", new { id });
            }
            catch (Exception ex)
            {
                TempData["ErrorMessage"] = "Could not save: " + ex.Message;
                await PopulateAgentList();
                return View("Edit", form);
            }
        }

        [HttpPost, ValidateAntiForgeryToken]
        public async Task<IActionResult> Delete(string id)
        {
            Auth.CheckPermission(PermissionCode.Documents, 'D');
            try
            {
                var doc = await rep.Get(id);
                await rep.Delete(id, Auth.GetUserId());
                if (doc != null) storage.Delete(doc.StoredFileName);
                TempData["SuccessMessage"] = "Document deleted.";
            }
            catch (Exception ex)
            {
                TempData["ErrorMessage"] = "Could not delete: " + ex.Message;
            }
            return RedirectToAction("Index");
        }

        // Only approved agents are offered as "Specific Agents" recipients —
        // a Pending agent can't do agent work yet anyway (see
        // Agent.IsContentRestricted), so there's no point pre-assigning them
        // a document before they're approved.
        private async Task PopulateAgentList()
        {
            var agents = await agentRep.GetList(new AgentSearchView { IsActive = "A" });
            ViewBag.AvailableAgents = agents.Where(a => a.AccountVerificationStatus == "Verified").ToList();
        }

        private static DocumentFormViewModel ToForm(Document d) => new()
        {
            DocumentID = d.DocumentID,
            Title = d.Title,
            Description = d.Description,
            VisibilityScope = d.VisibilityScope,
            IsActive = d.IsActive,
            AgentUserIDs = d.AssignedAgents.Select(a => a.UserID).ToList(),
            OriginalFileName = d.OriginalFileName,
            FileSizeBytes = d.FileSizeBytes
        };
    }
}

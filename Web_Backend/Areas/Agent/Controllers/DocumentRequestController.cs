using Microsoft.AspNetCore.Mvc;
using Web_Backend.Areas.Admin.Data;
using Web_Backend.Classes;

namespace Web_Backend.Areas.AgentPortal.Controllers
{
    // Lets an agent submit documents admin has requested from students the
    // agent registered (mst.Student.CreatedByUserID = the agent's own
    // UserID — this codebase's existing agent-scoping convention, see
    // 0058_agent_role_portal.sql). Mirrors Student's own
    // DocumentRequestController.Submit, just scoped differently and
    // stamping SubmittedByRole = "Agent" instead of "Student".
    [Area("Agent")]
    public class DocumentRequestController : Controller
    {
        private readonly IDocumentRequestData requestRep;
        private readonly IDocumentStorage storage;

        public DocumentRequestController(IDocumentRequestData requestRep, IDocumentStorage storage)
        {
            this.requestRep = requestRep;
            this.storage = storage;
        }

        [HttpGet]
        public async Task<IActionResult> Index()
        {
            ViewBag.CurrentUser = Auth.GetUser();
            var items = await requestRep.ListForAgent(Auth.GetUserId());
            return View(items);
        }

        [HttpPost, ValidateAntiForgeryToken]
        [RequestFormLimits(MultipartBodyLengthLimit = 12_000_000)]
        [RequestSizeLimit(12_000_000)]
        public async Task<IActionResult> Submit(string itemId, IFormFile? file)
        {
            var agentUserId = Auth.GetUserId();

            if (string.IsNullOrWhiteSpace(itemId) || file == null)
            {
                TempData["ErrorMessage"] = "Please choose a file to submit.";
                return RedirectToAction("Index");
            }

            var item = await requestRep.GetItem(itemId);
            if (item == null || item.StudentCreatedByUserID != agentUserId)
            {
                TempData["ErrorMessage"] = "Document request not found, or this student wasn't registered by you.";
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

                await requestRep.Submit(itemId, storedFileName, file.FileName, file.ContentType, agentUserId, "Agent");
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

        // Preview/download for one of the agent's own registered students'
        // submissions -- ownership-checked the same way Submit above is.
        [HttpGet]
        public async Task<IActionResult> Download(string itemId)
        {
            var agentUserId = Auth.GetUserId();

            var item = await requestRep.GetItem(itemId);
            if (item == null || item.StudentCreatedByUserID != agentUserId || string.IsNullOrEmpty(item.StoredFileName)) return NotFound();

            var stream = await storage.OpenReadAsync(item.StoredFileName);
            if (stream == null) return NotFound();

            return File(stream, string.IsNullOrEmpty(item.ContentType) ? "application/octet-stream" : item.ContentType, item.OriginalFileName ?? "document");
        }

        // Backs the Preview modal's <img>/<iframe> src -- inline
        // disposition, not attachment.
        [HttpGet]
        public async Task<IActionResult> Preview(string itemId)
        {
            var agentUserId = Auth.GetUserId();

            var item = await requestRep.GetItem(itemId);
            if (item == null || item.StudentCreatedByUserID != agentUserId || string.IsNullOrEmpty(item.StoredFileName)) return NotFound();

            var stream = await storage.OpenReadAsync(item.StoredFileName);
            if (stream == null) return NotFound();

            Response.Headers["Content-Disposition"] = $"inline; filename=\"{item.OriginalFileName}\"";
            return File(stream, string.IsNullOrEmpty(item.ContentType) ? "application/octet-stream" : item.ContentType);
        }
    }
}

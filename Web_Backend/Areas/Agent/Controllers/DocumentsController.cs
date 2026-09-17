using Microsoft.AspNetCore.Mvc;
using Web_Backend.Areas.Admin.Data;
using Web_Backend.Areas.Admin.Models;
using Web_Backend.Classes;

namespace Web_Backend.Areas.AgentPortal.Controllers
{
    // Read-only Documents library for the Agent portal — Admin manages the
    // actual documents (Areas/Admin/Controllers/DocumentController.cs); an
    // agent only ever sees the ones visible to them (mst.Document_ListForAgent
    // / _GetForAgent, scoped server-side) and can PREVIEW but never DOWNLOAD.
    //
    // "No download" is enforced two ways, not just by hiding a button:
    //   1. Preview streams the file with Content-Disposition: inline (never
    //      "attachment"), so a browser renders it rather than saving it.
    //   2. There is no action here that returns the file with a download
    //      disposition, and no such link exists in the view — an agent has
    //      no URL that would produce one.
    // This is a soft control (nothing stops a screenshot, or a browser's own
    // in-viewer save option for a rendered PDF/image), which is the practical
    // ceiling for "view but don't let them download" without DRM.
    [Area("Agent")]
    public class DocumentsController : Controller
    {
        private readonly IDocumentData rep;
        private readonly IDocumentStorage storage;

        public DocumentsController(IDocumentData rep, IDocumentStorage storage)
        {
            this.rep = rep;
            this.storage = storage;
        }

        public async Task<IActionResult> Index()
        {
            ViewBag.CurrentUser = Auth.GetUser();
            var list = await rep.GetListForAgent(Auth.GetUserId());
            return View(list);
        }

        // Renders the doc inline (PDF in an <iframe>, image in an <img>) —
        // Preview.cshtml never surfaces a download link for it.
        [HttpGet]
        public async Task<IActionResult> Preview(string id)
        {
            ViewBag.CurrentUser = Auth.GetUser();

            var doc = await rep.GetForAgent(id, Auth.GetUserId());
            if (doc == null)
            {
                TempData["ErrorMessage"] = "Document not found, or you don't have access to it.";
                return RedirectToAction("Index");
            }

            // Preview.cshtml is typed AgentDocumentView, not the full
            // Document model — an agent's view never needs (or should
            // receive) StoredFileName/CreatedByUserID/etc.
            return View(ToAgentView(doc));
        }

        // The actual byte stream backing Preview's <iframe>/<img> src. Same
        // visibility check as Preview (defense in depth — this URL could be
        // opened directly, bypassing the Preview page). Content-Disposition
        // is explicitly "inline", not "attachment": that's what stops the
        // browser treating the response as a download.
        [HttpGet]
        public async Task<IActionResult> ViewFile(string id)
        {
            var doc = await rep.GetForAgent(id, Auth.GetUserId());
            if (doc == null) return NotFound();

            var stream = await storage.OpenReadAsync(doc.StoredFileName);
            if (stream == null) return NotFound();

            Response.Headers["Content-Disposition"] = $"inline; filename=\"{doc.OriginalFileName}\"";
            return File(stream, string.IsNullOrEmpty(doc.ContentType) ? "application/octet-stream" : doc.ContentType);
        }

        private static AgentDocumentView ToAgentView(Document d) => new()
        {
            DocumentID = d.DocumentID,
            Title = d.Title,
            Description = d.Description,
            OriginalFileName = d.OriginalFileName,
            ContentType = d.ContentType,
            FileSizeBytes = d.FileSizeBytes,
            CreatedDate = d.CreatedDate
        };
    }
}

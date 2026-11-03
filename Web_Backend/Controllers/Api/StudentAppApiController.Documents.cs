using Microsoft.AspNetCore.Mvc;
using Web_Backend.Areas.Admin.Data;
using Web_Backend.Classes;

namespace Web_Backend.Controllers.Api
{
    // Student app: Document Requests. Same storage, sprocs and staff
    // notification as the portal (Student/DocumentRequestController); files
    // are private, so they're only served to their owner through here.
    public partial class StudentAppApiController
    {
        [HttpGet("documents")]
        public async Task<IActionResult> Documents([FromServices] IDocumentRequestData requestRep)
        {
            var student = await CurrentStudent();
            if (student == null) return Unauthorized();
            var items = await requestRep.ListForStudent(student.StudentID);
            return Ok(items.OrderByDescending(i => i.CanSubmit).ThenByDescending(i => i.CreatedDate).Select(i => new
            {
                itemId = i.ItemID,
                requestTitle = i.RequestTitle,
                instructions = i.RequestInstructions ?? "",
                typeName = i.TypeName,
                status = i.Status, // Pending | Submitted | Approved | Rejected
                canSubmit = i.CanSubmit,
                resubmissionRequested = i.ResubmissionRequested,
                resubmissionRemark = i.ResubmissionRemark ?? "",
                reviewRemark = i.ReviewRemark ?? "",
                fileName = i.OriginalFileName ?? "",
                hasFile = !string.IsNullOrEmpty(i.StoredFileName),
                submittedAt = i.SubmittedDate,
                createdAt = i.CreatedDate
            }));
        }

        // Upload (multipart "file"). Only while the item is open for it
        // (pending, or sent back for resubmission).
        [HttpPost("documents/{itemId}")]
        [RequestFormLimits(MultipartBodyLengthLimit = 12_000_000)]
        [RequestSizeLimit(12_000_000)]
        public async Task<IActionResult> SubmitDocument(string itemId, IFormFile? file,
            [FromServices] IDocumentRequestData requestRep, [FromServices] IDocumentStorage storage, [FromServices] NotificationService notifier)
        {
            var student = await CurrentStudent();
            if (student == null) return Unauthorized();
            if (file == null || file.Length == 0) return BadRequest(new { message = "Please choose a file to submit." });
            var item = await requestRep.GetItem(itemId);
            if (item == null || item.StudentID != student.StudentID) return NotFound(new { message = "Document request not found." });
            if (!item.CanSubmit) return Conflict(new { message = "This document has already been submitted." });

            try
            {
                var stored = await storage.SaveAsync(file);
                if (stored == null) return BadRequest(new { message = "Please choose a file to submit." });
                await requestRep.Submit(itemId, stored, file.FileName, file.ContentType, Auth.GetUserId(), "Student");
                await notifier.NotifyStaff(PermissionCode.DocumentRequests, "DocumentSubmitted", "Document submitted",
                    $"{student.FullName} uploaded a requested document.",
                    $"/Admin/DocumentRequest/Details?requestId={Uri.EscapeDataString(item.RequestID)}", itemId);
                return Ok(new { message = "Document submitted." });
            }
            catch (InvalidOperationException ex)
            {
                return BadRequest(new { message = ex.Message }); // type / size
            }
        }

        // The student's own submitted file (private).
        [HttpGet("documents/{itemId}/file")]
        public async Task<IActionResult> DocumentFile(string itemId, [FromServices] IDocumentRequestData requestRep, [FromServices] IDocumentStorage storage)
        {
            var student = await CurrentStudent();
            if (student == null) return Unauthorized();
            var item = await requestRep.GetItem(itemId);
            if (item == null || item.StudentID != student.StudentID || string.IsNullOrEmpty(item.StoredFileName)) return NotFound();
            var stream = await storage.OpenReadAsync(item.StoredFileName);
            if (stream == null) return NotFound();
            return File(stream, string.IsNullOrEmpty(item.ContentType) ? "application/octet-stream" : item.ContentType, item.OriginalFileName ?? "document");
        }
    }
}

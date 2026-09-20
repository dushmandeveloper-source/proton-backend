using Web_Backend.Areas.Admin.Models;

namespace Web_Backend.Areas.Admin.Data
{
    // One (StudentID, list of TypeIDs) pair for DocumentRequest_Create --
    // lets each selected student be asked for a different set of document
    // types within the same request batch.
    public class DocumentRequestItemInput
    {
        public string StudentID { get; set; } = "";
        public List<string> TypeIDs { get; set; } = new();
    }

    public interface IDocumentRequestData
    {
        Task<string> Create(string title, string? instructions, string requestedByUserId, List<DocumentRequestItemInput> items);
        Task<List<DocumentRequest>> ListForAdmin();
        Task<List<DocumentRequestItem>> ListForRequest(string requestId);
        Task<List<DocumentRequestItem>> ListForStudent(string studentId);
        Task<List<DocumentRequestItem>> ListForAgent(string agentUserId);
        Task<DocumentRequestItem?> GetItem(string itemId);
        Task Submit(string itemId, string storedFileName, string originalFileName, string? contentType, string submittedByUserId, string submittedByRole);
        Task Review(string itemId, bool approve, string? remark, string reviewedByUserId);
        Task RequestResubmission(string itemId, string? remark);
    }
}

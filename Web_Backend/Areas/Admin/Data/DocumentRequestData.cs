using System.Text.Json;
using DBAccess;
using Web_Backend.Areas.Admin.Models;
using Web_Backend.Classes;

namespace Web_Backend.Areas.Admin.Data
{
    public class DocumentRequestData : IDocumentRequestData
    {
        private readonly IDBAccess db;

        public DocumentRequestData(IDBAccess db)
        {
            this.db = db;
        }

        public Task<string> Create(string title, string? instructions, string requestedByUserId, List<DocumentRequestItemInput> items) =>
            db.Execute("mst.DocumentRequest_Create", new
            {
                APIKey = AppData.GetAPIKey(),
                Title = title,
                Instructions = instructions ?? "",
                RequestedByUserID = requestedByUserId,
                ItemsJSON = JsonSerializer.Serialize(items)
            });

        public Task<List<DocumentRequest>> ListForAdmin() =>
            db.GetList<DocumentRequest, object>("mst.DocumentRequest_ListForAdmin", new { APIKey = AppData.GetAPIKey() });

        public Task<List<DocumentRequestItem>> ListForRequest(string requestId) =>
            db.GetList<DocumentRequestItem, object>("mst.DocumentRequestItem_ListForRequest", new { APIKey = AppData.GetAPIKey(), RequestID = requestId });

        public Task<List<DocumentRequestItem>> ListForStudent(string studentId) =>
            db.GetList<DocumentRequestItem, object>("mst.DocumentRequestItem_ListForStudent", new { APIKey = AppData.GetAPIKey(), StudentID = studentId });

        public Task<List<DocumentRequestItem>> ListForAgent(string agentUserId) =>
            db.GetList<DocumentRequestItem, object>("mst.DocumentRequestItem_ListForAgent", new { APIKey = AppData.GetAPIKey(), AgentUserID = agentUserId });

        public Task<DocumentRequestItem?> GetItem(string itemId) =>
            db.Get<DocumentRequestItem, object>("mst.DocumentRequestItem_Get", new { APIKey = AppData.GetAPIKey(), ItemID = itemId });

        public Task Submit(string itemId, string storedFileName, string originalFileName, string? contentType, string submittedByUserId, string submittedByRole) =>
            db.ExecuteNonQuery("mst.DocumentRequestItem_Submit", new
            {
                APIKey = AppData.GetAPIKey(),
                ItemID = itemId,
                StoredFileName = storedFileName,
                OriginalFileName = originalFileName,
                ContentType = contentType ?? "",
                SubmittedByUserID = submittedByUserId,
                SubmittedByRole = submittedByRole
            });

        public Task Review(string itemId, bool approve, string? remark, string reviewedByUserId) =>
            db.ExecuteNonQuery("mst.DocumentRequestItem_Review", new
            {
                APIKey = AppData.GetAPIKey(),
                ItemID = itemId,
                Approve = approve,
                Remark = remark ?? "",
                ReviewedByUserID = reviewedByUserId
            });

        public Task RequestResubmission(string itemId, string? remark) =>
            db.ExecuteNonQuery("mst.DocumentRequestItem_RequestResubmission", new
            {
                APIKey = AppData.GetAPIKey(),
                ItemID = itemId,
                Remark = remark ?? ""
            });
    }
}

using System.Text.Json;
using DBAccess;
using Web_Backend.Areas.Admin.Models;
using Web_Backend.Classes;

namespace Web_Backend.Areas.Admin.Data
{
    public class DocumentData : IDocumentData
    {
        private readonly IDBAccess db;

        public DocumentData(IDBAccess db)
        {
            this.db = db;
        }

        public Task<List<Document>> GetList(DocumentSearchView search) =>
            db.GetList<Document, object>("mst.Document_List", new
            {
                APIKey = AppData.GetAPIKey(),
                search.KeyW,
                search.IsActive
            });

        public async Task<Document?> Get(string id)
        {
            var raw = await db.Get<DocumentRaw, object>("mst.Document_Get", new { APIKey = AppData.GetAPIKey(), ID = id });
            if (raw == null) return null;

            raw.AssignedAgents = string.IsNullOrWhiteSpace(raw.AssignedAgentsJSON)
                ? new List<AssignedAgent>()
                : JsonSerializer.Deserialize<List<AssignedAgent>>(raw.AssignedAgentsJSON) ?? new List<AssignedAgent>();
            return raw;
        }

        public Task<string> AddEdit(Document doc, List<string> agentUserIds, string logUserId) =>
            db.Execute("mst.Document_AddEdit", new
            {
                APIKey = AppData.GetAPIKey(),
                doc.DocumentID,
                doc.Title,
                doc.Description,
                doc.StoredFileName,
                doc.OriginalFileName,
                doc.ContentType,
                doc.FileSizeBytes,
                doc.VisibilityScope,
                doc.IsActive,
                AgentUserIDsJSON = JsonSerializer.Serialize(agentUserIds),
                LogUserID = logUserId
            });

        public Task<string> Delete(string id, string logUserId) =>
            db.Execute("mst.Document_Delete", new { APIKey = AppData.GetAPIKey(), ID = id, LogUserID = logUserId });

        public Task<List<AgentDocumentView>> GetListForAgent(string userId) =>
            db.GetList<AgentDocumentView, object>("mst.Document_ListForAgent", new { APIKey = AppData.GetAPIKey(), UserID = userId });

        public Task<Document?> GetForAgent(string id, string userId) =>
            db.Get<Document, object>("mst.Document_GetForAgent", new { APIKey = AppData.GetAPIKey(), ID = id, UserID = userId });

        // Shape returned directly by mst.Document_Get — AssignedAgentsJSON is
        // the raw JSON column, deserialized into AssignedAgents above before
        // handing back a plain Document to callers.
        private class DocumentRaw : Document
        {
            public string? AssignedAgentsJSON { get; set; }
        }
    }
}

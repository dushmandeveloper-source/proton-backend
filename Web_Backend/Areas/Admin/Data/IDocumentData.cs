using Web_Backend.Areas.Admin.Models;

namespace Web_Backend.Areas.Admin.Data
{
    public interface IDocumentData
    {
        Task<List<Document>> GetList(DocumentSearchView search);
        Task<Document?> Get(string id);
        Task<string> AddEdit(Document doc, List<string> agentUserIds, string logUserId);
        Task<string> Delete(string id, string logUserId);

        // Agent portal's own scoped reads.
        Task<List<AgentDocumentView>> GetListForAgent(string userId);
        Task<Document?> GetForAgent(string id, string userId);
    }
}

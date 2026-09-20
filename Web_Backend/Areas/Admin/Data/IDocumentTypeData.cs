using Web_Backend.Areas.Admin.Models;

namespace Web_Backend.Areas.Admin.Data
{
    public interface IDocumentTypeData
    {
        Task<string> AddEdit(DocumentType type);
        Task<List<DocumentType>> List(string isActive = "A");
        Task Delete(string id);
    }
}

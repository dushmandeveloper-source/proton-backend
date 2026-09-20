using DBAccess;
using Web_Backend.Areas.Admin.Models;
using Web_Backend.Classes;

namespace Web_Backend.Areas.Admin.Data
{
    public class DocumentTypeData : IDocumentTypeData
    {
        private readonly IDBAccess db;

        public DocumentTypeData(IDBAccess db)
        {
            this.db = db;
        }

        public Task<string> AddEdit(DocumentType t) =>
            db.Execute("mst.DocumentType_AddEdit", new
            {
                APIKey = AppData.GetAPIKey(),
                TypeID = t.TypeID,
                t.TypeName,
                Description = t.Description ?? "",
                t.SortOrder
            });

        public Task<List<DocumentType>> List(string isActive = "A") =>
            db.GetList<DocumentType, object>("mst.DocumentType_List", new { APIKey = AppData.GetAPIKey(), IsActive = isActive });

        public Task Delete(string id) =>
            db.ExecuteNonQuery("mst.DocumentType_Delete", new { APIKey = AppData.GetAPIKey(), ID = id });
    }
}

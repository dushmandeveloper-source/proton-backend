using DBAccess;
using Web_Backend.Areas.Admin.Models;
using Web_Backend.Classes;

namespace Web_Backend.Areas.Admin.Data
{
    // syst.Guide (0100): study guides / blog posts.
    public interface IGuideData
    {
        Task<List<Guide>> List(bool publicOnly = false);
        Task<Guide?> Get(int id);
        Task<Guide?> GetBySlug(string slug, bool publicOnly);
        Task Save(Guide g);
        Task Delete(int id);
        Task Move(int id, int direction);
        Task Reorder(IEnumerable<int> ids);
    }

    public class GuideData : IGuideData
    {
        private readonly IDBAccess db;
        public GuideData(IDBAccess db) { this.db = db; }

        public Task<List<Guide>> List(bool publicOnly = false) =>
            db.GetList<Guide, object>("syst.Guide_List", new { APIKey = AppData.GetAPIKey(), PublicOnly = publicOnly });

        public Task<Guide?> Get(int id) =>
            db.Get<Guide, object>("syst.Guide_Get", new { APIKey = AppData.GetAPIKey(), GuideID = id, Slug = "", PublicOnly = false });

        public Task<Guide?> GetBySlug(string slug, bool publicOnly) =>
            db.Get<Guide, object>("syst.Guide_Get", new { APIKey = AppData.GetAPIKey(), GuideID = 0, Slug = slug ?? "", PublicOnly = publicOnly });

        public Task Save(Guide g) =>
            db.ExecuteNonQuery("syst.Guide_AddEdit", new
            {
                APIKey = AppData.GetAPIKey(),
                g.GuideID,
                g.Slug,
                CoverImageURL = g.CoverImageURL ?? "",
                g.ContentJSON,
                IsActive = g.IsActive == "I" ? "I" : "A",
            });

        public Task Delete(int id) =>
            db.ExecuteNonQuery("syst.Guide_Delete", new { APIKey = AppData.GetAPIKey(), GuideID = id });

        public Task Reorder(IEnumerable<int> ids) =>
            db.ExecuteNonQuery("syst.Guide_Reorder", new { APIKey = AppData.GetAPIKey(), IdsJSON = System.Text.Json.JsonSerializer.Serialize(ids) });

        public Task Move(int id, int direction) =>
            db.ExecuteNonQuery("syst.Guide_Move", new { APIKey = AppData.GetAPIKey(), GuideID = id, Direction = direction });
    }
}

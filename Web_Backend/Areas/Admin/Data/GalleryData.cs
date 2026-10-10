using DBAccess;
using Web_Backend.Classes;

namespace Web_Backend.Areas.Admin.Data
{
    // syst.GalleryEvent / syst.GalleryPhoto (0105): event albums for /gallery.
    public class GalleryEvent
    {
        public int EventID { get; set; }
        public string Title { get; set; } = "";
        public string Description { get; set; } = "";
        public string Location { get; set; } = "";
        public DateTime? EventDate { get; set; }
        public int SortOrder { get; set; }
        public string IsActive { get; set; } = "A";
        public int PhotoCount { get; set; }
        public string CoverURL { get; set; } = "";
    }

    public class GalleryPhoto
    {
        public int PhotoID { get; set; }
        public int EventID { get; set; }
        public string ImageURL { get; set; } = "";
        public string Caption { get; set; } = "";
        public int SortOrder { get; set; }
    }

    public interface IGalleryData
    {
        Task<List<GalleryEvent>> ListEvents(bool publicOnly = false);
        Task<List<GalleryPhoto>> ListPhotos(int eventId = 0);
        Task<int> SaveEvent(GalleryEvent e);
        Task DeleteEvent(int eventId);
        Task ReorderEvents(IEnumerable<int> ids);
        Task AddPhoto(int eventId, string imageUrl, string caption);
        Task EditPhoto(int photoId, string caption);
        Task DeletePhoto(int photoId);
        Task ReorderPhotos(int eventId, IEnumerable<int> ids);
    }

    public class GalleryData : IGalleryData
    {
        private readonly IDBAccess db;
        public GalleryData(IDBAccess db) { this.db = db; }

        public Task<List<GalleryEvent>> ListEvents(bool publicOnly = false) =>
            db.GetList<GalleryEvent, object>("syst.GalleryEvent_List", new { APIKey = AppData.GetAPIKey(), PublicOnly = publicOnly });

        public Task<List<GalleryPhoto>> ListPhotos(int eventId = 0) =>
            db.GetList<GalleryPhoto, object>("syst.GalleryPhoto_List", new { APIKey = AppData.GetAPIKey(), EventID = eventId });

        public async Task<int> SaveEvent(GalleryEvent e)
        {
            var row = await db.Get<GalleryEvent, object>("syst.GalleryEvent_AddEdit", new
            {
                APIKey = AppData.GetAPIKey(),
                e.EventID,
                e.Title,
                Description = e.Description ?? "",
                Location = e.Location ?? "",
                e.EventDate,
                IsActive = e.IsActive == "I" ? "I" : "A",
            });
            return row?.EventID ?? e.EventID;
        }

        public Task DeleteEvent(int eventId) =>
            db.ExecuteNonQuery("syst.GalleryEvent_Delete", new { APIKey = AppData.GetAPIKey(), EventID = eventId });

        public Task ReorderEvents(IEnumerable<int> ids) =>
            db.ExecuteNonQuery("syst.GalleryEvent_Reorder", new { APIKey = AppData.GetAPIKey(), IdsJSON = System.Text.Json.JsonSerializer.Serialize(ids) });

        public Task AddPhoto(int eventId, string imageUrl, string caption) =>
            db.ExecuteNonQuery("syst.GalleryPhoto_Add", new { APIKey = AppData.GetAPIKey(), EventID = eventId, ImageURL = imageUrl, Caption = caption ?? "" });

        public Task EditPhoto(int photoId, string caption) =>
            db.ExecuteNonQuery("syst.GalleryPhoto_Edit", new { APIKey = AppData.GetAPIKey(), PhotoID = photoId, Caption = caption ?? "" });

        public Task DeletePhoto(int photoId) =>
            db.ExecuteNonQuery("syst.GalleryPhoto_Delete", new { APIKey = AppData.GetAPIKey(), PhotoID = photoId });

        public Task ReorderPhotos(int eventId, IEnumerable<int> ids) =>
            db.ExecuteNonQuery("syst.GalleryPhoto_Reorder", new { APIKey = AppData.GetAPIKey(), EventID = eventId, IdsJSON = System.Text.Json.JsonSerializer.Serialize(ids) });
    }
}

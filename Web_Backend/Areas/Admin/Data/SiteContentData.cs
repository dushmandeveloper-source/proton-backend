using Dapper;
using DBAccess;
using Web_Backend.Areas.Admin.Models;
using Web_Backend.Classes;

namespace Web_Backend.Areas.Admin.Data
{
    // syst.SiteBanner + syst.SiteSetting (0098): public-site content managed
    // from Admin → Site Content and served by SiteApiController.
    public interface ISiteContentData
    {
        Task<List<SiteBanner>> ListBanners(string placement = "", bool publicOnly = false);
        Task<SiteBanner?> GetBanner(int id);
        Task SaveBanner(SiteBanner b);
        Task DeleteBanner(int id);
        Task MoveBanner(int id, int direction);
        Task<Dictionary<string, string>> GetSettings();
        Task SetSetting(string key, string? value);
    }

    public class SiteContentData : ISiteContentData
    {
        private readonly IDBAccess db;
        public SiteContentData(IDBAccess db) { this.db = db; }

        public Task<List<SiteBanner>> ListBanners(string placement = "", bool publicOnly = false) =>
            db.GetList<SiteBanner, object>("syst.SiteBanner_List", new { APIKey = AppData.GetAPIKey(), Placement = placement ?? "", PublicOnly = publicOnly });

        public Task<SiteBanner?> GetBanner(int id) =>
            db.Get<SiteBanner, object>("syst.SiteBanner_Get", new { APIKey = AppData.GetAPIKey(), BannerID = id });

        // @Subtitle/@SubtitleChinese (0108) are sent only for the About placements
        // that use them, so hero/wheel/announcement/festival saves keep working on
        // a database where 0108 hasn't been applied yet.
        public Task SaveBanner(SiteBanner b)
        {
            var p = new DynamicParameters(new
            {
                APIKey = AppData.GetAPIKey(),
                b.BannerID,
                b.Placement,
                Title = b.Title ?? "",
                TitleChinese = b.TitleChinese ?? "",
                ImageURL = b.ImageURL ?? "",
                LinkURL = b.LinkURL ?? "",
                b.StartsAt,
                b.EndsAt,
                IsActive = b.IsActive == "I" ? "I" : "A",
            });
            if (b.Placement is SiteContentCatalog.AboutTeam or SiteContentCatalog.AboutPartner)
            {
                p.Add("Subtitle", b.Subtitle ?? "");
                p.Add("SubtitleChinese", b.SubtitleChinese ?? "");
            }
            return db.ExecuteNonQuery("syst.SiteBanner_AddEdit", p);
        }

        public Task DeleteBanner(int id) =>
            db.ExecuteNonQuery("syst.SiteBanner_Delete", new { APIKey = AppData.GetAPIKey(), BannerID = id });

        public Task MoveBanner(int id, int direction) =>
            db.ExecuteNonQuery("syst.SiteBanner_Move", new { APIKey = AppData.GetAPIKey(), BannerID = id, Direction = direction });

        // Stored rows merged over SiteContentCatalog.Defaults.
        public async Task<Dictionary<string, string>> GetSettings()
        {
            var rows = await db.GetList<SiteSettingRow, object>("syst.SiteSetting_List", new { APIKey = AppData.GetAPIKey() });
            var result = new Dictionary<string, string>(SiteContentCatalog.Defaults);
            foreach (var r in rows) result[r.SettingKey] = r.SettingValue;
            return result;
        }

        public Task SetSetting(string key, string? value) =>
            db.ExecuteNonQuery("syst.SiteSetting_Set", new { APIKey = AppData.GetAPIKey(), SettingKey = key, SettingValue = value ?? "" });
    }
}
